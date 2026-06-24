// SocialRosterViewModel
//
// Drives the M5 "Followers / Following / Requests" three-tab panel
// rendered by `SocialRosterRootView` (PLAN.md §1 "Follow system",
// §6 M5). Owns the three independent rosters and their pagination
// state so the user can switch tabs without losing position.
//
// Reads through `SocialServicing` only — no direct API access — so
// unit tests substitute a stub service. The view model is `@Observable`
// so SwiftUI re-renders on every state change.
//
// Per decision 0003, the view model consumes only `InterlinedDomain`.

import Foundation
import Observation
import InterlinedDomain

@MainActor
@Observable
final class SocialRosterViewModel {

    // MARK: - Tabs

    /// The three rosters surfaced in the panel. `Identifiable` so the
    /// SwiftUI segmented control drives selection by tag.
    enum Tab: String, CaseIterable, Identifiable, Sendable {
        case followers
        case following
        case requests

        var id: String { rawValue }

        var title: String {
            switch self {
            case .followers: return "Followers"
            case .following: return "Following"
            case .requests: return "Requests"
            }
        }
    }

    // MARK: - Dependencies

    private let social: SocialServicing
    private let bus: NotificationsEventBus?

    /// The user whose rosters we render. Typically the signed-in user
    /// (the Profile-area panel surfaces *my* followers); the M5 brief
    /// allows passing another user later without protocol changes.
    private let targetUserID: String

    /// Page size for follower / following pagination. Mirrors the
    /// kit's default `limit` so we always ask for full pages.
    static let pageSize: Int = 20

    // MARK: - Observable state

    /// Active tab. Persists across rebuilds so a re-render doesn't
    /// snap back to followers.
    var selectedTab: Tab = .followers

    private(set) var followers: [UserSummary] = []
    private(set) var followersHasMore: Bool = false
    private(set) var followersNextOffset: Int?
    private(set) var followersError: Error?

    private(set) var following: [UserSummary] = []
    private(set) var followingHasMore: Bool = false
    private(set) var followingNextOffset: Int?
    private(set) var followingError: Error?

    private(set) var requests: [FollowRequest] = []
    private(set) var requestsError: Error?

    private(set) var isLoadingFollowers: Bool = false
    private(set) var isLoadingFollowing: Bool = false
    private(set) var isLoadingRequests: Bool = false

    // MARK: - Init

    init(
        social: SocialServicing,
        targetUserID: String,
        notificationsEventBus: NotificationsEventBus? = nil
    ) {
        self.social = social
        self.targetUserID = targetUserID
        self.bus = notificationsEventBus
    }

    // MARK: - Intents

    /// Initial load of every tab. Bound to the SwiftUI `.task` on
    /// `SocialRosterRootView`. Each tab loads in parallel so the
    /// segmented control flips between them without a stall.
    func initialLoad() async {
        async let followersTask: Void = loadFollowers(reset: true)
        async let followingTask: Void = loadFollowing(reset: true)
        async let requestsTask: Void = loadRequests()
        _ = await (followersTask, followingTask, requestsTask)
    }

    func loadFollowers(reset: Bool = false) async {
        guard !isLoadingFollowers else { return }
        if reset {
            followers = []
            followersHasMore = false
            followersNextOffset = nil
            followersError = nil
        }
        isLoadingFollowers = true
        defer { isLoadingFollowers = false }
        do {
            let offset = followersNextOffset ?? 0
            let page = try await social.followers(
                of: targetUserID,
                limit: Self.pageSize,
                offset: offset
            )
            if reset {
                followers = page.users
            } else {
                followers.append(contentsOf: page.users)
            }
            followersHasMore = page.hasMore
            followersNextOffset = page.nextOffset
            followersError = nil
        } catch {
            followersError = error
        }
    }

    func loadFollowing(reset: Bool = false) async {
        guard !isLoadingFollowing else { return }
        if reset {
            following = []
            followingHasMore = false
            followingNextOffset = nil
            followingError = nil
        }
        isLoadingFollowing = true
        defer { isLoadingFollowing = false }
        do {
            let offset = followingNextOffset ?? 0
            let page = try await social.following(
                of: targetUserID,
                limit: Self.pageSize,
                offset: offset
            )
            if reset {
                following = page.users
            } else {
                following.append(contentsOf: page.users)
            }
            followingHasMore = page.hasMore
            followingNextOffset = page.nextOffset
            followingError = nil
        } catch {
            followingError = error
        }
    }

    func loadRequests() async {
        guard !isLoadingRequests else { return }
        isLoadingRequests = true
        defer { isLoadingRequests = false }
        do {
            requests = try await social.requests()
            requestsError = nil
        } catch {
            requestsError = error
        }
    }

    /// Approves an inbound follow request. Optimistically drops the
    /// row before the call; on failure, restores the row and surfaces
    /// the error to the caller's view-model state.
    ///
    /// - Returns: the error if the round-trip failed, `nil` on success.
    @discardableResult
    func approve(request: FollowRequest) async -> Error? {
        let snapshot = requests
        requests.removeAll { $0.id == request.id }
        do {
            try await social.approve(userId: request.user.id)
            bus?.post(.requestApproved(requestUserID: request.user.id))
            return nil
        } catch {
            requests = snapshot
            requestsError = error
            return error
        }
    }

    /// Rejects an inbound follow request — symmetric with `approve`.
    @discardableResult
    func reject(request: FollowRequest) async -> Error? {
        let snapshot = requests
        requests.removeAll { $0.id == request.id }
        do {
            try await social.reject(userId: request.user.id)
            bus?.post(.requestRejected(requestUserID: request.user.id))
            return nil
        } catch {
            requests = snapshot
            requestsError = error
            return error
        }
    }
}
