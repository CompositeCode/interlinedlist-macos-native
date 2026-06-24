// DocumentEditorViewModel
//
// Drives the M4 Documents editor + preview pane (PLAN.md §6 M4 — the
// detail column of the three-column `NavigationSplitView`). Owns the
// in-progress edit buffer, the debounced auto-save scheduler, and the
// image-drop handler. Reads through `DocumentsServicing` only.
//
// Auto-save cadence: the view model debounces title / body edits and
// saves 1.5 seconds after the most recent keystroke. The debounce is
// driven by a `ContinuousClock` injectable so tests use an immediate-
// fire clock.
//
// Decision 0003 compliance: this file consumes only `InterlinedDomain`.

import Foundation
import Observation
import InterlinedDomain

@MainActor
@Observable
final class DocumentEditorViewModel {

    /// Debounce interval (PLAN.md §5 — "offline-first" applies; this
    /// is the foreground keystroke debounce, not the sync interval).
    static let autoSaveDebounce: Duration = .milliseconds(1500)

    private let documents: DocumentsServicing
    private let debounce: Duration

    // MARK: - Observable state

    /// The document the editor is editing. `nil` before `bind(to:)` is
    /// called or after the selected document is removed.
    private(set) var document: Document?

    /// The current title buffer. Bound directly to the editor's title
    /// field. Mutations schedule an auto-save.
    var title: String = "" {
        didSet { onUserEdit(field: .title) }
    }

    /// The current Markdown body buffer. Bound directly to the editor's
    /// `TextEditor`. Mutations schedule an auto-save.
    var body: String = "" {
        didSet { onUserEdit(field: .body) }
    }

    /// True while an auto-save round-trip is in flight.
    private(set) var isSaving: Bool = false

    /// Surfaced error from the most recent failed save / image upload.
    /// Cleared on the next successful save.
    private(set) var error: Error?

    /// True when there are unsaved local changes — the buffer differs
    /// from the last successfully-saved document. Used by the editor
    /// chrome to show a "saved" or "saving…" indicator.
    private(set) var hasUnsavedChanges: Bool = false

    /// The conflict-banner state. Set when the documents event loop
    /// surfaces a `conflictResolved` event matching this document.
    /// Cleared when the user dismisses the banner.
    private(set) var conflict: ConflictBannerViewModel.Pending?

    /// One in-flight auto-save task; cancelled and replaced on every
    /// keystroke so only the last edit's save round-trips.
    private var pendingSaveTask: Task<Void, Never>?

    /// Suppresses `onUserEdit` while the view model is internally
    /// re-binding the buffer from a freshly-loaded document.
    private var suppressEdits: Bool = false

    // MARK: - Init

    /// - Parameters:
    ///   - documents: networking seam (a stub in tests).
    ///   - debounce: the debounce window applied to keystroke edits.
    ///     Production passes `autoSaveDebounce`; tests pass
    ///     `.zero` so saves fire on the next event loop turn.
    init(documents: DocumentsServicing, debounce: Duration = autoSaveDebounce) {
        self.documents = documents
        self.debounce = debounce
    }

    // MARK: - Intents

    /// Binds the editor to `document`. Cancels any pending save,
    /// replaces the buffer, and clears the dirty flag.
    func bind(to document: Document?) {
        pendingSaveTask?.cancel()
        pendingSaveTask = nil
        self.document = document
        suppressEdits = true
        defer { suppressEdits = false }
        self.title = document?.title ?? ""
        self.body = document?.body.markdown ?? ""
        self.hasUnsavedChanges = false
        self.error = nil
        self.conflict = nil
    }

    /// Forces an immediate save of the current buffer. Used by the
    /// menu / toolbar "Save" command and by tests so they don't have
    /// to spin the debounce clock.
    func saveNow() async {
        pendingSaveTask?.cancel()
        pendingSaveTask = nil
        await performSave()
    }

