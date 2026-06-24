// StubSocialService
//
// Deterministic `SocialServicing` stub for App-layer view-model
// tests of the M5 Social feature. Mirrors `StubMessagesService` /
// `StubListsService`: an actor with a queued outcome list per call
// site and a recorded-call log.
//
// Every read and write entry point has its own independent FIFO so
// tests can pre-stage outcomes without ordering coupling.

import Foundation
import InterlinedDomain
import InterlinedKit

/// Records one outbound call so a test can assert on intent.
struct RecordedSocialCall: Sendable, Equatable {
    enum Kind: Sendable, Equatable {
        case profile(username: String)
        case status(userId: String)
        case counts(userId: String)
        case followers(userId: String, limit: Int, offset: Int)
        case following(userId: String, limit: Int, offset: Int)
        case follow(userId: String)
        case unfollow(userId: String)
        case approve(userId: String)
        case reject(userId: String)
        case removeFollower(userId: String)
        case mutual(userId: String)
        case requests
    }
    let kind: Kind
}

actor StubSocialService: SocialServicing {

    // MARK: Outcome queues

    private var profileOutcomes: [Result<UserProfile, Error>] = []
    private var statusOutcomes: [Result<FollowStatusDTO, Error>] = []
    private var countsOutcomes: [Result<FollowCounts, Error>] = []
    private var followersOutcomes: [Result<UsersPage, Error>] = []
    private var followingOutcomes: [Result<UsersPage, Error>] = []
    private var followOutcomes: [Result<FollowAction, Error>] = []
    private var unfollowOutcomes: [Result<Void, Error>] = []
    private var approveOutcomes: [Result<Void, Error>] = []
    private var rejectOutcomes: [Result<Void, Error>] = []
    private var removeFollowerOutcomes: [Result<Void, Error>] = []
    private var mutualOutcomes: [Result<MutualCounts, Error>] = []
    private var requestsOutcomes: [Result<[FollowRequest], Error>] = []

    private(set) var recorded: [RecordedSocialCall] = []

    // MARK: Test programming

    func enqueueProfile(success profile: UserProfile) { profileOutcomes.append(.success(profile)) }
    func enqueueProfile(failure error: Error) { profileOutcomes.append(.failure(error)) }

    func enqueueStatus(success dto: FollowStatusDTO) { statusOutcomes.append(.success(dto)) }
    func enqueueStatus(failure error: Error) { statusOutcomes.append(.failure(error)) }

    func enqueueCounts(success counts: FollowCounts) { countsOutcomes.append(.success(counts)) }
    func enqueueCounts(failure error: Error) { countsOutcomes.append(.failure(error)) }

    func enqueueFollowers(success page: UsersPage) { followersOutcomes.append(.success(page)) }
    func enqueueFollowers(failure error: Error) { followersOutcomes.append(.failure(error)) }

    func enqueueFollowing(success page: UsersPage) { followingOutcomes.append(.success(page)) }
    func enqueueFollowing(failure error: Error) { followingOutcomes.append(.failure(error)) }

    func enqueueFollow(success action: FollowAction) { followOutcomes.append(.success(action)) }
    func enqueueFollow(failure error: Error) { followOutcomes.append(.failure(error)) }

    func enqueueUnfollowSuccess() { unfollowOutcomes.append(.success(())) }
    func enqueueUnfollow(failure error: Error) { unfollowOutcomes.append(.failure(error)) }

    func enqueueApproveSuccess() { approveOutcomes.append(.success(())) }
    func enqueueApprove(failure error: Error) { approveOutcomes.append(.failure(error)) }

    func enqueueRejectSuccess() { rejectOutcomes.append(.success(())) }
    func enqueueReject(failure error: Error) { rejectOutcomes.append(.failure(error)) }

    func enqueueRemoveFollowerSuccess() { removeFollowerOutcomes.append(.success(())) }
    func enqueueRemoveFollower(failure error: Error) { removeFollowerOutcomes.append(.failure(error)) }

    func enqueueMutual(success mutual: MutualCounts) { mutualOutcomes.append(.success(mutual)) }
    func enqueueMutual(failure error: Error) { mutualOutcomes.append(.failure(error)) }

    func enqueueRequests(success requests: [FollowRequest]) { requestsOutcomes.append(.success(requests)) }
    func enqueueRequests(failure error: Error) { requestsOutcomes.append(.failure(error)) }

    // MARK: SocialServicing

    func profile(username: String) async throws -> UserProfile {
        recorded.append(.init(kind: .profile(username: username)))
        return try take(&profileOutcomes, label: "profile")
    }

    func status(of userId: String) async throws -> FollowStatusDTO {
        recorded.append(.init(kind: .status(userId: userId)))
        return try take(&statusOutcomes, label: "status")
    }

    func counts(of userId: String) async throws -> FollowCounts {
        recorded.append(.init(kind: .counts(userId: userId)))
        return try take(&countsOutcomes, label: "counts")
    }

    func followers(of userId: String, limit: Int, offset: Int) async throws -> UsersPage {
        recorded.append(.init(kind: .followers(userId: userId, limit: limit, offset: offset)))
        return try take(&followersOutcomes, label: "followers")
    }

    func following(of userId: String, limit: Int, offset: Int) async throws -> UsersPage {
        recorded.append(.init(kind: .following(userId: userId, limit: limit, offset: offset)))
        return try take(&followingOutcomes, label: "following")
    }

    func follow(userId: String) async throws -> FollowAction {
        recorded.append(.init(kind: .follow(userId: userId)))
        return try take(&followOutcomes, label: "follow")
    }

    func unfollow(userId: String) async throws {
        recorded.append(.init(kind: .unfollow(userId: userId)))
        let _: Void = try take(&unfollowOutcomes, label: "unfollow")
    }

    func approve(userId: String) async throws {
        recorded.append(.init(kind: .approve(userId: userId)))
        let _: Void = try take(&approveOutcomes, label: "approve")
    }

    func reject(userId: String) async throws {
        recorded.append(.init(kind: .reject(userId: userId)))
        let _: Void = try take(&rejectOutcomes, label: "reject")
    }

    func removeFollower(userId: String) async throws {
        recorded.append(.init(kind: .removeFollower(userId: userId)))
        let _: Void = try take(&removeFollowerOutcomes, label: "removeFollower")
    }

    func mutual(of userId: String) async throws -> MutualCounts {
        recorded.append(.init(kind: .mutual(userId: userId)))
        return try take(&mutualOutcomes, label: "mutual")
    }

    func requests() async throws -> [FollowRequest] {
        recorded.append(.init(kind: .requests))
        return try take(&requestsOutcomes, label: "requests")
    }

    // MARK: - Internals

    private func take<T>(_ queue: inout [Result<T, Error>], label: String) throws -> T {
        guard !queue.isEmpty else {
            throw StubError.noOutcome(label: label)
        }
        switch queue.removeFirst() {
        case .success(let value): return value
        case .failure(let error): throw error
        }
    }

    enum StubError: Error, Equatable {
        case noOutcome(label: String)
    }
}
