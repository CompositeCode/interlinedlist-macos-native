import XCTest
@testable import InterlinedKit

/// BDD tests for the work-consolidation.md **G24** Documents routes: the
/// single-call sidebar tree, public documents by user, create-directly-in-a-
/// folder, the move body, and the invite landing.
///
/// The tree fixtures are the **live 2026-09-09 body**, trimmed of ids only —
/// the contract that folders nest via `parentId` while their documents nest
/// inline, and that root documents are a sibling array, is the thing worth
/// pinning, so the tests assert it rather than a hand-simplified shape.
final class DocumentsTreeEndpointTests: XCTestCase {

    private let baseURL = URL(string: "https://stub.local")!

    private func makeClient(
        transport: StubHTTPDataTransport = StubHTTPDataTransport(),
        tokenStore: TokenStore = InMemoryTokenStore(initial: "il_tok_abc")
    ) -> (APIClient, StubHTTPDataTransport) {
        let auth = DefaultAuthTransport(
            tokenStore: tokenStore,
            sessionTransport: StubHTTPDataTransport(),
            sessionEstablisher: NullSessionEstablisher()
        )
        let client = APIClient(baseURL: baseURL, transport: transport, authTransport: auth)
        return (client, transport)
    }

    // MARK: - Builder shape assertions

    func test_givenG24Builders_whenConstructed_thenUseExpectedMethodPathAuth() {
        XCTAssertEqual(Documents.tree().path, "/api/documents/tree")
        XCTAssertEqual(Documents.tree().method, .get)
        XCTAssertEqual(Documents.tree().auth, .bearer)
        // Unpaged by design — the tree returns the whole account in one body.
        XCTAssertNil(Documents.tree().paginationKey)

        // Public: verified live to answer identically with and without a
        // bearer token, and `x-auth-type: none` in the live spec.
        XCTAssertEqual(Documents.publicDocuments(username: "adron").path, "/api/users/adron/documents")
        XCTAssertEqual(Documents.publicDocuments(username: "adron").auth, .none)

        let create = Documents.createInFolder(
            folderId: "f1",
            CreateDocumentInFolderRequest(title: "t", content: "c")
        )
        XCTAssertEqual(create.path, "/api/documents/folders/f1/documents")
        XCTAssertEqual(create.method, .post)
        XCTAssertEqual(create.auth, .bearer)
        XCTAssertNotNil(create.body)

        let move = Documents.move(id: "d1", toFolderId: "f1")
        XCTAssertEqual(move.path, "/api/documents/d1")
        XCTAssertEqual(move.method, .patch)

        // The invite *landing* is public; there is deliberately no accept
        // builder — the claim route is session-cookie-only upstream.
        XCTAssertEqual(Documents.invite(token: "tok").path, "/api/documents/invite/tok")
        XCTAssertEqual(Documents.invite(token: "tok").method, .get)
        XCTAssertEqual(Documents.invite(token: "tok").auth, .none)
    }

    // MARK: - tree — happy path

    func test_givenLiveTreeBody_whenTreeSent_thenNestsDocumentsUnderFoldersAndKeepsRootAsSibling() async throws {
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"""
        {"folders":[{"id":"f-one","name":"One-Folder","parentId":null,
                     "documents":[{"id":"d-nested","title":"a-single-doc",
                                   "relativePath":"a-single-doc.md","isPublic":false}]},
                    {"id":"f-templates","name":"_templates","parentId":null,
                     "documents":[{"id":"d-tpl","title":"Recipe",
                                   "relativePath":"recipe.md","isPublic":false}]},
                    {"id":"f-empty","name":"emptiness","parentId":null,"documents":[]}],
         "rootDocuments":[{"id":"d-root","title":"a-root-doc",
                           "relativePath":"a-root-doc.md","isPublic":false}]}
        """#))

        let tree = try await client.send(Documents.tree())

        XCTAssertEqual(tree.folders.map(\.id), ["f-one", "f-templates", "f-empty"])
        // Documents live *inside* their folder…
        XCTAssertEqual(tree.folders[0].documents.map(\.id), ["d-nested"])
        XCTAssertEqual(tree.folders[0].documents.first?.relativePath, "a-single-doc.md")
        // …and root documents stay a sibling array, never folded into folders.
        XCTAssertEqual(tree.rootDocuments.map(\.id), ["d-root"])
        XCTAssertFalse(tree.folders.contains { $0.id == "d-root" })
        // The server hands back `_templates` inline with real folders.
        XCTAssertTrue(tree.folders.contains { $0.name == "_templates" })
    }

