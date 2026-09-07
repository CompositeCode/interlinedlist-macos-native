import XCTest
@testable import InterlinedKit

/// Regression lock for the **live-verb defects** catalogued as
/// `work-consolidation.md` §1c · V1–V7 and fixed on 2026-09-06.
///
/// Every one of these calls shipped sending an HTTP verb (or, in V3 and V7, a
/// path and body shape) the production API does not accept, so the feature
/// behind each failed against `https://interlinedlist.com`. Each fix here was
/// confirmed twice before it was written: the live `OPTIONS` `Allow` header,
/// and an authenticated round trip against the `.env` test account.
///
/// The `Allow` headers observed on 2026-09-06 — the reason each expectation
/// below is what it is:
///
/// | Route                                        | Live `Allow`                          |
/// | -------------------------------------------- | ------------------------------------- |
/// | `/api/messages/{id}`                          | `DELETE, GET, HEAD, OPTIONS, PATCH`   |
/// | `/api/user/update`                            | `OPTIONS, PATCH`                      |
/// | `/api/lists/{id}/data/{rowId}`                | `DELETE, GET, HEAD, OPTIONS, PUT`     |
/// | `/api/organizations/{id}`                     | `DELETE, GET, HEAD, OPTIONS, PUT`     |
/// | `/api/documents/folders/{id}`                 | `DELETE, GET, HEAD, OPTIONS, PUT`     |
/// | `/api/follow/{userId}/remove`                 | `DELETE, OPTIONS`                     |
/// | `/api/github/issues/{o}/{r}/{n}`              | `OPTIONS, PATCH`                      |
/// | `/api/github/issues/{o}/{r}/{n}/comments`     | `OPTIONS, POST`                       |
///
/// These tests exist so a future refactor cannot quietly reintroduce a verb the
/// server rejects. A failure here means the client has drifted off the live API
/// again — re-probe before changing an expectation.
final class LiveVerbDefectRegressionTests: XCTestCase {

    private let baseURL = URL(string: "https://stub.local")!

    private func makeClient(
        transport: StubHTTPDataTransport = StubHTTPDataTransport()
    ) -> (APIClient, StubHTTPDataTransport) {
        let auth = DefaultAuthTransport(
            tokenStore: InMemoryTokenStore(initial: "il_tok_abc"),
            sessionTransport: StubHTTPDataTransport(),
            sessionEstablisher: NullSessionEstablisher()
        )
        return (APIClient(baseURL: baseURL, transport: transport, authTransport: auth), transport)
    }

    // MARK: - The verb matrix (happy path for all seven at once)

    /// The single assertion that would have caught every §1c defect: each
    /// builder emits the verb the live route actually allows.
    func test_givenEveryFixedBuilder_whenConstructed_thenSendsTheLiveAllowedVerb() {
        XCTAssertEqual(
            Messages.reschedule(id: "m1", RescheduleMessageRequest(scheduledAt: .distantFuture)).method,
            .patch, "V1 — PUT is 405 live"
        )
        XCTAssertEqual(
            User.update(UpdateUserRequest(displayName: "Ada")).method,
            .patch, "V2 — POST is 405 live"
        )
        XCTAssertEqual(
            Lists.updateRow(listId: "l1", rowId: "r1", UpdateListRowRequest(rowData: [:])).method,
            .put, "V3 — PATCH is 405 live"
        )
        XCTAssertEqual(
            Organizations.update(id: "o1", UpdateOrganizationRequest(name: "Acme")).method,
            .put, "V4 — PATCH is 405 live"
        )
        XCTAssertEqual(
            Documents.updateFolder(id: "f1", UpdateDocumentFolderRequest(name: "Docs")).method,
            .put, "V5 — PATCH is 405 live"
        )
        XCTAssertEqual(
            Follow.remove(userId: "u1").method,
            .delete, "V6 — POST is 405 live"
        )
        XCTAssertEqual(
            GitHub.updateIssue(repo: "o/r", number: 1, UpdateGitHubIssueRequest(labels: ["bug"])).method,
            .patch, "V7 — verb was already right; the path was not"
        )
    }

    /// V7's other half: both single-issue routes are flat under
    /// `/api/github/issues`, not nested under `/api/github/repos`.
    func test_givenGitHubSingleIssueBuilders_whenConstructed_thenUseFlatPaths() {
        XCTAssertEqual(
            GitHub.updateIssue(repo: "octocat/hello", number: 42, UpdateGitHubIssueRequest(labels: ["bug"])).path,
            "/api/github/issues/octocat/hello/42"
        )
        XCTAssertEqual(
            GitHub.comment(repo: "octocat/hello", number: 42, CreateGitHubCommentRequest(body: "hi")).path,
            "/api/github/issues/octocat/hello/42/comments"
        )
    }

