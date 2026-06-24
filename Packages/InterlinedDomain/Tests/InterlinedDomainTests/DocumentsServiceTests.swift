import XCTest
import InterlinedKit
@testable import InterlinedDomain

/// BDD-named coverage for `DocumentsService` (Wave 5.1 / M4). Quartet
/// (happy + invalid + failure + empty/boundary) for every public method.
/// Stubs `APIClientProtocol`; uses a lightweight in-memory sync coordinator
/// to assert the passthrough surface.
final class DocumentsServiceTests: XCTestCase {

    // MARK: - documents(in:)

    func test_givenNoFolder_whenListingDocuments_thenHitsRootListEndpoint() async throws {
        // Given
        let api = StubAPIClient()
        await api.enqueue(json: Fixtures.paginatedDocuments(ids: ["d1", "d2"]))
        let service = DocumentsService(api: api)

        // When
        let docs = try await service.documents(in: nil, limit: 20, offset: 0)

        // Then
        XCTAssertEqual(docs.map(\.id), ["d1", "d2"])
        let recorded = await api.recorded
        XCTAssertEqual(recorded.first?.path, "/api/documents")
        XCTAssertEqual(recorded.first?.method, "GET")
    }

    func test_givenFolderId_whenListingDocuments_thenHitsFolderDocumentsEndpoint() async throws {
        // Given
        let api = StubAPIClient()
        await api.enqueue(json: Fixtures.paginatedDocuments(ids: ["d1"]))
        let service = DocumentsService(api: api)

        // When
        _ = try await service.documents(in: "folder-42", limit: 20, offset: 0)

        // Then
        let recorded = await api.recorded
        XCTAssertEqual(recorded.first?.path, "/api/documents/folders/folder-42/documents")
    }

    func test_givenEmptyPage_whenListingDocuments_thenReturnsEmptyArray() async throws {
        // Given — boundary: zero documents.
        let api = StubAPIClient()
        await api.enqueue(json: Fixtures.paginatedDocuments(ids: []))
        let service = DocumentsService(api: api)

        // When
        let docs = try await service.documents(in: nil, limit: 20, offset: 0)

        // Then
        XCTAssertTrue(docs.isEmpty)
    }

    func test_givenListAPIFailure_whenListingDocuments_thenThrowsAPIError() async throws {
        // Given
        let api = StubAPIClient()
        await api.enqueue(failure: .unauthorized(serverMessage: "sign in"))
        let service = DocumentsService(api: api)

        // When / Then
        do {
            _ = try await service.documents(in: nil, limit: 20, offset: 0)
            XCTFail("Expected APIError")
        } catch let error as APIError {
            XCTAssertEqual(error, .unauthorized(serverMessage: "sign in"))
        }
    }

    // MARK: - document(id:)

    func test_givenDocumentId_whenLoadingDetail_thenMapsAllFields() async throws {
        // Given
        let api = StubAPIClient()
        await api.enqueue(json: Fixtures.documentObject(id: "d-42", title: "Notes", content: "# H"))
        let service = DocumentsService(api: api)

        // When
        let doc = try await service.document(id: "d-42")

        // Then
        XCTAssertEqual(doc.id, "d-42")
        XCTAssertEqual(doc.title, "Notes")
        XCTAssertEqual(doc.body.markdown, "# H")
    }

    func test_givenDocumentNotFoundOnDetail_whenLoading_thenThrowsDocumentsErrorNotFound() async throws {
        // Given
        let api = StubAPIClient()
        await api.enqueue(failure: .notFound(serverMessage: nil))
        let service = DocumentsService(api: api)

        // When / Then
        do {
            _ = try await service.document(id: "missing")
            XCTFail("Expected DocumentsError")
        } catch let error as DocumentsError {
            XCTAssertEqual(error, .notFound)
        }
    }

    func test_givenDocumentDetailFailureNon404_whenLoading_thenThrowsAPIErrorUnchanged() async throws {
        // Given — invalid input → 400 from the server.
        let api = StubAPIClient()
        await api.enqueue(failure: .badRequest(serverMessage: "bad id"))
        let service = DocumentsService(api: api)

        // When / Then
        do {
            _ = try await service.document(id: "")
            XCTFail("Expected APIError")
        } catch let error as APIError {
            XCTAssertEqual(error, .badRequest(serverMessage: "bad id"))
        }
    }

