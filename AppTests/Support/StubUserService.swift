// StubUserService
//
// Deterministic `UserServicing` stub for App-layer view-model tests of the
// M6 Linked-accounts pane (and the Organizations list, which reads the
// user's org memberships). Mirrors the project's other stubs in spirit.
//
// `UserServicing.identityLinkURL(provider:instance:)` is a synchronous,
// non-isolated protocol requirement, so the stub is a lock-guarded
// `final class` (`@unchecked Sendable`) rather than an actor — that lets
// the synchronous requirement be satisfied without `nonisolated` actor
// gymnastics while keeping the FIFO-queue ergonomics of the other stubs.
//
// Returns only `InterlinedDomain` values, so this stub never imports
// `InterlinedKit`.

import Foundation
import InterlinedDomain

struct RecordedUserCall: Sendable, Equatable {
    enum Kind: Sendable, Equatable {
        case identities
        case organizations
        case identityLinkURL(provider: String, instance: String?)
        case requestEmailChange(newEmail: String)
        case uploadAvatar(contentType: String)
        case deleteAccount
        case searchUsers(query: String, limit: Int?)
        case lookupUser(handle: String)
        case blueskyConfigured
        case mastodonConfigured(instance: String)
        case identityLinkURLNative(provider: String, instance: String?)
        case linkIdentityNative(provider: String, code: String, state: String)
    }
    let kind: Kind
}

final class StubUserService: UserServicing, @unchecked Sendable {

    private let lock = NSLock()

    // MARK: Outcome queues (lock-guarded)

    private var identitiesOutcomes: [Result<[LinkedIdentity], Error>] = []
    private var organizationsOutcomes: [Result<[UserOrganization], Error>] = []
    private var requestEmailChangeOutcomes: [Result<Void, Error>] = []
    private var uploadAvatarOutcomes: [Result<URL?, Error>] = []
    private var deleteAccountOutcomes: [Result<Void, Error>] = []
    private var searchUsersOutcomes: [Result<[UserSearchResult], Error>] = []
    private var lookupUserOutcomes: [Result<UserSearchResult?, Error>] = []
    private var blueskyConfiguredOutcomes: [Result<Bool, Error>] = []
    private var mastodonConfiguredOutcomes: [Result<Bool, Error>] = []
    private var linkIdentityNativeOutcomes: [Result<LinkedIdentity, Error>] = []

    /// When set, `identityLinkURL` throws this error instead of returning a
    /// URL — set once in test setup for a deterministic failure-path test.
    private var linkURLError: Error?

    private var _recorded: [RecordedUserCall] = []

    /// Snapshot of recorded calls — safe to read from a test after `await`s.
    var recorded: [RecordedUserCall] {
        lock.lock(); defer { lock.unlock() }
        return _recorded
    }

    // MARK: Test programming

    func enqueueIdentities(success identities: [LinkedIdentity]) {
        lock.lock(); defer { lock.unlock() }
        identitiesOutcomes.append(.success(identities))
    }
    func enqueueIdentities(failure error: Error) {
        lock.lock(); defer { lock.unlock() }
        identitiesOutcomes.append(.failure(error))
    }

    func enqueueOrganizations(success orgs: [UserOrganization]) {
        lock.lock(); defer { lock.unlock() }
        organizationsOutcomes.append(.success(orgs))
    }
    func enqueueOrganizations(failure error: Error) {
        lock.lock(); defer { lock.unlock() }
        organizationsOutcomes.append(.failure(error))
    }

    func enqueueRequestEmailChange(success: Void = ()) {
        lock.lock(); defer { lock.unlock() }
        requestEmailChangeOutcomes.append(.success(()))
    }
    func enqueueRequestEmailChange(failure error: Error) {
        lock.lock(); defer { lock.unlock() }
        requestEmailChangeOutcomes.append(.failure(error))
    }

    func enqueueUploadAvatar(success url: URL?) {
        lock.lock(); defer { lock.unlock() }
        uploadAvatarOutcomes.append(.success(url))
    }
    func enqueueUploadAvatar(failure error: Error) {
        lock.lock(); defer { lock.unlock() }
        uploadAvatarOutcomes.append(.failure(error))
    }

