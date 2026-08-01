import XCTest
import InterlinedKit
@testable import InterlinedDomain

/// BDD-named coverage for `ListFoldersService` (the-gaps.md G6). Quartet per
/// public method: happy + invalid + failure + empty/boundary. Includes the
/// subscriber gate and the tree builder.
final class ListFoldersServiceTests: XCTestCase {

    private func subscriberService(_ api: StubAPIClient) -> ListFoldersService {
        ListFoldersService(api: api, entitlements: EntitlementsService(customerStatus: .subscriber))
    }

    // MARK: - folders

    func test_givenFolders_whenLoading_thenMapsRowsAndHitsPath() async throws {
        let api = StubAPIClient()
        await api.enqueue(json: #"{"folders":[{"id":"f1","name":"Root","parentId":null}]}"#)
        let service = subscriberService(api)

        let folders = try await service.folders()

        XCTAssertEqual(folders.map(\.id), ["f1"])
        let recorded = await api.recorded
        XCTAssertEqual(recorded.first?.path, "/api/folders")
        XCTAssertEqual(recorded.first?.method, "GET")
    }

    func test_givenEmpty_whenLoadingFolders_thenReturnsEmpty() async throws {
        let api = StubAPIClient()
        await api.enqueue(json: #"{"folders":[]}"#)
        let service = subscriberService(api)

        let folders = try await service.folders()

        XCTAssertTrue(folders.isEmpty)
    }

    func test_givenServerFailure_whenLoadingFolders_thenThrows() async throws {
        let api = StubAPIClient()
        await api.enqueue(failure: .httpStatus(code: 500, serverMessage: "boom"))
        let service = subscriberService(api)

        do {
            _ = try await service.folders()
            XCTFail("Expected APIError")
        } catch let error as APIError {
            XCTAssertEqual(error, .httpStatus(code: 500, serverMessage: "boom"))
        }
    }

    // MARK: - create (subscriber-gated)

    func test_givenSubscriber_whenCreating_thenPostsAndMapsFolder() async throws {
        let api = StubAPIClient()
        await api.enqueue(json: #"{"id":"f9","name":"Bikes","parentId":null}"#)
        let service = subscriberService(api)

        let folder = try await service.create(name: "  Bikes  ")

        XCTAssertEqual(folder.id, "f9")
        let recorded = await api.recorded
        XCTAssertEqual(recorded.first?.method, "POST")
        XCTAssertEqual(recorded.first?.path, "/api/folders")
    }

    func test_givenFreeUser_whenCreating_thenThrowsSubscriberRequiredWithoutRequest() async throws {
        let api = StubAPIClient()
        let service = ListFoldersService(api: api, entitlements: EntitlementsService(customerStatus: .free))

        do {
            _ = try await service.create(name: "Bikes")
            XCTFail("Expected subscriberRequired")
        } catch let error as ListFoldersError {
            XCTAssertEqual(error, .subscriberRequired)
        }
        let recorded = await api.recorded
        XCTAssertTrue(recorded.isEmpty, "The subscriber gate must short-circuit before any HTTP call")
    }

    func test_givenBlankName_whenCreating_thenThrowsInvalidName() async throws {
        let api = StubAPIClient()
        let service = subscriberService(api)

        do {
            _ = try await service.create(name: "   ")
            XCTFail("Expected invalidName")
        } catch let error as ListFoldersError {
            XCTAssertEqual(error, .invalidName)
        }
    }

    // MARK: - rename / move / delete

    func test_givenName_whenRenaming_thenPutsToFolderPath() async throws {
        let api = StubAPIClient()
        await api.enqueue(json: #"{"id":"f1","name":"Renamed","parentId":null}"#)
        let service = subscriberService(api)

        let folder = try await service.rename(id: "f1", name: "Renamed")

        XCTAssertEqual(folder.name, "Renamed")
        let recorded = await api.recorded
        XCTAssertEqual(recorded.first?.method, "PUT")
        XCTAssertEqual(recorded.first?.path, "/api/folders/f1")
    }

    func test_givenParent_whenMoving_thenPutsToFolderPath() async throws {
        let api = StubAPIClient()
        await api.enqueue(json: #"{"id":"f2","name":"Child","parentId":"f1"}"#)
        let service = subscriberService(api)

        let folder = try await service.move(id: "f2", toParent: "f1")

        XCTAssertEqual(folder.parentId, "f1")
    }

    func test_givenId_whenDeleting_thenDeletesFolderPath() async throws {
        let api = StubAPIClient()
        await api.enqueue(json: #"{}"#)
        let service = subscriberService(api)

        try await service.delete(id: "f1")

        let recorded = await api.recorded
        XCTAssertEqual(recorded.first?.method, "DELETE")
        XCTAssertEqual(recorded.first?.path, "/api/folders/f1")
    }

    // MARK: - tree builder

    func test_givenFlatFolders_whenBuildingTree_thenNestsByParentId() {
        let folders = [
            ListFolder(id: "r1", name: "Root 1", parentId: nil),
            ListFolder(id: "c1", name: "Child 1", parentId: "r1"),
            ListFolder(id: "c2", name: "Child 2", parentId: "r1"),
            ListFolder(id: "g1", name: "Grandchild", parentId: "c1"),
            ListFolder(id: "r2", name: "Root 2", parentId: nil)
        ]

        let tree = ListFolder.tree(from: folders)

        XCTAssertEqual(tree.map(\.id), ["r1", "r2"])
        XCTAssertEqual(tree.first?.children.map(\.id), ["c1", "c2"])
        XCTAssertEqual(tree.first?.children.first?.children.map(\.id), ["g1"])
    }

    func test_givenDanglingParent_whenBuildingTree_thenOrphanBecomesRoot() {
        let folders = [
            ListFolder(id: "a", name: "A", parentId: "missing"),
            ListFolder(id: "b", name: "B", parentId: nil)
        ]

        let tree = ListFolder.tree(from: folders)

        XCTAssertEqual(Set(tree.map(\.id)), ["a", "b"], "A folder with a dangling parent must not be lost")
    }

    func test_givenSelfParentCycle_whenBuildingTree_thenDoesNotRecurseInfinitely() {
        let folders = [ListFolder(id: "a", name: "A", parentId: "a")]

        let tree = ListFolder.tree(from: folders)

        XCTAssertEqual(tree.map(\.id), ["a"])
        XCTAssertTrue(tree.first?.children.isEmpty ?? false)
    }
}