    func test_givenNestedFolders_whenTreeSent_thenNestingIsCarriedByParentIdNotByNesting() async throws {
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"""
        {"folders":[{"id":"f1","name":"Parent","parentId":null,"documents":[]},
                    {"id":"f2","name":"Child","parentId":"f1","documents":[]}],
         "rootDocuments":[]}
        """#))

        let tree = try await client.send(Documents.tree())

        // Both folders are top-level entries in `folders`; the relationship is
        // in `parentId`. A consumer that looked for a nested `folders` array
        // would see a flat two-item list and think the tree had no hierarchy.
        XCTAssertEqual(tree.folders.count, 2)
        XCTAssertNil(tree.folders[0].parentId)
        XCTAssertEqual(tree.folders[1].parentId, "f1")
    }

    // MARK: - tree — boundary

    func test_givenEmptyFolderAndFolderOfOnlySubfolders_whenTreeSent_thenBothDecodeWithNoDocuments() async throws {
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"""
        {"folders":[{"id":"f-empty","name":"emptiness","parentId":null,"documents":[]},
                    {"id":"f-branch","name":"Branch","parentId":null,"documents":[]},
                    {"id":"f-leaf","name":"Leaf","parentId":"f-branch","documents":[]}],
         "rootDocuments":[]}
        """#))

        let tree = try await client.send(Documents.tree())

        XCTAssertTrue(tree.folders.allSatisfy { $0.documents.isEmpty })
        XCTAssertTrue(tree.rootDocuments.isEmpty)
    }

    func test_givenTreeOmittingBothArrays_whenTreeSent_thenDecodesToEmptyRatherThanFailing() async throws {
        // Boundary: a brand-new account, and defensive cover for a slimmer
        // future variant that drops empty keys entirely.
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"{}"#))

        let tree = try await client.send(Documents.tree())

        XCTAssertTrue(tree.folders.isEmpty)
        XCTAssertTrue(tree.rootDocuments.isEmpty)
    }

    func test_givenFolderWithoutDocumentsKey_whenTreeSent_thenDefaultsToEmptyArray() async throws {
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"""
        {"folders":[{"id":"f1","name":"NoKey","parentId":null}],"rootDocuments":[]}
        """#))

        let tree = try await client.send(Documents.tree())

        XCTAssertEqual(tree.folders.first?.documents, [])
    }

    // MARK: - tree — upstream failure

    func test_givenUnauthorized_whenTreeSent_thenSurfacesAnAuthFailure() async throws {
        // A 401 on a bearer request trips the client's session-retry safety
        // net, and the empty session queue then fails at the transport. Both
        // outcomes are correct surfaced errors for this path — the assertion
        // is that the failure reaches the caller, not which of the two it is
        // (same convention as `MessagesEndpointTests`' 401 case).
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"{"error":"sign in"}"#, status: 401))

        do {
            _ = try await client.send(Documents.tree())
            XCTFail("Expected an APIError")
        } catch let error as APIError {
            switch error {
            case .unauthorized, .transport:
                break
            default:
                XCTFail("Expected .unauthorized or .transport, got \(error)")
            }
        }
    }

    // MARK: - tree — invalid body

    func test_givenFolderMissingItsName_whenTreeSent_thenThrowsDecodingError() async throws {
        // Invalid input from upstream: `id`/`name` are the two fields the
        // sidebar cannot render without, so they stay required.
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"{"folders":[{"id":"f1"}],"rootDocuments":[]}"#))

        do {
            _ = try await client.send(Documents.tree())
            XCTFail("Expected a decoding failure")
        } catch let error as APIError {
            guard case .decoding = error else {
                return XCTFail("Expected .decoding, got \(error)")
            }
        }
    }

    // MARK: - publicDocuments