    func enqueueDeleteAccount(success: Void = ()) {
        lock.lock(); defer { lock.unlock() }
        deleteAccountOutcomes.append(.success(()))
    }
    func enqueueDeleteAccount(failure error: Error) {
        lock.lock(); defer { lock.unlock() }
        deleteAccountOutcomes.append(.failure(error))
    }

    func enqueueSearchUsers(success results: [UserSearchResult]) {
        lock.lock(); defer { lock.unlock() }
        searchUsersOutcomes.append(.success(results))
    }
    func enqueueSearchUsers(failure error: Error) {
        lock.lock(); defer { lock.unlock() }
        searchUsersOutcomes.append(.failure(error))
    }
    func enqueueLookupUser(success result: UserSearchResult?) {
        lock.lock(); defer { lock.unlock() }
        lookupUserOutcomes.append(.success(result))
    }
    func enqueueLookupUser(failure error: Error) {
        lock.lock(); defer { lock.unlock() }
        lookupUserOutcomes.append(.failure(error))
    }
    func enqueueBlueskyConfigured(success configured: Bool) {
        lock.lock(); defer { lock.unlock() }
        blueskyConfiguredOutcomes.append(.success(configured))
    }
    func enqueueBlueskyConfigured(failure error: Error) {
        lock.lock(); defer { lock.unlock() }
        blueskyConfiguredOutcomes.append(.failure(error))
    }
    func enqueueMastodonConfigured(success configured: Bool) {
        lock.lock(); defer { lock.unlock() }
        mastodonConfiguredOutcomes.append(.success(configured))
    }
    func enqueueMastodonConfigured(failure error: Error) {
        lock.lock(); defer { lock.unlock() }
        mastodonConfiguredOutcomes.append(.failure(error))
    }
    func enqueueLinkIdentityNative(success identity: LinkedIdentity) {
        lock.lock(); defer { lock.unlock() }
        linkIdentityNativeOutcomes.append(.success(identity))
    }
    func enqueueLinkIdentityNative(failure error: Error) {
        lock.lock(); defer { lock.unlock() }
        linkIdentityNativeOutcomes.append(.failure(error))
    }

    func setLinkURLError(_ error: Error?) {
        lock.lock(); defer { lock.unlock() }
        linkURLError = error
    }

    // MARK: UserServicing

    func identities() async throws -> [LinkedIdentity] {
        try perform(label: "identities", record: .identities) { $0.identitiesOutcomes }
            set: { $0.identitiesOutcomes = $1 }
    }

    func organizations() async throws -> [UserOrganization] {
        try perform(label: "organizations", record: .organizations) { $0.organizationsOutcomes }
            set: { $0.organizationsOutcomes = $1 }
    }

    func identityLinkURL(provider: IdentityProvider, instance: String?) throws -> URL {
        lock.lock()
        _recorded.append(.init(kind: .identityLinkURL(provider: provider.wireToken, instance: instance)))
        let error = linkURLError
        lock.unlock()

        if let error { throw error }

        // Deterministic, decision-0003-shaped URL the LinkedAccounts view
        // model hands to `openURL`. Mirrors the real service's shape
        // (path + link=true) without needing the kit builder.
        var components = URLComponents()
        components.scheme = "https"
        components.host = "interlinedlist.com"
        components.path = "/api/auth/\(provider.wireToken)/authorize"
        var items = [URLQueryItem(name: "link", value: "true")]
        if let instance, !instance.isEmpty {
            items.append(URLQueryItem(name: "instance", value: instance))
        }
        components.queryItems = items
        guard let url = components.url else { throw StubUserError.malformedURL }
        return url
    }

    func requestEmailChange(newEmail: String) async throws {
        try performVoid(label: "requestEmailChange", record: .requestEmailChange(newEmail: newEmail)) {
            $0.requestEmailChangeOutcomes
        } set: {
            $0.requestEmailChangeOutcomes = $1
        }
    }

