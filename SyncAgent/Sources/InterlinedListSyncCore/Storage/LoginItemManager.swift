import Foundation
import ServiceManagement
import os

/// Manages whether the agent launches at login and runs in the background,
/// independent of the main app. In production the main app also registers this
/// agent via `SMAppService.loginItem(identifier:)`; this manager lets the agent
/// self-register (its own "Launch at login" toggle and dev/standalone runs).
public protocol LoginItemManaging: Sendable {
    func isEnabled() -> Bool
    func enable() throws
    func disable() throws
}

public struct LoginItemManager: LoginItemManaging {

    private let logger = Logger(subsystem: SyncConfiguration.logSubsystem, category: "LoginItem")

    public init() {}

    public func isEnabled() -> Bool {
        SMAppService.mainApp.status == .enabled
    }

    public func enable() throws {
        if SMAppService.mainApp.status != .enabled {
            try SMAppService.mainApp.register()
        }
    }

    public func disable() throws {
        if SMAppService.mainApp.status == .enabled {
            try SMAppService.mainApp.unregister()
        }
    }
}

/// No-op login item manager for tests/previews.
public struct NullLoginItemManager: LoginItemManaging {
    public init() {}
    public func isEnabled() -> Bool { false }
    public func enable() throws {}
    public func disable() throws {}
}
