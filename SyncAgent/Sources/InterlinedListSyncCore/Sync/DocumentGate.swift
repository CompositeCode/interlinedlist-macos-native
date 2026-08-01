import Foundation

/// Serializes operations per document id while letting different documents run
/// concurrently. Prevents a poll-driven cycle and an FSEvents-driven cycle from
/// writing the same file at once, without a global lock.
public actor DocumentGate {

    private var inFlight: [String: [CheckedContinuation<Void, Never>]] = [:]

    public init() {}

    /// Runs `operation` with exclusive access to `id`. Other calls for the same
    /// id wait; calls for other ids proceed in parallel.
    public func run<T: Sendable>(id: String, _ operation: @Sendable () async throws -> T) async rethrows -> T {
        await acquire(id)
        defer { release(id) }
        return try await operation()
    }

    private func acquire(_ id: String) async {
        if inFlight[id] == nil {
            inFlight[id] = []
            return
        }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            inFlight[id, default: []].append(continuation)
        }
    }

    private func release(_ id: String) {
        guard var waiters = inFlight[id] else { return }
        if waiters.isEmpty {
            inFlight[id] = nil
        } else {
            let next = waiters.removeFirst()
            inFlight[id] = waiters
            next.resume()
        }
    }
}