    func uploadAvatar(imageData: Data, contentType: String) async throws -> URL? {
        try perform(label: "uploadAvatar", record: .uploadAvatar(contentType: contentType)) {
            $0.uploadAvatarOutcomes
        } set: {
            $0.uploadAvatarOutcomes = $1
        }
    }

    func deleteAccount(password: String) async throws {
        try performVoid(label: "deleteAccount", record: .deleteAccount) {
            $0.deleteAccountOutcomes
        } set: {
            $0.deleteAccountOutcomes = $1
        }
    }

    func searchUsers(query: String, limit: Int?) async throws -> [UserSearchResult] {
        try perform(label: "searchUsers", record: .searchUsers(query: query, limit: limit)) { $0.searchUsersOutcomes }
            set: { $0.searchUsersOutcomes = $1 }
    }

    func lookupUser(handle: String) async throws -> UserSearchResult? {
        try perform(label: "lookupUser", record: .lookupUser(handle: handle)) { $0.lookupUserOutcomes }
            set: { $0.lookupUserOutcomes = $1 }
    }

    func blueskyConfigured() async throws -> Bool {
        try perform(label: "blueskyConfigured", record: .blueskyConfigured) { $0.blueskyConfiguredOutcomes }
            set: { $0.blueskyConfiguredOutcomes = $1 }
    }

    func mastodonConfigured(instance: String) async throws -> Bool {
        try perform(label: "mastodonConfigured", record: .mastodonConfigured(instance: instance)) { $0.mastodonConfiguredOutcomes }
            set: { $0.mastodonConfiguredOutcomes = $1 }
    }

    func identityLinkURLNative(provider: IdentityProvider, instance: String?) throws -> URL {
        lock.lock()
        _recorded.append(.init(kind: .identityLinkURLNative(provider: provider.wireToken, instance: instance)))
        let error = linkURLError
        lock.unlock()
        if let error { throw error }
        var components = URLComponents()
        components.scheme = "https"
        components.host = "interlinedlist.com"
        components.path = "/api/auth/\(provider.wireToken)/authorize"
        var items = [URLQueryItem(name: "link", value: "true"),
                     URLQueryItem(name: "redirect_uri", value: "interlinedlist://oauth/callback")]
        if let instance, !instance.isEmpty {
            items.append(URLQueryItem(name: "instance", value: instance))
        }
        components.queryItems = items
        guard let url = components.url else { throw StubUserError.malformedURL }
        return url
    }

    func linkIdentityNative(provider: IdentityProvider, code: String, state: String) async throws -> LinkedIdentity {
        try perform(label: "linkIdentityNative", record: .linkIdentityNative(provider: provider.wireToken, code: code, state: state)) { $0.linkIdentityNativeOutcomes }
            set: { $0.linkIdentityNativeOutcomes = $1 }
    }

    // MARK: - Internals

    private func perform<T>(
        label: String,
        record: RecordedUserCall.Kind,
        get: (StubUserService) -> [Result<T, Error>],
        set: (StubUserService, [Result<T, Error>]) -> Void
    ) throws -> T {
        lock.lock()
        _recorded.append(.init(kind: record))
        var queue = get(self)
        guard !queue.isEmpty else {
            lock.unlock()
            throw StubUserError.noOutcome(label: label)
        }
        let outcome = queue.removeFirst()
        set(self, queue)
        lock.unlock()
        switch outcome {
        case .success(let value): return value
        case .failure(let error): throw error
        }
    }

    /// Variant of `perform` for methods that return `Void` on success.
    private func performVoid(
        label: String,
        record: RecordedUserCall.Kind,
        get: (StubUserService) -> [Result<Void, Error>],
        set: (StubUserService, [Result<Void, Error>]) -> Void
    ) throws {
        lock.lock()
        _recorded.append(.init(kind: record))
        var queue = get(self)
        guard !queue.isEmpty else {
            lock.unlock()
            throw StubUserError.noOutcome(label: label)
        }
        let outcome = queue.removeFirst()
        set(self, queue)
        lock.unlock()
        switch outcome {
        case .success: return
        case .failure(let error): throw error
        }
    }

    enum StubUserError: Error, Equatable {
        case noOutcome(label: String)
        case malformedURL
    }
}
