// ListConnectionsViewModelTests
//
// BDD-named tests for the M3 connections-graph view model. Covers
// load happy / failure / empty, optimistic add / remove, deterministic
// radial layout, drag re-position, and event-bus consumption.

import XCTest
import CoreGraphics
import InterlinedDomain
@testable import InterlinedList

@MainActor
final class ListConnectionsViewModelTests: XCTestCase {

    // MARK: - load

    func test_givenLoadedEdges_whenLoading_thenBuildsNodes() async {
        let stub = StubListsService()
        let focusList = ListsFixtures.ownedList(id: "L1", title: "Focus")
        let neighbour = ListsFixtures.ownedList(id: "L2", title: "Other")
        let edge = ListsFixtures.connection(id: "E1", from: "L1", to: "L2")
        await stub.enqueueConnections(success: [edge])
        let viewModel = ListConnectionsViewModel(
            lists: stub,
            eventBus: ListsEventBus(),
            focusListId: "L1",
            knownLists: [focusList, neighbour]
        )

        await viewModel.load()

        XCTAssertEqual(viewModel.edges.count, 1)
        XCTAssertEqual(viewModel.nodes.count, 2)
        XCTAssertTrue(viewModel.nodes.contains { $0.id == "L1" && $0.isFocused })
        XCTAssertTrue(viewModel.nodes.contains { $0.id == "L2" && !$0.isFocused })
    }

    func test_givenEmptyConnections_whenLoading_thenStillKnowsFocusNode() async {
        let stub = StubListsService()
        let focusList = ListsFixtures.ownedList(id: "L1", title: "Focus")
        await stub.enqueueConnections(success: [])
        let viewModel = ListConnectionsViewModel(
            lists: stub,
            eventBus: ListsEventBus(),
            focusListId: "L1",
            knownLists: [focusList]
        )

        await viewModel.load()

        XCTAssertTrue(viewModel.edges.isEmpty)
        XCTAssertEqual(viewModel.nodes.map(\.id), ["L1"])
    }

    func test_givenAPIFailure_whenLoading_thenSurfacesError() async {
        let stub = StubListsService()
        await stub.enqueueConnections(failure: TestError.upstream("denied"))
        let viewModel = ListConnectionsViewModel(
            lists: stub,
            eventBus: ListsEventBus(),
            focusListId: "L1"
        )

        await viewModel.load()

        XCTAssertEqual(viewModel.error as? TestError, .upstream("denied"))
    }

    // MARK: - addConnection / removeConnection

    func test_givenTwoNodes_whenAddConnection_thenAppendsEdge() async {
        let stub = StubListsService()
        await stub.enqueueConnections(success: [])
        let viewModel = ListConnectionsViewModel(
            lists: stub,
            eventBus: ListsEventBus(),
            focusListId: "L1"
        )
        await viewModel.load()
        let created = ListsFixtures.connection(id: "E1", from: "L1", to: "L2")
        await stub.enqueueAddConnection(success: created)

        await viewModel.addConnection(from: "L1", to: "L2", label: "rel")

        XCTAssertEqual(viewModel.edges.map(\.id), ["E1"])
    }

    func test_givenAddConnectionFailure_whenAdding_thenRestoresSnapshot() async {
        let stub = StubListsService()
        let existing = ListsFixtures.connection(id: "E1", from: "L1", to: "L2")
        await stub.enqueueConnections(success: [existing])
        let viewModel = ListConnectionsViewModel(
            lists: stub,
            eventBus: ListsEventBus(),
            focusListId: "L1"
        )
        await viewModel.load()
        await stub.enqueueAddConnection(failure: TestError.upstream("denied"))

        await viewModel.addConnection(from: "L1", to: "L3", label: nil)

        XCTAssertEqual(viewModel.edges.map(\.id), ["E1"])
        XCTAssertEqual(viewModel.error as? TestError, .upstream("denied"))
    }