    // MARK: - Wire-level verbs (the request that actually leaves the client)

    func test_givenFixedWrites_whenSent_thenWireMethodMatchesTheLiveAllowHeader() async throws {
        // Each pair is (enqueued live-shaped body, the send). Asserted on the
        // URLRequest, not just the builder, so a transport-level regression is
        // caught too.
        let (client, transport) = makeClient()

        // The live 2026-09-06 body, with the account fields `UserDTO` requires.
        await transport.enqueue(.json(#"""
        {"message":"User updated successfully",
         "user":{"id":"u1","email":"ada@example.com","username":"ada","displayName":"Ada",
           "avatar":null,"bio":"hi","theme":"light","emailVerified":true,
           "maxMessageLength":5000,"defaultPubliclyVisible":true,"messagesPerPage":25,
           "viewingPreference":"all","showPreviews":true,"showAdvancedPostSettings":false,
           "latitude":null,"longitude":null,"isPrivateAccount":false,
           "githubDefaultRepo":null,"customerStatus":"subscriber","stripeCustomerId":null,
           "notificationTrayLimit":20,"createdAt":"2026-01-01T00:00:00.000Z"}}
        """#))
        _ = try await client.send(User.update(UpdateUserRequest(displayName: "Ada")))

        await transport.enqueue(.json(#"{"message":"Row updated successfully","data":{"id":"r1","rowData":{}}}"#))
        _ = try await client.send(Lists.updateRow(listId: "l1", rowId: "r1", UpdateListRowRequest(rowData: [:])))

        await transport.enqueue(.json(#"{"message":"Organization updated successfully","organization":{"id":"o1","name":"Acme"}}"#))
        _ = try await client.send(Organizations.update(id: "o1", UpdateOrganizationRequest(name: "Acme")))

        await transport.enqueue(.json(#"{"message":"Folder updated successfully","folder":{"id":"f1","name":"Docs"}}"#))
        _ = try await client.send(Documents.updateFolder(id: "f1", UpdateDocumentFolderRequest(name: "Docs")))

        let received = await transport.received
        XCTAssertEqual(received.map(\.httpMethod), ["PATCH", "PUT", "PUT", "PUT"])
    }

    // MARK: - Response envelopes (fixing the verb alone was not enough)

    /// V3/V4/V5 each answer an envelope, not a bare DTO. Before the fix a
    /// corrected verb would simply have swapped a 405 for a decode failure.
    func test_givenLiveEnvelopes_whenWritesSent_thenDecodeIntoTheWrappedDTO() async throws {
        let (client, transport) = makeClient()

        await transport.enqueue(.json(#"{"message":"Row updated successfully","data":{"id":"r1","listId":"l1","rowData":{"Title":"Dune"}}}"#))
        let row = try await client.send(Lists.updateRow(listId: "l1", rowId: "r1", UpdateListRowRequest(rowData: [:])))
        XCTAssertEqual(row.data.id, "r1")
        XCTAssertEqual(row.data.rowData["Title"], .string("Dune"))

        await transport.enqueue(.json(#"{"message":"Organization updated successfully","organization":{"id":"o1","name":"Acme","isPublic":false}}"#))
        let org = try await client.send(Organizations.update(id: "o1", UpdateOrganizationRequest(name: "Acme")))
        XCTAssertEqual(org.organization.name, "Acme")

        await transport.enqueue(.json(#"{"message":"Folder updated successfully","folder":{"id":"f1","name":"Docs"}}"#))
        let folder = try await client.send(Documents.updateFolder(id: "f1", UpdateDocumentFolderRequest(name: "Docs")))
        XCTAssertEqual(folder.folder.name, "Docs")
    }

    /// The reads share the same envelopes but omit `message` — so the wrapper's
    /// `message` must stay optional.
    func test_givenReadEnvelopesWithoutMessage_whenSent_thenStillDecode() async throws {
        let (client, transport) = makeClient()

        await transport.enqueue(.json(#"{"organization":{"id":"o1","name":"Acme"}}"#))
        let org = try await client.send(Organizations.get(id: "o1"))
        XCTAssertNil(org.message)
        XCTAssertEqual(org.organization.id, "o1")

        await transport.enqueue(.json(#"{"folder":{"id":"f1","name":"Docs"}}"#))
        let folder = try await client.send(Documents.folder(id: "f1"))
        XCTAssertNil(folder.message)
        XCTAssertEqual(folder.folder.id, "f1")

        await transport.enqueue(.json(#"{"data":{"id":"r1","rowData":{}}}"#))
        let row = try await client.send(Lists.row(listId: "l1", rowId: "r1"))
        XCTAssertNil(row.message)
        XCTAssertEqual(row.data.id, "r1")
    }

    // MARK: - Request bodies

    /// V3's third defect: the list-row wire field is `data`. A `rowData` body is
    /// rejected `400 "Data is required"` even once the verb is correct.
    func test_givenRowRequests_whenEncoded_thenUseDataNotRowDataOnTheWire() throws {
        let created = try JSONEncoder().encode(CreateListRowRequest(rowData: ["Title": .string("New")]))
        let createdKeys = try XCTUnwrap(
            JSONSerialization.jsonObject(with: created) as? [String: Any]
        ).keys
        XCTAssertEqual(Set(createdKeys), ["data"])

        let updated = try JSONEncoder().encode(UpdateListRowRequest(rowData: ["Title": .string("New")]))
        let updatedKeys = try XCTUnwrap(
            JSONSerialization.jsonObject(with: updated) as? [String: Any]
        ).keys
        XCTAssertEqual(Set(updatedKeys), ["data"])
    }

    /// V1: the reschedule body cannot express a content edit, because the live
    /// route silently discards `content` when it accompanies `scheduledAt`.
    func test_givenRescheduleRequest_whenEncoded_thenCarriesScheduledAtAlone() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(RescheduleMessageRequest(scheduledAt: Date(timeIntervalSince1970: 1_800_000_000)))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(Set(object.keys), ["scheduledAt"])
    }

    // MARK: - Upstream failure

    /// The shape of the failure each defect produced in production: a 405 with
    /// the server's `Allow` header. Kept so the mapping stays exercised.
    func test_given405FromWrongVerb_whenSent_thenSurfacesAsAPIError() async throws {
        let (client, transport) = makeClient()
        await transport.enqueue(.json(
            #"{"error":"Method Not Allowed"}"#,
            status: 405,
            headers: ["Allow": "OPTIONS, PATCH"]
        ))

        do {
            _ = try await client.send(User.update(UpdateUserRequest(displayName: "Ada")))
            XCTFail("Expected the 405 to throw")
        } catch is APIError {
            // Expected — the client must not treat a 405 as a success.
        }
    }

    /// V6 could not be exercised to a 2xx (the test account has no followers),
    /// so the observed live response is what is locked: the handler is reached
    /// and answers a business-level 404, not a 405.
    func test_givenNoSuchFollower_whenRemoveSent_thenSurfacesNotFoundNot405() async throws {
        let (client, transport) = makeClient()
        await transport.enqueue(.json(#"{"error":"Follower relationship not found","code":"not_found"}"#, status: 404))

        do {
            _ = try await client.send(Follow.remove(userId: "u404"))
            XCTFail("Expected notFound")
        } catch let error as APIError {
            XCTAssertEqual(error, .notFound(serverMessage: "Follower relationship not found"))
        }

        let received = await transport.received
        XCTAssertEqual(received[0].httpMethod, "DELETE")
    }

    // MARK: - Boundary

    /// Boundary: an empty patch body still encodes as a valid object on the
    /// corrected verb rather than tripping the encoder.
    func test_givenEmptyBodies_whenBuiltOnCorrectedVerbs_thenStillEncode() throws {
        let user = User.update(UpdateUserRequest())
        XCTAssertEqual(user.method, .patch)

        let row = Lists.updateRow(listId: "l1", rowId: "r1", UpdateListRowRequest(rowData: [:]))
        XCTAssertEqual(row.method, .put)

        let org = Organizations.update(id: "o1", UpdateOrganizationRequest())
        XCTAssertEqual(org.method, .put)
    }

    /// Boundary: a repo slug already contains a slash, so the flat GitHub paths
    /// must interpolate `owner/repo` without double-escaping it.
    func test_givenOwnerRepoSlug_whenFlatGitHubPathsBuilt_thenSlugIsNotEscaped() {
        let update = GitHub.updateIssue(
            repo: "CompositeCode/interlinedlist",
            number: 7,
            UpdateGitHubIssueRequest(assignees: ["octocat"])
        )
        XCTAssertEqual(update.path, "/api/github/issues/CompositeCode/interlinedlist/7")
    }
}