    func test_givenLivePublicDocumentsBody_whenSent_thenDecodesRicherRowsThanTheTree() async throws {
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"""
        {"documents":[{"id":"d1","title":"Railroad Apps to Build for Fun","folderId":null,
                       "relativePath":"railroad-passenger-seating.md",
                       "createdAt":"2026-03-01T22:07:59.037Z",
                       "updatedAt":"2026-03-01T22:08:34.894Z"}],
         "folders":[]}
        """#))

        let result = try await client.send(Documents.publicDocuments(username: "adron"))

        XCTAssertEqual(result.documents.map(\.id), ["d1"])
        // These rows carry timestamps the tree's inline rows do not — the
        // reason the profile column can sort and date them.
        XCTAssertNotNil(result.documents.first?.updatedAt)
        XCTAssertNotNil(result.documents.first?.createdAt)
        XCTAssertTrue(result.folders.isEmpty)
    }

    func test_givenUserWithNothingPublic_whenPublicDocumentsSent_thenDecodesEmptyArrays() async throws {
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"{"documents":[],"folders":[]}"#))

        let result = try await client.send(Documents.publicDocuments(username: "ghost"))

        XCTAssertTrue(result.documents.isEmpty)
        XCTAssertTrue(result.folders.isEmpty)
    }

    func test_givenUnknownUser_whenPublicDocumentsSent_thenThrowsNotFound() async throws {
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"{"error":"User not found"}"#, status: 404))

        do {
            _ = try await client.send(Documents.publicDocuments(username: "nobody"))
            XCTFail("Expected an APIError")
        } catch let error as APIError {
            guard case .notFound = error else {
                return XCTFail("Expected .notFound, got \(error)")
            }
        }
    }

    func test_givenPublicFoldersCarryingNestedDocuments_whenSent_thenStillDecodes() async throws {
        // The live probe only ever saw `"folders":[]`, so the non-empty shape
        // is unverified. Prove the tolerant type survives either possibility
        // rather than discovering it in production.
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"""
        {"documents":[],
         "folders":[{"id":"f1","name":"Public","parentId":null,
                     "documents":[{"id":"d1","title":"Inside"}]}]}
        """#))

        let result = try await client.send(Documents.publicDocuments(username: "adron"))

        XCTAssertEqual(result.folders.first?.documents.map(\.id), ["d1"])
    }

    // MARK: - createInFolder

