import XCTest
import InterlinedKit
@testable import InterlinedDomain

/// Verifies the DTO → domain mapping for the Documents surface (Wave 5.1 /
/// M4). Mirrors `MapperTests`: nullable wire fields resolve to sensible
/// defaults and no DTO leaks through the boundary.
final class DocumentMappersTests: XCTestCase {

    private let date = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: - Document

    func test_givenFullDocumentDTO_whenMapped_thenAllFieldsRoundTrip() {
        // Given
        let dto = DocumentDTO(
            id: "doc-1",
            title: "Welcome",
            content: "# Hello",
            isPublic: true,
            folderId: "folder-1",
            relativePath: nil,
            createdAt: date,
            updatedAt: date.addingTimeInterval(60),
            deleted: nil
        )

        // When
        let document = Document(from: dto)

        // Then
        XCTAssertEqual(document.id, "doc-1")
        XCTAssertEqual(document.title, "Welcome")
        XCTAssertEqual(document.body.markdown, "# Hello")
        XCTAssertEqual(document.folderId, "folder-1")
        XCTAssertTrue(document.isPublic)
        XCTAssertFalse(document.deleted)
        XCTAssertEqual(document.updatedAt, date.addingTimeInterval(60))
        XCTAssertEqual(document.createdAt, date)
    }

    func test_givenDocumentWithNilContent_whenMapped_thenBodyIsEmpty() {
        // Given — the sync delta omits content; the domain collapses to .empty.
        let dto = DocumentDTO(id: "d", title: "T", content: nil, updatedAt: date)

        // When
        let document = Document(from: dto)

        // Then
        XCTAssertEqual(document.body, .empty)
        XCTAssertEqual(document.body.markdown, "")
    }

    func test_givenDocumentWithNilUpdatedAt_whenMapped_thenFallsBackToCreatedAt() {
        // Given — defensive: API omitted updatedAt; we fall back to createdAt.
        let dto = DocumentDTO(id: "d", title: "T", createdAt: date, updatedAt: nil)

        // When
        let document = Document(from: dto)

        // Then
        XCTAssertEqual(document.updatedAt, date)
    }

    func test_givenDocumentWithNoTimestamps_whenMapped_thenUpdatedAtIsDistantPast() {
        // Given — boundary: both timestamps missing. The engine should always
        // lose any meaningful comparison; distantPast is the floor.
        let dto = DocumentDTO(id: "d", title: "T")

        // When
        let document = Document(from: dto)

        // Then
        XCTAssertEqual(document.updatedAt, .distantPast)
    }

    func test_givenTombstonedDocument_whenMapped_thenDeletedIsTrue() {
        // Given
        let dto = DocumentDTO(id: "d", title: "T", updatedAt: date, deleted: true)

        // When
        let document = Document(from: dto)

        // Then
        XCTAssertTrue(document.deleted)
    }

    func test_givenDocumentWithNilIsPublic_whenMapped_thenDefaultsToFalse() {
        // Given — boundary: API omits isPublic.
        let dto = DocumentDTO(id: "d", title: "T", isPublic: nil, updatedAt: date)

        // When
        let document = Document(from: dto)

        // Then
        XCTAssertFalse(document.isPublic)
    }

    // MARK: - FolderNode

    func test_givenFolderDTO_whenMapped_thenRoundTripsAllFields() {
        // Given
        let dto = DocumentFolderDTO(
            id: "f1",
            name: "Archive",
            parentId: "f0",
            createdAt: date,
            updatedAt: date,
            deleted: false
        )

        // When
        let folder = FolderNode(from: dto)

        // Then
        XCTAssertEqual(folder.id, "f1")
        XCTAssertEqual(folder.name, "Archive")
        XCTAssertEqual(folder.parentId, "f0")
        XCTAssertEqual(folder.createdAt, date)
        XCTAssertFalse(folder.deleted)
    }

    func test_givenFolderWithNilDeletedFlag_whenMapped_thenDeletedIsFalse() {
        // Given
        let dto = DocumentFolderDTO(id: "f", name: "x", deleted: nil)

        // When
        let folder = FolderNode(from: dto)

        // Then
        XCTAssertFalse(folder.deleted)
    }

    // MARK: - FolderTree

    func test_givenFlatFolderList_whenBuildingTree_thenSplitsRootsAndChildren() {
        // Given
        let folders = [
            FolderNode(id: "a", parentId: nil, name: "A"),
            FolderNode(id: "b", parentId: "a", name: "B"),
            FolderNode(id: "c", parentId: nil, name: "C"),
            FolderNode(id: "d", parentId: "a", name: "D")
        ]

        // When
        let tree = FolderTree(folders: folders)

        // Then
        XCTAssertEqual(tree.roots.map(\.id), ["a", "c"])
        XCTAssertEqual(tree.children(of: "a").map(\.id), ["b", "d"])
        XCTAssertEqual(tree.children(of: "c"), [])
        XCTAssertEqual(tree.children(of: nil).map(\.id), ["a", "c"])
    }

