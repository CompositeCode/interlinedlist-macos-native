import Foundation
import InterlinedKit

// MARK: - ListFoldersError

public enum ListFoldersError: Error, Sendable, Equatable {
    /// Creating a folder requires an active subscription. Raised before any
    /// HTTP call when `EntitlementsService.isSubscriber == false` (folders are
    /// explicitly subscriber-only per the live docs, unlike the permissive
    /// list-management gate).
    case subscriberRequired
    /// The folder name was empty or exceeded 80 characters.
    case invalidName
}

extension ListFoldersError: LocalizedError, CustomStringConvertible {
    public var errorDescription: String? { description }
    public var description: String {
        switch self {
        case .subscriberRequired: return "Creating list folders requires an active subscription."
        case .invalidName: return "A folder name must be 1–80 characters."
        }
    }
}

// MARK: - ListFoldersServicing

/// The list-folders surface the App layer codes against (the-gaps.md G6) — read
/// the folder tree, create (subscriber-gated), rename, move, and delete folders.
///
/// Follows the domain-service DI shape and mirrors `ListsService`'s entitlement
/// seam: it consults `EntitlementsService` before a gated write and throws
/// `ListFoldersError.subscriberRequired` on a non-subscriber, before any HTTP.
public protocol ListFoldersServicing: Sendable {
    func folders() async throws -> [ListFolder]
    func tree() async throws -> [ListFolderNode]
    func create(name: String, parentId: String?) async throws -> ListFolder
    func rename(id: String, name: String) async throws -> ListFolder
    func move(id: String, toParent parentId: String?) async throws -> ListFolder
    func delete(id: String) async throws
}

public extension ListFoldersServicing {
    func create(name: String) async throws -> ListFolder {
        try await create(name: name, parentId: nil)
    }
}

// MARK: - ListFoldersService

public final class ListFoldersService: ListFoldersServicing {

    private let api: APIClientProtocol
    private let entitlements: EntitlementsService

    public init(
        api: APIClientProtocol,
        entitlements: EntitlementsService = EntitlementsService(customerStatus: .free)
    ) {
        self.api = api
        self.entitlements = entitlements
    }

    public func folders() async throws -> [ListFolder] {
        let dto = try await api.send(ListFolders.list())
        return dto.folders.map(ListFolder.init(from:))
    }

    public func tree() async throws -> [ListFolderNode] {
        ListFolder.tree(from: try await folders())
    }

    public func create(name: String, parentId: String?) async throws -> ListFolder {
        guard entitlements.isSubscriber else { throw ListFoldersError.subscriberRequired }
        let clean = try Self.validate(name)
        let dto = try await api.send(ListFolders.create(CreateListFolderRequest(name: clean, parentId: parentId)))
        return ListFolder(from: dto)
    }

    public func rename(id: String, name: String) async throws -> ListFolder {
        let clean = try Self.validate(name)
        let dto = try await api.send(ListFolders.update(id: id, UpdateListFolderRequest(name: clean)))
        return ListFolder(from: dto)
    }

    public func move(id: String, toParent parentId: String?) async throws -> ListFolder {
        let dto = try await api.send(ListFolders.update(id: id, UpdateListFolderRequest(parentId: parentId)))
        return ListFolder(from: dto)
    }

    public func delete(id: String) async throws {
        try await api.sendVoid(ListFolders.delete(id: id))
    }

    // MARK: - Helpers

    /// Trims and range-checks a folder name (1–80 chars per the API contract).
    private static func validate(_ name: String) throws -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 80 else { throw ListFoldersError.invalidName }
        return trimmed
    }
}
