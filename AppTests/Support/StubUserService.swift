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
    }
    let kind: Kind
}

final class StubUserService: UserServicing, @unchecked Sendable {

    private let lock = NSLock()

    // MARK: Outcome queues (lock-guarded)

    private var identitiesOutcomes: [Result<[LinkedIdentity], Error>] = []
    private var organizationsOutcomes: [Result<[UserOrganization], Error>] = []

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

    enum StubUserError: Error, Equatable {
        case noOutcome(label: String)
        case malformedURL
    }
}