    func test_givenTombstonedFolder_whenBuildingTree_thenDropped() {
        // Given — sidebar should never render a deleted folder.
        let folders = [
            FolderNode(id: "a", parentId: nil, name: "A"),
            FolderNode(id: "b", parentId: nil, name: "B", deleted: true)
        ]

        // When
        let tree = FolderTree(folders: folders)

        // Then
        XCTAssertEqual(tree.roots.map(\.id), ["a"])
    }

    func test_givenEmptyFolderList_whenBuildingTree_thenAllProjectionsEmpty() {
        // Given / When
        let tree = FolderTree(folders: [])

        // Then
        XCTAssertTrue(tree.folders.isEmpty)
        XCTAssertTrue(tree.roots.isEmpty)
        XCTAssertEqual(tree.children(of: nil), [])
        XCTAssertEqual(tree.children(of: "anything"), [])
    }

    // MARK: - DocumentChange → DocumentSyncOperation

    func test_givenCreateDocumentChange_whenMapped_thenOperationCarriesAllFields() {
        // Given
        let change = DocumentChange.createDocument(
            id: "d1",
            folderId: "f1",
            title: "Welcome",
            body: "# Hello",
            isPublic: true
        )

        // When
        let op = DocumentSyncOperation(from: change)

        // Then
        XCTAssertEqual(op.operation, "create")
        XCTAssertEqual(op.type, "document")
        XCTAssertEqual(op.id, "d1")
        XCTAssertEqual(op.title, "Welcome")
        XCTAssertEqual(op.content, "# Hello")
        XCTAssertEqual(op.folderId, "f1")
        XCTAssertEqual(op.isPublic, true)
    }

    func test_givenUpdateDocumentChange_whenMapped_thenPartialFieldsAreNil() {
        // Given — only title set; body/folder/isPublic stay nil.
        let change = DocumentChange.updateDocument(
            id: "d1",
            title: "Renamed",
            body: nil,
            folderId: nil,
            isPublic: nil
        )

        // When
        let op = DocumentSyncOperation(from: change)

        // Then
        XCTAssertEqual(op.operation, "update")
        XCTAssertEqual(op.title, "Renamed")
        XCTAssertNil(op.content)
        XCTAssertNil(op.folderId)
        XCTAssertNil(op.isPublic)
    }

    func test_givenDeleteDocumentChange_whenMapped_thenOnlyIdSet() {
        // Given
        let change = DocumentChange.deleteDocument(id: "d1")

        // When
        let op = DocumentSyncOperation(from: change)

        // Then
        XCTAssertEqual(op.operation, "delete")
        XCTAssertEqual(op.type, "document")
        XCTAssertEqual(op.id, "d1")
        XCTAssertNil(op.title)
        XCTAssertNil(op.content)
    }

    func test_givenCreateFolderChange_whenMapped_thenOperationCarriesNameAndParent() {
        // Given
        let change = DocumentChange.createFolder(id: "f1", name: "Inbox", parentId: nil)

        // When
        let op = DocumentSyncOperation(from: change)

        // Then
        XCTAssertEqual(op.operation, "create")
        XCTAssertEqual(op.type, "folder")
        XCTAssertEqual(op.id, "f1")
        XCTAssertEqual(op.name, "Inbox")
        XCTAssertNil(op.parentId)
    }

    func test_givenRenameFolderChange_whenMapped_thenOperationIsUpdateFolder() {
        // Given
        let change = DocumentChange.renameFolder(id: "f1", name: "Archive", parentId: "f0")

        // When
        let op = DocumentSyncOperation(from: change)

        // Then
        XCTAssertEqual(op.operation, "update")
        XCTAssertEqual(op.type, "folder")
        XCTAssertEqual(op.name, "Archive")
        XCTAssertEqual(op.parentId, "f0")
    }

    func test_givenDeleteFolderChange_whenMapped_thenOperationIsDeleteFolder() {
        // Given
        let change = DocumentChange.deleteFolder(id: "f1")

        // When
        let op = DocumentSyncOperation(from: change)

        // Then
        XCTAssertEqual(op.operation, "delete")
        XCTAssertEqual(op.type, "folder")
        XCTAssertEqual(op.id, "f1")
    }

    // MARK: - DocumentChange.kind / targetId

    func test_givenAnyChange_whenKindRead_thenMatchesEnumCase() {
        XCTAssertEqual(
            DocumentChange.createDocument(id: "d", folderId: nil, title: "T", body: "", isPublic: false).kind,
            .createDocument
        )
        XCTAssertEqual(DocumentChange.deleteDocument(id: "d").kind, .deleteDocument)
        XCTAssertEqual(DocumentChange.createFolder(id: "f", name: "x", parentId: nil).kind, .createFolder)
        XCTAssertEqual(DocumentChange.deleteFolder(id: "f").kind, .deleteFolder)
    }

    func test_givenAnyChange_whenTargetIdRead_thenMatchesEntityId() {
        XCTAssertEqual(DocumentChange.deleteDocument(id: "d-123").targetId, "d-123")
        XCTAssertEqual(DocumentChange.renameFolder(id: "f-456", name: "x", parentId: nil).targetId, "f-456")
    }
}