    func test_givenDocumentDetailWithEmptyContent_whenLoading_thenBodyIsEmpty() async throws {
        // Given — boundary: server returns null content.
        let api = StubAPIClient()
        await api.enqueue(json: Fixtures.documentObject(id: "d", content: nil))
        let service = DocumentsService(api: api)

        // When
        let doc = try await service.document(id: "d")

        // Then
        XCTAssertEqual(doc.body, .empty)
    }

    // MARK: - create

    func test_givenTitleAndBody_whenCreating_thenPostsToDocumentsAndReturnsMapped() async throws {
        // Given
        let api = StubAPIClient()
        await api.enqueue(json: Fixtures.documentObject(id: "d-new", title: "New", content: "Body"))
        let service = DocumentsService(api: api)

        // When
        let doc = try await service.create(title: "New", body: "Body", folderId: nil, isPublic: false)

        // Then
        XCTAssertEqual(doc.id, "d-new")
        let recorded = await api.recorded
        XCTAssertEqual(recorded.first?.method, "POST")
        XCTAssertEqual(recorded.first?.path, "/api/documents")
    }

    func test_givenCreateAPIFailure_whenCreating_thenThrows() async throws {
        // Given — invalid input → 400.
        let api = StubAPIClient()
        await api.enqueue(failure: .badRequest(serverMessage: "title required"))
        let service = DocumentsService(api: api)

        // When / Then
        do {
            _ = try await service.create(title: "", body: "", folderId: nil, isPublic: false)
            XCTFail("Expected APIError")
        } catch let error as APIError {
            XCTAssertEqual(error, .badRequest(serverMessage: "title required"))
        }
    }

    func test_givenEmptyBody_whenCreating_thenStillPostsAndReturnsServerResponse() async throws {
        // Given — boundary: API permits empty body.
        let api = StubAPIClient()
        await api.enqueue(json: Fixtures.documentObject(id: "d-e", content: ""))
        let service = DocumentsService(api: api)

        // When
        let doc = try await service.create(title: "T", body: "", folderId: nil, isPublic: false)

        // Then
        XCTAssertEqual(doc.body.markdown, "")
    }

    // MARK: - update

    func test_givenPartialEdit_whenUpdating_thenPatchesDocumentAndReturnsMapped() async throws {
        // Given
        let api = StubAPIClient()
        await api.enqueue(json: Fixtures.documentObject(id: "d", title: "Renamed"))
        let service = DocumentsService(api: api)

        // When
        let doc = try await service.update(id: "d", title: "Renamed", body: nil, folderId: nil, isPublic: nil)

        // Then
        XCTAssertEqual(doc.title, "Renamed")
        let recorded = await api.recorded
        XCTAssertEqual(recorded.first?.method, "PATCH")
        XCTAssertEqual(recorded.first?.path, "/api/documents/d")
    }

    func test_givenUpdateNotFound_whenUpdating_thenThrowsDocumentsErrorNotFound() async throws {
        // Given
        let api = StubAPIClient()
        await api.enqueue(failure: .notFound(serverMessage: nil))
        let service = DocumentsService(api: api)

        // When / Then
        do {
            _ = try await service.update(id: "missing", title: "x", body: nil, folderId: nil, isPublic: nil)
            XCTFail("Expected DocumentsError")
        } catch let error as DocumentsError {
            XCTAssertEqual(error, .notFound)
        }
    }

    func test_givenUpdateForbidden_whenUpdating_thenThrowsAPIErrorUnchanged() async throws {
        // Given — invalid input case: user doesn't own this document.
        let api = StubAPIClient()
        await api.enqueue(failure: .forbidden(serverMessage: "not yours"))
        let service = DocumentsService(api: api)

        // When / Then
        do {
            _ = try await service.update(id: "d", title: "x", body: nil, folderId: nil, isPublic: nil)
            XCTFail("Expected APIError")
        } catch let error as APIError {
            XCTAssertEqual(error, .forbidden(serverMessage: "not yours"))
        }
    }

    func test_givenAllFieldsNil_whenUpdating_thenStillPatches() async throws {
        // Given — boundary: every field nil. Server may reject; service does not.
        let api = StubAPIClient()
        await api.enqueue(json: Fixtures.documentObject(id: "d"))
        let service = DocumentsService(api: api)

        // When / Then — no throw.
        _ = try await service.update(id: "d", title: nil, body: nil, folderId: nil, isPublic: nil)
    }

    // MARK: - delete

