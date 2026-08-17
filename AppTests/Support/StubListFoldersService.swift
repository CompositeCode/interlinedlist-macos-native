// StubListFoldersService
//
// Deterministic `ListFoldersServicing` stub for App-layer view-model
// tests of the list-folders feature (work-consolidation.md G6). Mirrors the
// project's other stubs: an actor with one FIFO outcome queue per call
// site + a recorded-call log.
//
// `tree()` is not stubbed independently — the real `ListFoldersService`
// derives it from `folders()`, and the view model calls `tree()`. The
// stub therefore backs `tree()` with its own queue so tests can stage the
// assembled tree directly without reconstructing `folders()` mapping.

import Foundation
import InterlinedDomain

struct RecordedListFoldersCall: Sendable, Equatable {
    enum Kind: Sendable, Equatable {
        case folders
        case tree
        case create(name: String, parentId: String?)
        case rename(id: String, name: String)
        case move(id: String, parentId: String?)
        case delete(id: String)
    }
    let kind: Kind
}

actor StubListFoldersService: ListFoldersServicing {

    private var foldersOutcomes: [Result<[ListFolder], Error>] = []
    private var treeOutcomes: [Result<[ListFolderNode], Error>] = []
    private var createOutcomes: [Result<ListFolder, Error>] = []
    private var renameOutcomes: [Result<ListFolder, Error>] = []
    private var moveOutcomes: [Result<ListFolder, Error>] = []
    private var deleteOutcomes: [Result<Void, Error>] = []

    private(set) var recorded: [RecordedListFoldersCall] = []

    // MARK: Programmable enqueue helpers

    func enqueueFolders(success value: [ListFolder]) { foldersOutcomes.append(.success(value)) }
    func enqueueFolders(failure error: Error) { foldersOutcomes.append(.failure(error)) }

    func enqueueTree(success value: [ListFolderNode]) { treeOutcomes.append(.success(value)) }
    func enqueueTree(failure error: Error) { treeOutcomes.append(.failure(error)) }

    func enqueueCreate(success value: ListFolder) { createOutcomes.append(.success(value)) }
    func enqueueCreate(failure error: Error) { createOutcomes.append(.failure(error)) }

    func enqueueRename(success value: ListFolder) { renameOutcomes.append(.success(value)) }
    func enqueueRename(failure error: Error) { renameOutcomes.append(.failure(error)) }

    func enqueueMove(success value: ListFolder) { moveOutcomes.append(.success(value)) }
    func enqueueMove(failure error: Error) { moveOutcomes.append(.failure(error)) }

    func enqueueDeleteSuccess() { deleteOutcomes.append(.success(())) }
    func enqueueDelete(failure error: Error) { deleteOutcomes.append(.failure(error)) }

    // MARK: ListFoldersServicing

    func folders() async throws -> [ListFolder] {
        recorded.append(.init(kind: .folders))
        return try take(&foldersOutcomes, label: "folders")
    }

    func tree() async throws -> [ListFolderNode] {
        recorded.append(.init(kind: .tree))
        return try take(&treeOutcomes, label: "tree")
    }

    func create(name: String, parentId: String?) async throws -> ListFolder {
        recorded.append(.init(kind: .create(name: name, parentId: parentId)))
        return try take(&createOutcomes, label: "create")
    }

    func rename(id: String, name: String) async throws -> ListFolder {
        recorded.append(.init(kind: .rename(id: id, name: name)))
        return try take(&renameOutcomes, label: "rename")
    }

    func move(id: String, toParent parentId: String?) async throws -> ListFolder {
        recorded.append(.init(kind: .move(id: id, parentId: parentId)))
        return try take(&moveOutcomes, label: "move")
    }

    func delete(id: String) async throws {
        recorded.append(.init(kind: .delete(id: id)))
        let _: Void = try take(&deleteOutcomes, label: "delete")
    }

    private func take<T>(_ queue: inout [Result<T, Error>], label: String) throws -> T {
        guard !queue.isEmpty else { throw StubError.noOutcome(label: label) }
        switch queue.removeFirst() {
        case .success(let value): return value
        case .failure(let error): throw error
        }
    }

    enum StubError: Error, Equatable {
        case noOutcome(label: String)
    }
}