    func test_givenEdge_whenRemove_thenDrops() async {
        let stub = StubListsService()
        let existing = ListsFixtures.connection(id: "E1", from: "L1", to: "L2")
        await stub.enqueueConnections(success: [existing])
        let viewModel = ListConnectionsViewModel(
            lists: stub,
            eventBus: ListsEventBus(),
            focusListId: "L1"
        )
        await viewModel.load()
        await stub.enqueueRemoveConnectionSuccess()

        await viewModel.removeConnection(id: "E1")

        XCTAssertTrue(viewModel.edges.isEmpty)
    }

    func test_givenSameSourceAndTarget_whenAdd_thenIsNoop() async {
        let stub = StubListsService()
        await stub.enqueueConnections(success: [])
        let viewModel = ListConnectionsViewModel(
            lists: stub,
            eventBus: ListsEventBus(),
            focusListId: "L1"
        )
        await viewModel.load()

        await viewModel.addConnection(from: "L1", to: "L1", label: nil)

        let recorded = await stub.recorded
        XCTAssertFalse(recorded.contains { kind in
            if case .addConnection = kind.kind { return true } else { return false }
        })
    }

    // MARK: - layout determinism

    func test_givenSeedNodes_whenLayout_thenFocusAtCenter() async {
        let stub = StubListsService()
        let focus = ListsFixtures.ownedList(id: "L1")
        let other = ListsFixtures.ownedList(id: "L2")
        let edge = ListsFixtures.connection(id: "E1", from: "L1", to: "L2")
        await stub.enqueueConnections(success: [edge])
        let viewModel = ListConnectionsViewModel(
            lists: stub,
            eventBus: ListsEventBus(),
            focusListId: "L1",
            knownLists: [focus, other]
        )
        await viewModel.load()

        let size = CGSize(width: 600, height: 400)
        viewModel.layout(in: size)

        let focusNode = viewModel.nodes.first { $0.isFocused }
        XCTAssertNotNil(focusNode)
        XCTAssertEqual(Double(focusNode?.position.x ?? 0), 300, accuracy: 0.001)
        XCTAssertEqual(Double(focusNode?.position.y ?? 0), 200, accuracy: 0.001)
    }

    // MARK: - drag re-position

    func test_givenLoadedGraph_whenSetNodePosition_thenUpdatesNode() async {
        let stub = StubListsService()
        let focus = ListsFixtures.ownedList(id: "L1")
        let other = ListsFixtures.ownedList(id: "L2")
        let edge = ListsFixtures.connection(id: "E1", from: "L1", to: "L2")
        await stub.enqueueConnections(success: [edge])
        let viewModel = ListConnectionsViewModel(
            lists: stub,
            eventBus: ListsEventBus(),
            focusListId: "L1",
            knownLists: [focus, other]
        )
        await viewModel.load()

        viewModel.setNodePosition(id: "L2", to: CGPoint(x: 100, y: 100))

        let target = viewModel.nodes.first { $0.id == "L2" }
        XCTAssertEqual(target?.position, CGPoint(x: 100, y: 100))
    }

    // MARK: - apply(event:)

    func test_givenConnectionAddedEventForFocus_whenApplied_thenAppendsEdge() async {
        let stub = StubListsService()
        await stub.enqueueConnections(success: [])
        let viewModel = ListConnectionsViewModel(
            lists: stub,
            eventBus: ListsEventBus(),
            focusListId: "L1"
        )
        await viewModel.load()
        let edge = ListsFixtures.connection(id: "E1", from: "L1", to: "L2")

        viewModel.apply(event: .connectionAdded(edge))

        XCTAssertEqual(viewModel.edges.map(\.id), ["E1"])
    }

    func test_givenConnectionAddedEventOutsideFocus_whenApplied_thenIsNoop() async {
        let stub = StubListsService()
        await stub.enqueueConnections(success: [])
        let viewModel = ListConnectionsViewModel(
            lists: stub,
            eventBus: ListsEventBus(),
            focusListId: "L1"
        )
        await viewModel.load()
        let edge = ListsFixtures.connection(id: "E1", from: "X", to: "Y")

        viewModel.apply(event: .connectionAdded(edge))

        XCTAssertTrue(viewModel.edges.isEmpty)
    }
}
