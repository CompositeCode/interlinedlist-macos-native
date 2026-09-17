// ResolveShareViewModel
//
// Drives `ResolveShareView` — the shared-resource landing shown when the
// user opens a `…/lists/shared/{token}` or `…/documents/shared/{token}`
// link, whether pasted or delivered via the `interlinedlist://` deep-link
// scheme (work-consolidation.md G3).
//
// It resolves the token (`resolveListShare` / `resolveDocumentShare`),
// surfaces the resource title + granted role, and — when the resolved
// share `canClaim` and the user is signed in — offers a "Claim access"
// button that calls the matching claim method. When the resolved share
// `needsAuth` (or no current user is known), the view prompts sign-in
// instead of showing the claim button (ownership-gating: never render an
// enabled-but-broken action).
//
// Reads through `SharingServicing` only; the current-user id is injected
// as a plain `String?` so tests don't need a session graph. A `nil`
// current-user id is the "signed out" signal (mirrors the project's
// ownership-gating convention).
//
// Per decision 0003, this view model consumes only `InterlinedDomain`.

import Foundation
import Observation
import InterlinedDomain

@MainActor
@Observable
final class ResolveShareViewModel {

    // MARK: - Dependencies

    private let service: SharingServicing
    let parsed: ParsedShare
    /// The signed-in user's id, or `nil` when the session is unresolved /
    /// signed out. Drives the sign-in-vs-claim decision.
    private(set) var currentUserID: String?

    // MARK: - Observable state

    /// The resolved share once `resolve()` succeeds. `nil` before the first
    /// resolve or after a resolve failure.
    private(set) var resolved: ResolvedShare?

    /// True while a resolve / claim round-trip is in flight.
    private(set) var isLoading: Bool = false

    /// Surfaced error from the most recent failed resolve / claim.
    private(set) var error: Error?

    /// True once a claim has succeeded — the view swaps to a "You now have
    /// access" confirmation and can offer to open the resource.
    private(set) var didClaim: Bool = false

    /// The claim's authoritative result (resource id + granted role) once
    /// `claim()` succeeds. Lets the caller navigate to the resource.
    private(set) var claim: ShareClaim?

    // MARK: Shared row data (work-consolidation.md G23 / issue #48)

    /// The shared list's rows, read through `GET /api/lists/shared/{token}/data`.
    ///
    /// This is the read-only viewer's missing half: resolving a token gives the
    /// title and the granted role, but until G23 the landing showed nothing of
    /// the list itself. The token is the capability — rows come back with no
    /// session and regardless of the list's `isPublic` flag — so a Viewer link
    /// to a private list renders its contents here.
    private(set) var rows: [ListRow] = []

    /// True while the row read is in flight. Separate from `isLoading` so the
    /// rows section can spin without blocking the claim button.
    private(set) var isLoadingRows: Bool = false

    /// Surfaced error from the row read. Kept apart from `error` so a rows
    /// failure never hides a successfully resolved title and role.
    private(set) var rowsError: Error?

    /// True once the row read resolved, so the view can tell "loading" from
    /// "this list has no rows".
    private(set) var hasLoadedRowsOnce: Bool = false

    /// How many rows the landing previews. A share landing is a preview, not
    /// the full grid — the user opens the list proper once they have access.
    static let rowPageSize: Int = 100

    // MARK: - Init

    init(service: SharingServicing, parsed: ParsedShare, currentUserID: String?) {
        self.service = service
        self.parsed = parsed
        self.currentUserID = currentUserID
    }

    // MARK: - Derived UI state

    /// Whether the resolved share is claimable *and* the user is signed in.
    /// The claim button is shown only when this is true; otherwise the view
    /// shows the sign-in prompt (when auth is needed) or a plain preview.
    var canOfferClaim: Bool {
        guard let resolved else { return false }
        return resolved.canClaim && currentUserID != nil
    }

    /// Whether the view should prompt sign-in: the share needs auth, or the
    /// share is claimable but no current user is resolved yet. Ownership-
    /// gating: a claimable link with an unknown user prompts sign-in rather
    /// than rendering a broken claim button.
    var needsSignIn: Bool {
        guard let resolved else { return false }
        if resolved.needsAuth { return true }
        return resolved.canClaim && currentUserID == nil
    }

    // MARK: - Intents

    /// Resolves the token, populating `resolved` (title / role / claimable),
    /// then — for a list share — reads the first page of its rows.
    ///
    /// The row read runs only after a successful resolve: an unknown, expired,
    /// or revoked token would fail both calls identically, and spending a
    /// second round-trip to learn the same 404 helps nobody.
    func resolve() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            resolved = try await resolveShare()
            error = nil
        } catch {
            resolved = nil
            self.error = error
            return
        }
        if parsed.kind == .list {
            await loadRows()
        }
    }

    /// Reads one page of the shared list's rows. Public so the view can retry
    /// the rows half on its own without re-resolving the token.
    func loadRows() async {
        guard parsed.kind == .list, !isLoadingRows else { return }
        isLoadingRows = true
        rowsError = nil
        defer {
            isLoadingRows = false
            hasLoadedRowsOnce = true
        }
        do {
            let page = try await service.sharedListRows(
                token: parsed.token,
                limit: Self.rowPageSize,
                offset: 0
            )
            rows = page.rows
        } catch {
            rows = []
            rowsError = error
        }
    }

    /// Claims access to the resource. Guarded: does nothing (surfaces no
    /// error) when the current share is not claimable or the user is signed
    /// out — the view never presents the button in that state, but the
    /// guard keeps a programmatic call safe. On success sets `didClaim` and
    /// records the authoritative `ShareClaim`.
    func claimAccess() async {
        guard canOfferClaim else { return }
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let result = try await claimShare()
            claim = result
            didClaim = true
            error = nil
        } catch {
            self.error = error
        }
    }

    /// Updates the known current-user id (e.g. after an in-flow sign-in
    /// resolves). Lets the view re-evaluate `canOfferClaim` / `needsSignIn`
    /// without rebuilding the view model.
    func updateCurrentUser(id: String?) {
        currentUserID = id
    }

    /// Stable column order derived from the loaded rows' field keys, sorted so
    /// the preview renders deterministically. Mirrors `ListDetailViewModel`:
    /// the schema-defined order is not available on a token-scoped read.
    var columns: [String] {
        var seen = Set<String>()
        var ordered: [String] = []
        for row in rows {
            for key in row.fields.keys where !seen.contains(key) {
                seen.insert(key)
                ordered.append(key)
            }
        }
        return ordered.sorted()
    }

    // MARK: - Target dispatch

    private func resolveShare() async throws -> ResolvedShare {
        switch parsed.kind {
        case .list: return try await service.resolveListShare(token: parsed.token)
        case .document: return try await service.resolveDocumentShare(token: parsed.token)
        }
    }

    private func claimShare() async throws -> ShareClaim {
        switch parsed.kind {
        case .list: return try await service.claimListShare(token: parsed.token)
        case .document: return try await service.claimDocumentShare(token: parsed.token)
        }
    }
}
