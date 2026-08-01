import Foundation
import Network

/// Reports network reachability so the engine can pause while offline and
/// resync automatically when connectivity returns.
public protocol NetworkMonitoring: Sendable {
    func start()
    func stop()
    /// Snapshot of the current reachability.
    func isCurrentlyOnline() -> Bool
    /// Invoked whenever reachability flips. Called off the main actor.
    func setOnChange(_ handler: @escaping @Sendable (Bool) -> Void)
}

public final class NetworkMonitor: NetworkMonitoring, @unchecked Sendable {

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.interlinedlist.macos.sync.network")
    private let lock = NSLock()
    private var online = true
    private var onChange: (@Sendable (Bool) -> Void)?

    public init() {}

    public func start() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            let isOnline = path.status == .satisfied
            self.lock.lock()
            let changed = isOnline != self.online
            self.online = isOnline
            let handler = self.onChange
            self.lock.unlock()
            if changed { handler?(isOnline) }
        }
        monitor.start(queue: queue)
    }

    public func stop() {
        monitor.cancel()
    }

    public func isCurrentlyOnline() -> Bool {
        lock.lock(); defer { lock.unlock() }
        return online
    }

    public func setOnChange(_ handler: @escaping @Sendable (Bool) -> Void) {
        lock.lock(); defer { lock.unlock() }
        onChange = handler
    }
}

/// Always-online test double.
public struct AlwaysOnlineMonitor: NetworkMonitoring {
    public init() {}
    public func start() {}
    public func stop() {}
    public func isCurrentlyOnline() -> Bool { true }
    public func setOnChange(_ handler: @escaping @Sendable (Bool) -> Void) {}
}
