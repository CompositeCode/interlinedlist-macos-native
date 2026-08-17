// ServerTemplatesViewModel
//
// Drives the "Your templates" section of the "New from Template…" picker
// (work-consolidation.md G12). Lists the user's own **server-side** saved template
// documents (`DocumentTemplateRef`), creates a new document from one, and can
// seed the default starter set.
//
// This is deliberately separate from the client-side `DocumentTemplate.builtIn`
// catalog the picker already shows: the built-in section is dependency-free and
// stays exactly as-is, while this view model is the only part that touches the
// network. Load failures are therefore **non-fatal** — they are surfaced in a
// dedicated `loadError` so the built-in section always renders regardless.
//
// After `createFromTemplate` (which the server answers `201` with an empty
// body), the new document is materialized on the server, so this view model
// reloads the injected `DocumentsListViewModel` and returns the freshly-created
// `Document` so the caller can bind the editor to it — mirroring how selecting a
// built-in template routes through `createDocument(from:)`.
//
// Decision 0003 compliance: this file consumes only `InterlinedDomain`.

import Foundation
import Observation
import InterlinedDomain

@MainActor
@Observable
final class ServerTemplatesViewModel {

    private let service: DocumentTemplatesServicing

    /// The documents list the picker feeds into. After a server-template
    /// create, this view model reloads it so the new document appears, then
    /// hands the created document back to the caller to open in the editor.
    private let documentsList: DocumentsListViewModel

    // MARK: - Observable state

    /// The user's saved server-side templates, most-recent order as returned
    /// by the service. Empty until `loadTemplates()` succeeds (or when the
    /// account genuinely has none).
    private(set) var templates: [DocumentTemplateRef] = []

    /// True while the initial `templates()` fetch or a `seedDefaultTemplates()`
    /// round-trip is in flight.
    private(set) var isLoading: Bool = false

    /// True once a `templates()` fetch has completed (success *or* failure) so
    /// the view can distinguish "still loading" from "loaded, but empty" and
    /// only show the empty-state row after the first load resolves.
    private(set) var hasLoaded: Bool = false

    /// Non-fatal error from the most recent failed `templates()` /
    /// `seedDefaultTemplates()` load. Kept separate from the documents-list
    /// error so a server-template failure never blocks the built-in section.
    private(set) var loadError: Error?

    /// Error from the most recent failed `createFromTemplate`. Surfaced to the
    /// picker so the sheet can stay open for a retry.
    private(set) var createError: Error?

    /// Debounce set keyed by server-template id so rapid double-taps on the
    /// same "Your templates" row don't double-fire the create. Also used by
    /// the view to show a per-row in-flight state.
    private(set) var pendingTemplateIDs: Set<DocumentTemplateRef.ID> = []

    /// True when the load has resolved and there are no server templates —
    /// the signal the picker uses to show the "No saved templates yet" row.
    var isEmpty: Bool {
        hasLoaded && templates.isEmpty
    }

    // MARK: - Init

    init(service: DocumentTemplatesServicing, documentsList: DocumentsListViewModel) {
        self.service = service
        self.documentsList = documentsList
    }

    // MARK: - Intents

    /// Loads the user's server templates. Non-fatal: on failure the list is
    /// left empty and `loadError` is set, but the caller keeps rendering the
    /// built-in section. Safe to call repeatedly (e.g. re-open of the sheet).
    func loadTemplates() async {
        isLoading = true
        defer {
            isLoading = false
            hasLoaded = true
        }
        do {
            templates = try await service.templates()
            loadError = nil
        } catch {
            templates = []
            loadError = error
        }
    }

    /// Creates a document from the given server template, then reloads the
    /// documents list so the new document appears, and returns it so the
    /// caller can open it in the editor. Debounced per template id.
    ///
    /// Returns `nil` (and sets `createError`) on failure, or when the same
    /// template already has a create in flight.
    @discardableResult
    func createFromTemplate(_ template: DocumentTemplateRef) async -> Document? {
        guard !pendingTemplateIDs.contains(template.id) else { return nil }
        pendingTemplateIDs.insert(template.id)
        defer { pendingTemplateIDs.remove(template.id) }

        // Snapshot the currently-loaded document ids so the reload can
        // identify the newly-materialized document rather than trusting a
        // positional guess.
        let existingIDs = Set(documentsList.documentsLoaded.map(\.id))
        do {
            try await service.createFromTemplate(templateDocumentId: template.id)
            createError = nil
        } catch {
            createError = error
            return nil
        }

        // The server created the document with an empty `201` body, so reload
        // to surface it, then select + return the newly-appeared one.
        await documentsList.refresh()
        let created = documentsList.documentsLoaded.first { !existingIDs.contains($0.id) }
            ?? documentsList.documentsLoaded.first
        if let created {
            documentsList.select(id: created.id)
        }
        return created
    }

    /// Seeds the account's default starter templates, then reloads the list so
    /// the freshly-seeded templates appear in the "Your templates" section.
    /// Non-fatal like `loadTemplates` — a failure sets `loadError` and leaves
    /// the built-in section intact.
    func seedDefaults() async {
        isLoading = true
        do {
            try await service.seedDefaultTemplates()
            loadError = nil
        } catch {
            isLoading = false
            loadError = error
            return
        }
        // Re-fetch to show what was seeded. `loadTemplates` manages its own
        // `isLoading`/`hasLoaded`, so hand off directly.
        await loadTemplates()
    }
}