    /// Uploads `image` for the current document, returning the hosted
    /// URL the view inserts as a Markdown image reference. On failure
    /// surfaces the error (`DocumentsError.imageTooLargeAfterPrep`
    /// is translated to `DocumentsUIError.imageTooLargeAfterPrep` so
    /// the banner copy stays consistent).
    @discardableResult
    func uploadImage(_ image: Data, suggestedName: String?) async -> URL? {
        guard let document else {
            error = DocumentsUIError.invalidDocumentTitle
            return nil
        }
        do {
            let url = try await documents.uploadImage(
                in: document.id,
                image: image,
                suggestedName: suggestedName
            )
            // Insert a Markdown image reference at the end of the body.
            // Editor view is free to do better when it knows where the
            // cursor is.
            let alt = suggestedName ?? "image"
            let reference = "\n![\(alt)](\(url.absoluteString))\n"
            self.body = (self.body) + reference
            error = nil
            return url
        } catch DocumentsError.imageTooLargeAfterPrep {
            self.error = DocumentsUIError.imageTooLargeAfterPrep
            return nil
        } catch {
            self.error = error
            return nil
        }
    }

    /// Records a conflict for this document (called by the documents
    /// event loop when `DocumentSyncEvent.conflictResolved` fires with
    /// `original == document.id`). The view layer reads `conflict` and
    /// renders the inline banner.
    func recordConflict(preservedAs preservedId: Document.ID, title preservedTitle: String) {
        conflict = .init(preservedId: preservedId, preservedTitle: preservedTitle)
    }

    /// Clears the conflict banner state. Wired to the banner's
    /// "Dismiss" button.
    func dismissConflict() {
        conflict = nil
    }

    // MARK: - Internals

    private enum Field { case title, body }

    private func onUserEdit(field _: Field) {
        guard !suppressEdits, document != nil else { return }
        hasUnsavedChanges = true
        scheduleSave()
    }

    private func scheduleSave() {
        pendingSaveTask?.cancel()
        let interval = debounce
        pendingSaveTask = Task { [weak self] in
            if interval > .zero {
                try? await Task.sleep(for: interval)
            }
            guard let self else { return }
            if Task.isCancelled { return }
            await self.performSave()
        }
    }

    private func performSave() async {
        guard let current = document else { return }
        // Only call the service if the buffer differs from the loaded
        // document — guards against a flurry of saves on rebind.
        let titleChanged = title != current.title
        let bodyChanged = body != current.body.markdown
        guard titleChanged || bodyChanged else {
            hasUnsavedChanges = false
            return
        }
        isSaving = true
        defer { isSaving = false }
        do {
            let updated = try await documents.update(
                id: current.id,
                title: titleChanged ? title : nil,
                body: bodyChanged ? body : nil,
                folderId: nil,
                isPublic: nil
            )
            // Rebind to the server's authoritative copy, suppressing
            // the buffer change so we don't immediately re-schedule a
            // save (the "snapshot + replace" optimistic-UI pattern from
            // the M2 brief — but inverted: the server's value wins).
            document = updated
            suppressEdits = true
            defer { suppressEdits = false }
            title = updated.title
            body = updated.body.markdown
            hasUnsavedChanges = false
            error = nil
        } catch {
            self.error = error
            // Leave the buffer dirty so the next keystroke (or manual
            // save) tries again; do not clobber the user's edits.
        }
    }
}

// MARK: - ConflictBannerViewModel

/// Tiny view-state holder for the inline conflict banner. The editor
/// view model owns one of these per document; the banner view renders
/// it directly.
enum ConflictBannerViewModel {
    struct Pending: Sendable, Equatable {
        public let preservedId: Document.ID
        public let preservedTitle: String

        public init(preservedId: Document.ID, preservedTitle: String) {
            self.preservedId = preservedId
            self.preservedTitle = preservedTitle
        }
    }
}
