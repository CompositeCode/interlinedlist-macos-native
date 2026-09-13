import XCTest
import InterlinedKit
@testable import InterlinedDomain

/// BDD-named coverage for the work-consolidation.md **G24** additions to
/// `DocumentsService`: the single-call sidebar tree, public documents by user,
/// create-directly-in-a-folder (subscriber-gated), move-between-folders, and
/// the invite landing. Quartet per method.
final class DocumentsTreeServiceTests: XCTestCase {

    // MARK: - Fixtures

    /// The live 2026-09-09 tree body, ids shortened. Keeps the two structural
    /// facts under test: folders are flat with `parentId`, documents nest
    /// inside them, and `rootDocuments` is a sibling array.
    private static let liveTree = #"""
    {"folders":[{"id":"f-one","name":"One-Folder","parentId":null,
                 "documents":[{"id":"d-nested","title":"a-single-doc",
                               "relativePath":"a-single-doc.md","isPublic":false}]},
                {"id":"f-templates","name":"_templates","parentId":null,
                 "documents":[{"id":"d-tpl","title":"Recipe","relativePath":"recipe.md"}]},
                {"id":"f-empty","name":"emptiness","parentId":null,"documents":[]}],
     "rootDocuments":[{"id":"d-root","title":"a-root-doc",
                       "relativePath":"a-root-doc.md","isPublic":false}]}
    """#

    private func subscriberService(api: APIClientProtocol) -> DocumentsService {
        DocumentsService(
            api: api,
            entitlementsProvider: { EntitlementsService(customerStatus: .subscriber) }
        )
    }

    // MARK: - documentTree — happy path

    func test_givenLiveTree_whenFetchingTree_thenIndexesDocumentsByFolderAndKeepsRootSeparate() async throws {
        let api = StubAPIClient()
        await api.enqueue(json: Self.liveTree)
        let service = DocumentsService(api: api)

        let tree = try await service.documentTree()

        let recorded = await api.recorded
        XCTAssertEqual(recorded.first?.path, "/api/documents/tree")
        XCTAssertEqual(recorded.first?.method, "GET")

        XCTAssertEqual(tree.documents(in: "f-one").map(\.id), ["d-nested"])
        XCTAssertEqual(tree.documents(in: nil).map(\.id), ["d-root"])
        // Root documents are never folded into a folder.
        XCTAssertNil(tree.documentsByFolder[""])
        XCTAssertEqual(tree.documentCount(in: "f-one"), 1)
        XCTAssertEqual(tree.documentCount(in: "f-empty"), 0)
    }

    func test_givenTreeWithoutFolderIdOnNestedRows_whenFetchingTree_thenStampsTheEnclosingFolder() async throws {
        // The wire omits `folderId` on nested rows — the folder *is* the id.
        // Losing that would break "which folder is this document in?", which
        // the move action depends on.
        let api = StubAPIClient()
        await api.enqueue(json: Self.liveTree)
        let service = DocumentsService(api: api)

        let tree = try await service.documentTree()

        XCTAssertEqual(tree.documents(in: "f-one").first?.folderId, "f-one")
        XCTAssertNil(tree.documents(in: nil).first?.folderId)
        XCTAssertEqual(tree.folderID(ofDocument: "d-nested"), "f-one")
        XCTAssertNil(tree.folderID(ofDocument: "d-root"))
    }

    func test_givenTreeContainingTemplates_whenFetchingTree_thenTemplatesIsFoundButNotOfferedAsADestination() async throws {
        let api = StubAPIClient()
        await api.enqueue(json: Self.liveTree)
        let service = DocumentsService(api: api)

        let tree = try await service.documentTree()

        // Present in the raw folder list, and findable by the template picker…
        XCTAssertEqual(tree.templatesFolderID, "f-templates")
        XCTAssertTrue(tree.folders.contains { $0.name == "_templates" })
        // …but never a browsable folder or a move destination.
        XCTAssertFalse(tree.userFolders.contains { $0.name == "_templates" })
        XCTAssertFalse(tree.moveDestinations.contains { $0.name == "_templates" })
        XCTAssertFalse(tree.folderTree.folders.contains { $0.name == "_templates" })
    }

    func test_givenNestedFolders_whenFetchingTree_thenFolderTreeProjectsTheHierarchy() async throws {
        let api = StubAPIClient()
        await api.enqueue(json: #"""
        {"folders":[{"id":"f1","name":"Parent","parentId":null,"documents":[]},
                    {"id":"f2","name":"Child","parentId":"f1","documents":[]}],
         "rootDocuments":[]}
        """#)
        let service = DocumentsService(api: api)

        let tree = try await service.documentTree()

        XCTAssertEqual(tree.folderTree.roots.map(\.id), ["f1"])
        XCTAssertEqual(tree.folderTree.children(of: "f1").map(\.id), ["f2"])
    }

    // MARK: - documentTree — boundary

    func test_givenEmptyAccount_whenFetchingTree_thenReturnsAnEmptySnapshot() async throws {
        let api = StubAPIClient()
        await api.enqueue(json: #"{"folders":[],"rootDocuments":[]}"#)
        let service = DocumentsService(api: api)

        let tree = try await service.documentTree()

        XCTAssertTrue(tree.folders.isEmpty)
        XCTAssertTrue(tree.rootDocuments.isEmpty)
        XCTAssertEqual(tree.documentCount(in: nil), 0)
        XCTAssertNil(tree.templatesFolderID)
    }

    func test_givenFolderOfOnlySubfolders_whenFetchingTree_thenParentCountsZeroNotItsDescendants() async throws {
        // Direct children only. A parent that rolled up its sub-folders would
        // read as "3 documents" for a folder you can open and find empty.
        let api = StubAPIClient()
        await api.enqueue(json: #"""
        {"folders":[{"id":"f-branch","name":"Branch","parentId":null,"documents":[]},
                    {"id":"f-leaf","name":"Leaf","parentId":"f-branch",
                     "documents":[{"id":"d1","title":"One"},{"id":"d2","title":"Two"}]}],
         "rootDocuments":[]}
        """#)
        let service = DocumentsService(api: api)

        let tree = try await service.documentTree()

        XCTAssertEqual(tree.documentCount(in: "f-branch"), 0)
        XCTAssertEqual(tree.documentCount(in: "f-leaf"), 2)
    }

    // MARK: - documentTree — upstream failure

    func test_givenTreeAPIFailure_whenFetchingTree_thenThrowsAPIError() async throws {
        let api = StubAPIClient()
        await api.enqueue(failure: .unauthorized(serverMessage: "sign in"))
        let service = DocumentsService(api: api)

        do {
            _ = try await service.documentTree()
            XCTFail("Expected APIError")
        } catch let error as APIError {
            XCTAssertEqual(error, .unauthorized(serverMessage: "sign in"))
        }
    }

    // MARK: - publicDocuments — quartet

    func test_givenPublicDocuments_whenFetchingForAUser_thenMapsRichRowsAndEchoesTheHandle() async throws {
        let api = StubAPIClient()
        await api.enqueue(json: #"""
        {"documents":[{"id":"d1","title":"Railroad Apps","folderId":null,
                       "relativePath":"railroad.md",
                       "createdAt":"2026-03-01T22:07:59.037Z",
                       "updatedAt":"2026-03-01T22:08:34.894Z"}],
         "folders":[]}
        """#)
        let service = DocumentsService(api: api)

        let result = try await service.publicDocuments(ofUser: "adron")

        let recorded = await api.recorded
        XCTAssertEqual(recorded.first?.path, "/api/users/adron/documents")
        XCTAssertEqual(result.username, "adron")
        XCTAssertEqual(result.documents.map(\.id), ["d1"])
        // Unlike the tree's summaries these carry a real timestamp, not the
        // `.distantPast` floor.
        XCTAssertNotEqual(result.documents.first?.updatedAt, .distantPast)
    }

    func test_givenBlankUsername_whenFetchingPublicDocuments_thenRefusesBeforeAnyCall() async throws {
        // Invalid input: `/api/users//documents` is a different route. Assert
        // no request was made at all.
        let api = StubAPIClient()
        let service = DocumentsService(api: api)

        do {
            _ = try await service.publicDocuments(ofUser: "   ")
            XCTFail("Expected DocumentsError.notFound")
        } catch let error as DocumentsError {
            XCTAssertEqual(error, .notFound)
        }
        let recorded = await api.recorded
        XCTAssertTrue(recorded.isEmpty, "no HTTP call should be made for a blank handle")
    }

    func test_givenUnknownUser_whenFetchingPublicDocuments_thenMapsNotFoundToDomainError() async throws {
        let api = StubAPIClient()
        await api.enqueue(failure: .notFound(serverMessage: "User not found"))
        let service = DocumentsService(api: api)

        do {
            _ = try await service.publicDocuments(ofUser: "nobody")
            XCTFail("Expected DocumentsError.notFound")
        } catch let error as DocumentsError {
            XCTAssertEqual(error, .notFound)
        }
    }

    func test_givenUserWithNothingPublic_whenFetchingPublicDocuments_thenReportsEmpty() async throws {
        let api = StubAPIClient()
        await api.enqueue(json: #"{"documents":[],"folders":[]}"#)
        let service = DocumentsService(api: api)

        let result = try await service.publicDocuments(ofUser: "ghost")

        XCTAssertTrue(result.isEmpty)
    }

    // MARK: - createDocument(inFolder:) — quartet

    func test_givenSubscriber_whenCreatingInAFolder_thenPostsToTheFolderRoute() async throws {
        let api = StubAPIClient()
        await api.enqueue(json: #"""
        {"message":"Document created successfully",
         "document":{"id":"d1","title":"Notes","content":"# Notes","folderId":"f1"}}
        """#)
        let service = subscriberService(api: api)

        let document = try await service.createDocument(
            inFolder: "f1",
            title: "Notes",
            body: "# Notes",
            isPublic: false,
            relativePath: nil
        )

        let recorded = await api.recorded
        // The folder route, not `POST /api/documents` — which ignores folderId
        // and would have filed this at root.
        XCTAssertEqual(recorded.first?.path, "/api/documents/folders/f1/documents")
        XCTAssertEqual(recorded.first?.method, "POST")
        XCTAssertEqual(document.folderId, "f1")
    }

    func test_givenFreeAccount_whenCreatingInAFolder_thenRefusesBeforeAnyCall() async throws {
        // The gate is local so a free user gets a clear message instead of a
        // bare 403 — and so the app doesn't spend a round-trip to be told no.
        let api = StubAPIClient()
        let service = DocumentsService(
            api: api,
            entitlementsProvider: { EntitlementsService(customerStatus: .free) }
        )

        do {
            _ = try await service.createDocument(
                inFolder: "f1", title: "Notes", body: "", isPublic: false, relativePath: nil
            )
            XCTFail("Expected DocumentsError.subscriberRequired")
        } catch let error as DocumentsError {
            XCTAssertEqual(error, .subscriberRequired)
        }
        let recorded = await api.recorded
        XCTAssertTrue(recorded.isEmpty, "the gate must run before the HTTP call")
    }

    func test_givenServerSideSubscriptionRejection_whenCreatingInAFolder_thenMapsForbiddenToSubscriberRequired() async throws {
        // The server gates this route too. Both gates must produce the same
        // typed error so the UI branches once.
        let api = StubAPIClient()
        await api.enqueue(failure: .forbidden(serverMessage: "Subscribe to create documents."))
        let service = subscriberService(api: api)

        do {
            _ = try await service.createDocument(
                inFolder: "f1", title: "Notes", body: "", isPublic: false, relativePath: nil
            )
            XCTFail("Expected DocumentsError.subscriberRequired")
        } catch let error as DocumentsError {
            XCTAssertEqual(error, .subscriberRequired)
        }
    }

    func test_givenVanishedFolder_whenCreatingInIt_thenMapsNotFoundToDomainError() async throws {
        let api = StubAPIClient()
        await api.enqueue(failure: .notFound(serverMessage: "Folder not found"))
        let service = subscriberService(api: api)

        do {
            _ = try await service.createDocument(
                inFolder: "gone", title: "Notes", body: "", isPublic: false, relativePath: nil
            )
            XCTFail("Expected DocumentsError.notFound")
        } catch let error as DocumentsError {
            XCTAssertEqual(error, .notFound)
        }
    }

    func test_givenEmptyBody_whenCreatingInAFolder_thenStillSucceeds() async throws {
        // Boundary: "New Document" creates an empty buffer titled Untitled.
        let api = StubAPIClient()
        await api.enqueue(json: #"{"document":{"id":"d1","title":"Untitled","folderId":"f1"}}"#)
        let service = subscriberService(api: api)

        let document = try await service.createDocument(
            inFolder: "f1", title: "Untitled", body: "", isPublic: false, relativePath: nil
        )

        XCTAssertEqual(document.body.markdown, "")
        XCTAssertEqual(document.title, "Untitled")
    }

    // MARK: - moveDocument — quartet

    func test_givenDestinationFolder_whenMovingADocument_thenPatchesTheDocumentRoute() async throws {
        let api = StubAPIClient()
        await api.enqueue(json: #"{"document":{"id":"d1","title":"Doc","folderId":"f2"}}"#)
        let service = DocumentsService(api: api)

        let moved = try await service.moveDocument(id: "d1", toFolder: "f2")

        let recorded = await api.recorded
        XCTAssertEqual(recorded.first?.path, "/api/documents/d1")
        XCTAssertEqual(recorded.first?.method, "PATCH")
        XCTAssertEqual(moved.folderId, "f2")
    }

    func test_givenRootDestination_whenMovingADocument_thenReturnsAnUnfiledDocument() async throws {
        // Boundary: "No folder (root)". The explicit-null body is asserted at
        // the kit layer; here the domain contract is that the result is unfiled.
        let api = StubAPIClient()
        await api.enqueue(json: #"{"document":{"id":"d1","title":"Doc","folderId":null}}"#)
        let service = DocumentsService(api: api)

        let moved = try await service.moveDocument(id: "d1", toFolder: nil)

        XCTAssertNil(moved.folderId)
    }

    func test_givenFolderThatNoLongerExists_whenMovingADocument_thenMapsNotFoundToDomainError() async throws {
        // Invalid input as the user experiences it: the sidebar offered a
        // folder that was deleted in another window a moment ago.
        let api = StubAPIClient()
        await api.enqueue(failure: .notFound(serverMessage: "Folder not found"))
        let service = DocumentsService(api: api)

        do {
            _ = try await service.moveDocument(id: "d1", toFolder: "deleted-folder")
            XCTFail("Expected DocumentsError.notFound")
        } catch let error as DocumentsError {
            XCTAssertEqual(error, .notFound)
        }
    }

    func test_givenMoveAPIFailure_whenMovingADocument_thenBubblesTheAPIError() async throws {
        let api = StubAPIClient()
        await api.enqueue(failure: .httpStatus(code: 500, serverMessage: "boom"))
        let service = DocumentsService(api: api)

        do {
            _ = try await service.moveDocument(id: "d1", toFolder: "f2")
            XCTFail("Expected APIError")
        } catch let error as APIError {
            XCTAssertEqual(error, .httpStatus(code: 500, serverMessage: "boom"))
        }
    }

    // MARK: - invite — quartet

    func test_givenResolvableInvite_whenResolving_thenMapsEveryBranchFlagAndThreadsTheToken() async throws {
        let api = StubAPIClient()
        await api.enqueue(json: #"""
        {"role":"collaborator","needsAuth":false,"canClaim":true,
         "wrongAccount":false,"accepted":false,"resourceTitle":"Q3 Planning"}
        """#)
        let service = DocumentsService(api: api)

        let invite = try await service.invite(token: "xN3v9Qk")

        let recorded = await api.recorded
        XCTAssertEqual(recorded.first?.path, "/api/documents/invite/xN3v9Qk")
        XCTAssertEqual(invite.role, "collaborator")
        XCTAssertEqual(invite.resourceTitle, "Q3 Planning")
        XCTAssertTrue(invite.canClaim)
        // The token is not in the response body; it must survive from the
        // request so the landing can build the browser hand-off.
        XCTAssertEqual(invite.token, "xN3v9Qk")
        XCTAssertEqual(
            invite.acceptURL(base: URL(string: "https://interlinedlist.com")!).absoluteString,
            "https://interlinedlist.com/documents/invite/xN3v9Qk"
        )
    }

    func test_givenBlankToken_whenResolvingAnInvite_thenRefusesBeforeAnyCall() async throws {
        let api = StubAPIClient()
        let service = DocumentsService(api: api)

        do {
            _ = try await service.invite(token: " ")
            XCTFail("Expected DocumentsError.notFound")
        } catch let error as DocumentsError {
            XCTAssertEqual(error, .notFound)
        }
        let recorded = await api.recorded
        XCTAssertTrue(recorded.isEmpty)
    }

    func test_givenUnknownOrExpiredToken_whenResolvingAnInvite_thenMapsNotFoundToDomainError() async throws {
        let api = StubAPIClient()
        await api.enqueue(failure: .notFound(serverMessage: "Invite not found, expired, or revoked"))
        let service = DocumentsService(api: api)

        do {
            _ = try await service.invite(token: "faketoken")
            XCTFail("Expected DocumentsError.notFound")
        } catch let error as DocumentsError {
            XCTAssertEqual(error, .notFound)
        }
    }

    func test_givenInviteWithOnlyARole_whenResolving_thenAbsentFlagsBecomeFalse() async throws {
        // Boundary: the success body is unverified live, so the mapper must
        // cope with everything but `role` missing.
        let api = StubAPIClient()
        await api.enqueue(json: #"{"role":"watcher"}"#)
        let service = DocumentsService(api: api)

        let invite = try await service.invite(token: "tok")

        XCTAssertEqual(invite.role, "watcher")
        XCTAssertFalse(invite.needsAuth)
        XCTAssertFalse(invite.canClaim)
        XCTAssertFalse(invite.wrongAccount)
        XCTAssertFalse(invite.accepted)
        XCTAssertNil(invite.resourceTitle)
    }
}