    func test_givenTitleAndBody_whenCreateInFolderSent_thenPostsToFolderRouteWithNoFolderIdInBody() async throws {
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"""
        {"message":"Document created successfully",
         "document":{"id":"d1","title":"Notes","content":"# Notes","folderId":"f1"}}
        """#, status: 201))

        let response = try await client.send(
            Documents.createInFolder(
                folderId: "f1",
                CreateDocumentInFolderRequest(title: "Notes", content: "# Notes")
            )
        )

        XCTAssertEqual(response.document.id, "d1")
        XCTAssertEqual(response.document.folderId, "f1")

        let received = await transport.received
        XCTAssertEqual(received.last?.url?.path, "/api/documents/folders/f1/documents")
        XCTAssertEqual(received.last?.httpMethod, "POST")
        let body = try XCTUnwrap(received.last?.httpBody)
        let json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: body) as? [String: Any]
        )
        XCTAssertEqual(json["title"] as? String, "Notes")
        // The folder is the path, never the body — mirroring the route's own
        // contract. A `folderId` here would be meaningless at best.
        XCTAssertNil(json["folderId"])
    }

    func test_givenFreeAccount_whenCreateInFolderSent_thenThrowsForbidden() async throws {
        // The route is `x-subscription-tier: subscriber`; the client must
        // surface the 403 rather than swallowing it.
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"{"error":"Subscribe to create documents."}"#, status: 403))

        do {
            _ = try await client.send(
                Documents.createInFolder(
                    folderId: "f1",
                    CreateDocumentInFolderRequest(title: "t", content: "")
                )
            )
            XCTFail("Expected an APIError")
        } catch let error as APIError {
            guard case .forbidden = error else {
                return XCTFail("Expected .forbidden, got \(error)")
            }
        }
    }

    func test_givenEmptyBody_whenCreateInFolderSent_thenStillEncodesBothRequiredKeys() async throws {
        // Boundary: an empty document is legitimate — the editor creates one
        // called "Untitled" with no content at all.
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"{"document":{"id":"d1","title":"Untitled"}}"#, status: 201))

        _ = try await client.send(
            Documents.createInFolder(
                folderId: "f1",
                CreateDocumentInFolderRequest(title: "Untitled", content: "")
            )
        )

        let received = await transport.received
        let body = try XCTUnwrap(received.last?.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["title"] as? String, "Untitled")
        XCTAssertEqual(json["content"] as? String, "")
    }

    // MARK: - move

    func test_givenDestinationFolder_whenMoveSent_thenPatchesWithThatFolderId() async throws {
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"{"document":{"id":"d1","title":"Doc","folderId":"f2"}}"#))

        let response = try await client.send(Documents.move(id: "d1", toFolderId: "f2"))

        XCTAssertEqual(response.document.folderId, "f2")
        let received = await transport.received
        XCTAssertEqual(received.last?.httpMethod, "PATCH")
        let body = try XCTUnwrap(received.last?.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["folderId"] as? String, "f2")
    }

    func test_givenRootDestination_whenMoveSent_thenEncodesAnExplicitNullNotAnOmittedKey() async throws {
        // The whole reason `MoveDocumentRequest` exists. Codable's synthesised
        // encoding would drop a nil `folderId`, and an omitted key means "leave
        // the folder alone" — the document would never reach root.
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"{"document":{"id":"d1","title":"Doc","folderId":null}}"#))

        _ = try await client.send(Documents.move(id: "d1", toFolderId: nil))

        let received = await transport.received
        let body = try XCTUnwrap(received.last?.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertTrue(json.keys.contains("folderId"), "folderId must be present, not omitted")
        XCTAssertTrue(json["folderId"] is NSNull, "folderId must be an explicit null")
    }

    func test_givenMissingDocumentOrFolder_whenMoveSent_thenThrowsNotFound() async throws {
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"{"error":"Document not found"}"#, status: 404))

        do {
            _ = try await client.send(Documents.move(id: "gone", toFolderId: "f2"))
            XCTFail("Expected an APIError")
        } catch let error as APIError {
            guard case .notFound = error else {
                return XCTFail("Expected .notFound, got \(error)")
            }
        }
    }

    // MARK: - invite

    func test_givenResolvableInvite_whenInviteSent_thenDecodesEveryLandingBranchFlag() async throws {
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"""
        {"role":"collaborator","needsAuth":false,"canClaim":true,
         "wrongAccount":false,"accepted":false,"resourceTitle":"Q3 Planning"}
        """#))

        let invite = try await client.send(Documents.invite(token: "xN3v9Qk"))

        XCTAssertEqual(invite.role, "collaborator")
        XCTAssertEqual(invite.canClaim, true)
        XCTAssertEqual(invite.needsAuth, false)
        XCTAssertEqual(invite.wrongAccount, false)
        XCTAssertEqual(invite.accepted, false)
        XCTAssertEqual(invite.resourceTitle, "Q3 Planning")
    }

    func test_givenInviteWithOnlyARole_whenInviteSent_thenOptionalFlagsDecodeAsNil() async throws {
        // Boundary: the success body could not be exercised live (minting an
        // invite is a write), so everything but `role` is optional and must
        // survive being absent.
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"{"role":"watcher"}"#))

        let invite = try await client.send(Documents.invite(token: "tok"))

        XCTAssertEqual(invite.role, "watcher")
        XCTAssertNil(invite.needsAuth)
        XCTAssertNil(invite.canClaim)
        XCTAssertNil(invite.resourceTitle)
    }

    func test_givenUnknownOrExpiredToken_whenInviteSent_thenThrowsNotFound() async throws {
        // VERIFIED live 2026-09-09, unauthenticated, against a fabricated
        // token. Unknown / expired / revoked / deleted are deliberately
        // indistinguishable upstream.
        let (client, transport) = makeClient()
        await transport.enqueue(.json(
            #"{"error":"Invite not found, expired, or revoked","code":"not_found"}"#,
            status: 404
        ))

        do {
            _ = try await client.send(Documents.invite(token: "faketoken"))
            XCTFail("Expected an APIError")
        } catch let error as APIError {
            guard case .notFound = error else {
                return XCTFail("Expected .notFound, got \(error)")
            }
        }
    }

    func test_givenInviteBodyMissingRole_whenInviteSent_thenThrowsDecodingError() async throws {
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"{"resourceTitle":"Q3 Planning"}"#))

        do {
            _ = try await client.send(Documents.invite(token: "tok"))
            XCTFail("Expected a decoding failure")
        } catch let error as APIError {
            guard case .decoding = error else {
                return XCTFail("Expected .decoding, got \(error)")
            }
        }
    }
}