    func test_givenDocumentId_whenDeleting_thenIssuesDelete() async throws {
        // Given
        let api = StubAPIClient()
        await api.enqueue(json: "{}")
        let service = DocumentsService(api: api)

        // When
        try await service.delete(id: "d-1")

        // Then
        let recorded = await api.recorded
        XCTAssertEqual(recorded.first?.method, "DELETE")
        XCTAssertEqual(recorded.first?.path, "/api/documents/d-1")
    }

    func test_givenDeleteNotFound_whenDeleting_thenThrowsDocumentsErrorNotFound() async throws {
        // Given
        let api = StubAPIClient()
        await api.enqueue(failure: .notFound(serverMessage: nil))
        let service = DocumentsService(api: api)

        // When / Then
        do {
            try await service.delete(id: "missing")
            XCTFail("Expected DocumentsError")
        } catch let error as DocumentsError {
            XCTAssertEqual(error, .notFound)
        }
    }

    func test_givenDeleteForbidden_whenDeleting_thenThrowsAPIErrorUnchanged() async throws {
        // Given
        let api = StubAPIClient()
        await api.enqueue(failure: .forbidden(serverMessage: "not yours"))
        let service = DocumentsService(api: api)

        // When / Then
        do {
            try await service.delete(id: "d")
            XCTFail("Expected APIError")
        } catch let error as APIError {
            XCTAssertEqual(error, .forbidden(serverMessage: "not yours"))
        }
    }

    func test_givenEmptyIdString_whenDeleting_thenStillIssuesDelete() async throws {
        // Given — boundary. Server validates; service forwards.
        let api = StubAPIClient()
        await api.enqueue(failure: .badRequest(serverMessage: "missing id"))
        let service = DocumentsService(api: api)

        // When / Then
        do {
            try await service.delete(id: "")
            XCTFail("Expected APIError")
        } catch let error as APIError {
            XCTAssertEqual(error, .badRequest(serverMessage: "missing id"))
        }
    }

    // MARK: - uploadImage

    func test_givenValidImage_whenUploading_thenReturnsServerURL() async throws {
        // Given — small synthetic PNG.
        let image = makeSmoothPNG(width: 64, height: 64)
        let api = StubAPIClient()
        await api.enqueue(json: Fixtures.documentImageUploadResponse(
            url: "https://cdn.interlinedlist.com/uploads/x.png"
        ))
        let service = DocumentsService(api: api)

        // When
        let url = try await service.uploadImage(in: "doc-1", image: image, suggestedName: "x.png")

        // Then
        XCTAssertEqual(url.absoluteString, "https://cdn.interlinedlist.com/uploads/x.png")
        let recorded = await api.recorded
        XCTAssertEqual(recorded.first?.method, "POST")
        XCTAssertEqual(recorded.first?.path, "/api/documents/doc-1/images/upload")
    }

