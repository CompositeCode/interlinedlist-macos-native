// ResolveShareViewModel
//
// Drives `ResolveShareView` — the shared-resource landing shown when the
// user opens a `…/lists/shared/{token}` or `…/documents/shared/{token}`
// link, whether pasted or delivered via the `interlinedlist://` deep-link
// scheme (the-gaps.md G3).
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

    /// Resolves the token, populating `resolved` (title / role / claimable).
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
