// OrgLinkedInViewModel
//
// Drives the organization's shared-LinkedIn section (work-consolidation.md
// G25): credential status, the discovered company pages, per-member page
// assignments, and disconnect.
//
// The route shape drives the design here. `linkedin/status` is the only
// readable route of the four — `GET` on `sync-pages` and on `assignments`
// answers 405 — so the page list and the assignment map both arrive on the
// status response, and every write is followed by a status re-read rather
// than a targeted refetch.
//
// The upstream-failure rule the issue calls out is enforced in `syncPages()`:
// a failed sync must leave the previously-loaded page list on screen so the
// assignment UI stays usable, with the error surfaced separately.
//
// Reads through `OrgServicing` only — no direct API access — so unit tests
// substitute a stub. `@Observable` so SwiftUI re-renders on every state change.
//
// Per decision 0003, the view model consumes only `InterlinedDomain`.

import Foundation
import Observation
import InterlinedDomain

@MainActor
@Observable
final class OrgLinkedInViewModel {

    // MARK: - Dependencies

    private let orgs: OrgServicing
    private let orgId: String

    /// The caller's role from the membership list. Used as the gate before the
    /// status read lands (and as a fallback if status omits `role`).
    private let membershipRole: OrgRole

    // MARK: - Observable state

    /// The org's shared-LinkedIn state. `nil` until the first load.
    private(set) var status: OrgLinkedInStatus?

    private(set) var isLoading: Bool = false
    private(set) var loadError: Error?

    /// True while a sync / assign / disconnect round-trip is in flight.
    private(set) var isWorking: Bool = false

    /// The most recent write error. Separate from `loadError` so a failed
    /// write never blanks the page list the assignment UI needs.
    private(set) var actionError: Error?

    /// True when the last `syncPages()` failed while a page list was already
    /// on screen. The list is deliberately kept — the view shows this as a
    /// "couldn't refresh" hint rather than emptying the assignment UI.
    private(set) var syncFailedWithStalePages: Bool = false

    // MARK: - Init

    init(orgService: OrgServicing, orgId: String, membershipRole: OrgRole) {
        self.orgs = orgService
        self.orgId = orgId
        self.membershipRole = membershipRole
    }

    // MARK: - Derived state

    /// The company pages currently known for the org.
    var pages: [OrgLinkedInPage] { status?.pages ?? [] }

    /// Whether the org has a shared credential connected.
    var isConnected: Bool { status?.isConnected ?? false }

    /// Whether the signed-in user may connect, sync, assign, and disconnect.
    ///
    /// Prefers the role the status route reports (it is authoritative for this
    /// org) and falls back to the membership role before the first load, so
    /// the section does not flash the wrong affordances on appear.
    var canManage: Bool {
        if let status, status.callerRole != nil { return status.callerCanManage }
        switch membershipRole {
        case .owner, .admin: return true
        case .member, .other: return false
        }
    }

    /// The page assigned to `userId`, if any.
    func assignedPage(for userId: String) -> OrgLinkedInPage? {
        status?.assignedPage(for: userId)
    }

    // MARK: - Loading

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            status = try await orgs.linkedInStatus(of: orgId)
            loadError = nil
        } catch {
            loadError = error
        }
    }

    // MARK: - Sync pages

    /// Re-discovers the org's LinkedIn company pages.
    ///
    /// On failure with pages already loaded, the existing list is left intact
    /// and `syncFailedWithStalePages` is set — the assignment UI keeps working
    /// against the stale list, which is what the issue asks for.
    ///
    /// - Returns: the error on failure, `nil` on success / no-op.
    @discardableResult
    func syncPages() async -> Error? {
        guard !isWorking else { return nil }
        isWorking = true
        syncFailedWithStalePages = false
        defer { isWorking = false }
        do {
            status = try await orgs.syncLinkedInPages(of: orgId, callerRole: effectiveRole)
            actionError = nil
            return nil
        } catch {
            actionError = error
            // Keep whatever pages are already on screen; only note that the
            // refresh failed.
            syncFailedWithStalePages = !pages.isEmpty
            return error
        }
    }

    // MARK: - Assign a page

    /// Assigns `userId` to `pageId`, or clears their assignment when `pageId`
    /// is nil, then re-reads status so the rendered assignments match the
    /// server.
    ///
    /// - Returns: the error on failure, `nil` on success / no-op.
    @discardableResult
    func assign(userId: String, pageId: String?) async -> Error? {
        guard !isWorking else { return nil }
        isWorking = true
        defer { isWorking = false }
        do {
            try await orgs.assignLinkedInPage(
                in: orgId,
                userId: userId,
                pageId: pageId,
                callerRole: effectiveRole
            )
            // No read route for assignments — status is where they come back.
            status = try await orgs.linkedInStatus(of: orgId)
            actionError = nil
            return nil
        } catch {
            actionError = error
            return error
        }
    }

    // MARK: - Disconnect

    /// Disconnects the org's shared credential.
    ///
    /// Destructive beyond this screen: every assigned member silently falls
    /// back to their personal LinkedIn identity, so the view must confirm and
    /// say so before calling this.
    ///
    /// - Returns: the error on failure, `nil` on success / no-op.
    @discardableResult
    func disconnect() async -> Error? {
        guard !isWorking else { return nil }
        isWorking = true
        defer { isWorking = false }
        do {
            try await orgs.disconnectLinkedIn(from: orgId, callerRole: effectiveRole)
            // Re-read rather than assuming: the server also clears assignments.
            status = try await orgs.linkedInStatus(of: orgId)
            actionError = nil
            return nil
        } catch {
            actionError = error
            return error
        }
    }

    /// How many members would lose their assigned page if the credential were
    /// disconnected right now. The confirmation names this count, because the
    /// consequence lands on people other than the person clicking.
    var assignedMemberCount: Int {
        (status?.assignments ?? []).filter { $0.pageId != nil }.count
    }

    /// The browser URL that starts the org's LinkedIn OAuth flow, or `nil` if
    /// it cannot be built. Connecting is a redirect flow, not an API call.
    var authorizeURL: URL? {
        orgs.linkedInAuthorizeURL(organizationId: orgId)
    }

    /// The role the service-side gate should see: the status route's answer
    /// when it has one, else the membership role.
    private var effectiveRole: OrgRole? {
        status?.callerRole ?? membershipRole
    }
}