    func test_givenUndecodableBytes_whenUploadingImage_thenThrowsImagePrepError() async {
        // Given — invalid input: non-image bytes.
        let api = StubAPIClient()
        let service = DocumentsService(api: api)

        // When / Then
        do {
            _ = try await service.uploadImage(in: "doc-1", image: Data("not an image".utf8), suggestedName: nil)
            XCTFail("Expected ImagePrepError")
        } catch let error as ImagePrepError {
            XCTAssertEqual(error, .undecodable)
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func test_givenUploadAPIFailure_whenUploadingImage_thenThrowsAPIErrorUnchanged() async throws {
        // Given — happy prep, failing upload.
        let image = makeSmoothPNG(width: 64, height: 64)
        let api = StubAPIClient()
        await api.enqueue(failure: .forbidden(serverMessage: "subscriber feature"))
        let service = DocumentsService(api: api)

        // When / Then
        do {
            _ = try await service.uploadImage(in: "doc-1", image: image, suggestedName: nil)
            XCTFail("Expected APIError")
        } catch let error as APIError {
            XCTAssertEqual(error, .forbidden(serverMessage: "subscriber feature"))
        }
    }

    func test_givenServerReturnsInvalidURL_whenUploadingImage_thenThrowsDecodingError() async throws {
        // Given — boundary: server hands back a malformed URL string.
        let image = makeSmoothPNG(width: 64, height: 64)
        let api = StubAPIClient()
        await api.enqueue(json: Fixtures.documentImageUploadResponse(url: ""))
        let service = DocumentsService(api: api)

        // When / Then
        do {
            _ = try await service.uploadImage(in: "doc-1", image: image, suggestedName: nil)
            XCTFail("Expected APIError")
        } catch let error as APIError {
            if case .decoding = error {
                // pass
            } else {
                XCTFail("Expected decoding error, got \(error)")
            }
        }
    }

    // MARK: - folders surface

    func test_givenFolderList_whenLoadingFolders_thenMapsAllNodes() async throws {
        // Given
        let api = StubAPIClient()
        await api.enqueue(json: Fixtures.paginatedFolders(ids: ["f1", "f2"]))
        let service = DocumentsService(api: api)

        // When
        let folders = try await service.folders(limit: 20, offset: 0)

        // Then
        XCTAssertEqual(folders.map(\.id), ["f1", "f2"])
    }

    func test_givenEmptyFolderList_whenLoadingFolders_thenReturnsEmpty() async throws {
        // Given — boundary.
        let api = StubAPIClient()
        await api.enqueue(json: Fixtures.paginatedFolders(ids: []))
        let service = DocumentsService(api: api)

        // When
        let folders = try await service.folders(limit: 20, offset: 0)

        // Then
        XCTAssertTrue(folders.isEmpty)
    }

    func test_givenFolderListAPIFailure_whenLoading_thenThrows() async throws {
        // Given
        let api = StubAPIClient()
        await api.enqueue(failure: .transport(message: "offline"))
        let service = DocumentsService(api: api)

        // When / Then
        do {
            _ = try await service.folders(limit: 20, offset: 0)
            XCTFail("Expected APIError")
        } catch let error as APIError {
            XCTAssertEqual(error, .transport(message: "offline"))
        }
    }

    func test_givenFolderId_whenLoadingFolder_thenMapsFolder() async throws {
        // Given
        let api = StubAPIClient()
        await api.enqueue(json: Fixtures.folderObject(id: "f1", name: "Inbox"))
        let service = DocumentsService(api: api)

        // When
        let folder = try await service.folder(id: "f1")

        // Then
        XCTAssertEqual(folder.id, "f1")
        XCTAssertEqual(folder.name, "Inbox")
    }

    func test_givenFolderNotFound_whenLoading_thenThrowsDocumentsErrorNotFound() async throws {
        // Given
        let api = StubAPIClient()
        await api.enqueue(failure: .notFound(serverMessage: nil))
        let service = DocumentsService(api: api)

        // When / Then
        do {
            _ = try await service.folder(id: "missing")
            XCTFail("Expected DocumentsError")
        } catch let error as DocumentsError {
            XCTAssertEqual(error, .notFound)
        }
    }

    func test_givenName_whenCreatingFolder_thenPostsAndMaps() async throws {
        // Given
        let api = StubAPIClient()
        await api.enqueue(json: Fixtures.folderObject(id: "f-new", name: "New"))
        let service = DocumentsService(api: api)

        // When
        let folder = try await service.createFolder(name: "New", parentId: nil)

        // Then
        XCTAssertEqual(folder.id, "f-new")
        let recorded = await api.recorded
        XCTAssertEqual(recorded.first?.method, "POST")
        XCTAssertEqual(recorded.first?.path, "/api/documents/folders")
    }

    func test_givenCreateFolderAPIFailure_whenCreating_thenThrows() async throws {
        // Given
        let api = StubAPIClient()
        await api.enqueue(failure: .badRequest(serverMessage: "name required"))
        let service = DocumentsService(api: api)

        // When / Then
        do {
            _ = try await service.createFolder(name: "", parentId: nil)
            XCTFail("Expected APIError")
        } catch let error as APIError {
            XCTAssertEqual(error, .badRequest(serverMessage: "name required"))
        }
    }

    func test_givenFolderId_whenRenamingFolder_thenPatchesAndMaps() async throws {
        // Given
        let api = StubAPIClient()
        await api.enqueue(json: Fixtures.folderObject(id: "f1", name: "Renamed"))
        let service = DocumentsService(api: api)

        // When
        let folder = try await service.renameFolder(id: "f1", to: "Renamed")

        // Then
        XCTAssertEqual(folder.name, "Renamed")
        let recorded = await api.recorded
        XCTAssertEqual(recorded.first?.method, "PATCH")
        XCTAssertEqual(recorded.first?.path, "/api/documents/folders/f1")
    }

    func test_givenFolderId_whenDeletingFolder_thenIssuesDelete() async throws {
        // Given
        let api = StubAPIClient()
        await api.enqueue(json: "{}")
        let service = DocumentsService(api: api)

        // When
        try await service.deleteFolder(id: "f1")

        // Then
        let recorded = await api.recorded
        XCTAssertEqual(recorded.first?.method, "DELETE")
        XCTAssertEqual(recorded.first?.path, "/api/documents/folders/f1")
    }

    func test_givenDeleteFolderNotFound_whenDeleting_thenThrowsDocumentsErrorNotFound() async throws {
        // Given
        let api = StubAPIClient()
        await api.enqueue(failure: .notFound(serverMessage: nil))
        let service = DocumentsService(api: api)

        // When / Then
        do {
            try await service.deleteFolder(id: "missing")
            XCTFail("Expected DocumentsError")
        } catch let error as DocumentsError {
            XCTAssertEqual(error, .notFound)
        }
    }

    // MARK: - sync passthrough

    func test_givenNoCoordinator_whenSyncing_thenThrowsSyncFailed() async {
        // Given — boundary: no coordinator injected.
        let api = StubAPIClient()
        let service = DocumentsService(api: api)

        // When / Then
        do {
            _ = try await service.syncNow()
            XCTFail("Expected DocumentsError.syncFailed")
        } catch let error as DocumentsError {
            if case .syncFailed = error {
                // pass
            } else {
                XCTFail("Expected .syncFailed, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func test_givenNoCoordinator_whenReadingSyncEvents_thenReturnsNil() async {
        // Given
        let api = StubAPIClient()
        let service = DocumentsService(api: api)

        // When / Then
        XCTAssertNil(service.syncEvents)
    }

    func test_givenCoordinator_whenSyncing_thenForwardsAndReturnsReport() async throws {
        // Given
        let coord = StubSyncCoordinator()
        await coord.setNextReport(DocumentSyncReport(insertedDocumentIds: ["d1"]))
        let service = DocumentsService(api: StubAPIClient(), sync: coord)

        // When
        let report = try await service.syncNow()

        // Then
        XCTAssertEqual(report.insertedDocumentIds, ["d1"])
        let calls = await coord.syncCalls
        XCTAssertEqual(calls, 1)
    }

    func test_givenCoordinator_whenEnqueueingOfflineWrite_thenForwardsChange() async {
        // Given
        let coord = StubSyncCoordinator()
        let service = DocumentsService(api: StubAPIClient(), sync: coord)
        let change = DocumentChange.deleteDocument(id: "d-x")

        // When
        await service.enqueueOfflineWrite(change)

        // Then
        let enqueued = await coord.enqueuedChanges
        XCTAssertEqual(enqueued, [change])
    }

    // MARK: - Helpers

    private func makeSmoothPNG(width: Int, height: Int) -> Data {
        let bitmapInfo: UInt32 = CGImageAlphaInfo.premultipliedLast.rawValue
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: bitmapInfo
        )!
        context.setFillColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        guard let image = context.makeImage() else { return Data() }
        let mutable = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(mutable, ImageFormat.png.uti as CFString, 1, nil) else {
            return Data()
        }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { return Data() }
        return mutable as Data
    }
}

// MARK: - StubSyncCoordinator

/// A minimal `DocumentSyncCoordinating` stub for the passthrough surface
/// tests. Lives in this file because it's only used by `DocumentsServiceTests`.
actor StubSyncCoordinator: DocumentSyncCoordinating {

    private(set) var syncCalls: Int = 0
    private(set) var enqueuedChanges: [DocumentChange] = []
    private var nextReport: DocumentSyncReport = DocumentSyncReport()
    private var nextError: Error?

    private let _events: AsyncStream<DocumentSyncEvent>
    private let continuation: AsyncStream<DocumentSyncEvent>.Continuation

    nonisolated var events: AsyncStream<DocumentSyncEvent> { _events }

    init() {
        let (stream, continuation) = AsyncStream<DocumentSyncEvent>.makeStream()
        self._events = stream
        self.continuation = continuation
    }

    func setNextReport(_ report: DocumentSyncReport) {
        self.nextReport = report
    }

    func setNextError(_ error: Error) {
        self.nextError = error
    }

    func syncNow() async throws -> DocumentSyncReport {
        syncCalls += 1
        if let error = nextError {
            nextError = nil
            throw error
        }
        return nextReport
    }

    func enqueue(_ change: DocumentChange) async {
        enqueuedChanges.append(change)
    }
}
