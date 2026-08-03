// OrganizationsListViewModel
//
// Drives the master list of the signed-in user's organizations and the
// create-org affordance (PLAN.md §1 "Organizations", §6 M6). Renders the
// memberships from `UserService.organizations()` — the membership view
// that carries the caller's own role per org — so the list shows what the
// user belongs to without a second per-org lookup.
//
// Reads through `OrgServicing` (create) and `UserServicing` (list) only —
// no direct API access — so unit tests substitute stubs. `@Observable` so
// SwiftUI re-renders on every state change.
//
// Per decision 0003, the view model consumes only `InterlinedDomain`.

import Foundation
import Observation
import InterlinedDomain

@MainActor
@Observable
final class OrganizationsListViewModel {

    // MARK: - Dependencies

    private let orgs: OrgServicing
    private let user: UserServicing

    // MARK: - Observable state

    /// The signed-in user's org memberships (org + the caller's role).
    private(set) var memberships: [UserOrganization] = []

    private(set) var isLoading: Bool = false
    private(set) var loadError: Error?

    /// True while a background revalidation runs *after* the cache has
    /// already painted the memberships (stale-while-revalidate, PLAN.md §5).
    private(set) var isRefreshing: Bool = false

    /// True once the first load (cache or network) has painted memberships.
    /// Lets the view suppress the blocking spinner once cache is on screen.
    private(set) var hasLoadedOnce: Bool = false

    /// True when a background revalidation failed while cached memberships
    /// were on screen. The list keeps its cached rows; the view surfaces this
    /// as an unobtrusive hint rather than blanking the list.
    private(set) var refreshFailed: Bool = false

    /// Timestamp of the last successful network refresh — drives the TTL.
    private(set) var lastRefreshedAt: Date?

    /// Freshness window: a re-appearing view whose memberships refreshed
    /// within this many seconds skips revalidation and trusts cache.
    static let refreshTTL: TimeInterval = 45

    /// Whether a `.task`-driven re-appearance should revalidate.
    var shouldRefresh: Bool {
        guard let lastRefreshedAt else { return true }
        return Date().timeIntervalSince(lastRefreshedAt) >= Self.refreshTTL
    }

    /// Surfaces a failed create back to the view without clobbering the
    /// list-load error.
    private(set) var createError: Error?

    /// True while a create round-trip is in flight, so the form disables
    /// its submit button and a double-tap can't double-create.
    private(set) var isCreating: Bool = false

    // MARK: - Init

    init(orgService: OrgServicing, userService: UserServicing) {
        self.orgs = orgService
        self.user = userService
    }

    // MARK: - Intents

    /// Loads the signed-in user's organizations, stale-while-revalidate
    /// (PLAN.md §5): on a cold start it paints the cached memberships
    /// immediately (suppressing the blocking spinner) and then revalidates
    /// over the network. A retry / refresh revalidates in place. On a network
    /// failure the prior list is left intact — `loadError` is set only on a
    /// cold-cache failure; `refreshFailed` is set (non-blocking) when cached
    /// rows are on screen. Bound to the view's `.task` and the retry button.
    func load() async {
        guard !isLoading, !isRefreshing else { return }
        // Paint from cache only on the very first load; a manual refresh keeps
        // whatever is already rendered.
        let cachePainted: Bool
        if !hasLoadedOnce {
            let cached = await user.cachedOrganizations()
            if !cached.isEmpty {
                memberships = cached
                hasLoadedOnce = true
                cachePainted = true
            } else {
                cachePainted = false
            }
        } else {
            cachePainted = !memberships.isEmpty
        }

        if cachePainted {
            isRefreshing = true
        } else {
            isLoading = true
        }
        refreshFailed = false
        defer {
            isLoading = false
            isRefreshing = false
        }
        do {
            memberships = try await user.organizations()
            loadError = nil
            hasLoadedOnce = true
            lastRefreshedAt = Date()
        } catch {
            if cachePainted {
                refreshFailed = true
            } else {
                loadError = error
            }
            hasLoadedOnce = true
        }
    }

    /// Creates an organization, prepends it to the list on success, and
    /// surfaces the new org for the caller to navigate to.
    ///
    /// Validates the name client-side: a blank name is rejected before any
    /// service call (the create endpoint requires a name).
    ///
    /// - Returns: the created `Organization` on success, `nil` on validation
    ///   failure or a failed round-trip (inspect `createError`).
    @discardableResult
    func create(name: String, description: String, isPublic: Bool) async -> Organization? {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            createError = OrganizationsListError.emptyName
            return nil
        }
        guard !isCreating else { return nil }
        isCreating = true
        defer { isCreating = false }

        let trimmedDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let created = try await orgs.create(
                name: trimmedName,
                description: trimmedDescription,
                isPublic: isPublic
            )
            // Reflect the new org immediately as a membership (the creator is
            // the owner) so the list updates without a refetch.
            let membership = UserOrganization(
                organization: created,
                role: .owner,
                joinedAt: created.createdAt
            )
            memberships.insert(membership, at: 0)
            createError = nil
            return created
        } catch {
            createError = error
            return nil
        }
    }
}

// MARK: - OrganizationsListError

/// Client-side validation failures surfaced before any network call.
enum OrganizationsListError: LocalizedError, Equatable {
    case emptyName

    var errorDescription: String? {
        switch self {
        case .emptyName:
            return "Enter a name for the organization."
        }
    }
}
