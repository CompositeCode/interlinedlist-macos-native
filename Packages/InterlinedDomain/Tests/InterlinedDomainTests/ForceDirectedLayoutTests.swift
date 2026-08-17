// ForceDirectedLayoutTests
//
// BDD-named tests for the pure, deterministic force-directed graph
// layout. Covers reproducibility, finiteness (no NaN/inf), in-bounds
// guarantees, the connected-clusters-closer property, and the empty /
// single-node degenerate cases.

import XCTest
import CoreGraphics
@testable import InterlinedDomain

final class ForceDirectedLayoutTests: XCTestCase {

    private let size = CGSize(width: 600, height: 400)

    private func distance(_ a: CGPoint, _ b: CGPoint) -> Double {
        let dx = Double(a.x - b.x)
        let dy = Double(a.y - b.y)
        return (dx * dx + dy * dy).squareRoot()
    }

    // MARK: - determinism

    func test_givenSameGraph_whenComputedTwice_thenPositionsAreIdentical() {
        let layout = ForceDirectedLayout()
        let ids = ["A", "B", "C", "D"]
        let edges = [
            ForceDirectedLayout.Edge(from: "A", to: "B"),
            ForceDirectedLayout.Edge(from: "B", to: "C"),
            ForceDirectedLayout.Edge(from: "C", to: "D")
        ]

        let first = layout.positions(nodeIDs: ids, edges: edges, size: size)
        let second = layout.positions(nodeIDs: ids, edges: edges, size: size)

        XCTAssertEqual(first, second)
    }

    func test_givenSameGraph_whenComputedByDistinctInstances_thenPositionsAreIdentical() {
        let ids = ["A", "B", "C"]
        let edges = [ForceDirectedLayout.Edge(from: "A", to: "B")]

        let first = ForceDirectedLayout().positions(nodeIDs: ids, edges: edges, size: size)
        let second = ForceDirectedLayout().positions(nodeIDs: ids, edges: edges, size: size)

        XCTAssertEqual(first, second)
    }

    // MARK: - finiteness

    func test_givenConnectedGraph_whenLaidOut_thenNoCoordinateIsNaNOrInfinite() {
        let layout = ForceDirectedLayout()
        let ids = (0..<8).map { "N\($0)" }
        let edges = zip(ids, ids.dropFirst()).map {
            ForceDirectedLayout.Edge(from: $0, to: $1)
        }

        let positions = layout.positions(nodeIDs: ids, edges: edges, size: size)

        for point in positions.values {
            XCTAssertTrue(point.x.isFinite, "x should be finite")
            XCTAssertTrue(point.y.isFinite, "y should be finite")
        }
    }

    func test_givenCoincidentSeedRisk_whenSingleEdge_thenNoNaNFromDivision() {
        // A two-node graph joined by an edge exercises the smallest,
        // most collision-prone configuration; assert it stays finite.
        let layout = ForceDirectedLayout()
        let positions = layout.positions(
            nodeIDs: ["A", "B"],
            edges: [ForceDirectedLayout.Edge(from: "A", to: "B")],
            size: size
        )

        for point in positions.values {
            XCTAssertTrue(point.x.isFinite)
            XCTAssertTrue(point.y.isFinite)
        }
    }

    // MARK: - bounds

    func test_givenGraph_whenLaidOut_thenEveryPositionIsWithinCanvas() {
        let layout = ForceDirectedLayout()
        let ids = (0..<10).map { "N\($0)" }
        // A hub-and-spoke graph.
        let edges = ids.dropFirst().map {
            ForceDirectedLayout.Edge(from: ids[0], to: $0)
        }

        let positions = layout.positions(nodeIDs: ids, edges: edges, size: size)

        for point in positions.values {
            XCTAssertGreaterThanOrEqual(point.x, 0)
            XCTAssertLessThanOrEqual(point.x, size.width)
            XCTAssertGreaterThanOrEqual(point.y, 0)
            XCTAssertLessThanOrEqual(point.y, size.height)
        }
    }

    func test_givenDisconnectedNodes_whenLaidOut_thenStillWithinCanvas() {
        let layout = ForceDirectedLayout()
        let ids = (0..<6).map { "N\($0)" }

        let positions = layout.positions(nodeIDs: ids, edges: [], size: size)

        XCTAssertEqual(positions.count, ids.count)
        for point in positions.values {
            XCTAssertGreaterThanOrEqual(point.x, 0)
            XCTAssertLessThanOrEqual(point.x, size.width)
            XCTAssertGreaterThanOrEqual(point.y, 0)
            XCTAssertLessThanOrEqual(point.y, size.height)
        }
    }

    // MARK: - clustering property

    func test_givenConnectedAndDisconnectedPairs_whenLaidOut_thenConnectedAreCloser() {
        // A and B are joined; C and D float free (each only connected to
        // its own partner far away). The connected pair should settle
        // closer together than an unconnected pair of the same graph.
        let layout = ForceDirectedLayout()
        let ids = ["A", "B", "C", "D", "E", "F"]
        let edges = [
            ForceDirectedLayout.Edge(from: "A", to: "B"),
            ForceDirectedLayout.Edge(from: "C", to: "D"),
            ForceDirectedLayout.Edge(from: "E", to: "F")
        ]

        let positions = layout.positions(nodeIDs: ids, edges: edges, size: size)

        let connected = distance(positions["A"]!, positions["B"]!)
        // A and C are in different components — with no spring between
        // them, repulsion keeps them apart.
        let disconnected = distance(positions["A"]!, positions["C"]!)

        XCTAssertLessThan(connected, disconnected)
    }

    func test_givenHubGraph_whenLaidOut_thenSpokesAreNearHub() {
        // Every spoke connects only to the hub; on average a spoke should
        // be closer to the hub than to the farthest other spoke.
        let layout = ForceDirectedLayout()
        let ids = ["HUB", "S1", "S2", "S3", "S4"]
        let edges = ids.dropFirst().map {
            ForceDirectedLayout.Edge(from: "HUB", to: $0)
        }

        let positions = layout.positions(nodeIDs: ids, edges: edges, size: size)
        let hub = positions["HUB"]!
        let spokeToHub = distance(positions["S1"]!, hub)

        // The two farthest spokes are pushed apart by repulsion, so a
        // spoke's distance to the hub is less than the graph's diameter.
        var maxSpokeToSpoke = 0.0
        let spokes = ["S1", "S2", "S3", "S4"]
        for i in 0..<spokes.count {
            for j in (i + 1)..<spokes.count {
                maxSpokeToSpoke = Swift.max(
                    maxSpokeToSpoke,
                    distance(positions[spokes[i]]!, positions[spokes[j]]!)
                )
            }
        }

        XCTAssertLessThan(spokeToHub, maxSpokeToSpoke)
    }

    // MARK: - degenerate graphs

    func test_givenEmptyGraph_whenLaidOut_thenReturnsEmptyWithoutCrashing() {
        let layout = ForceDirectedLayout()

        let positions = layout.positions(nodeIDs: [], edges: [], size: size)

        XCTAssertTrue(positions.isEmpty)
    }

    func test_givenSingleNode_whenLaidOut_thenCenteredWithoutCrashing() {
        let layout = ForceDirectedLayout()

        let positions = layout.positions(nodeIDs: ["ONLY"], edges: [], size: size)

        XCTAssertEqual(positions.count, 1)
        let point = positions["ONLY"]
        XCTAssertNotNil(point)
        XCTAssertEqual(Double(point!.x), Double(size.width / 2), accuracy: 0.0001)
        XCTAssertEqual(Double(point!.y), Double(size.height / 2), accuracy: 0.0001)
    }

    func test_givenEdgeReferencingUnknownNode_whenLaidOut_thenIgnoresItWithoutCrashing() {
        let layout = ForceDirectedLayout()
        let ids = ["A", "B"]
        let edges = [
            ForceDirectedLayout.Edge(from: "A", to: "B"),
            ForceDirectedLayout.Edge(from: "A", to: "GHOST")
        ]

        let positions = layout.positions(nodeIDs: ids, edges: edges, size: size)

        XCTAssertEqual(positions.count, 2)
        XCTAssertNil(positions["GHOST"])
    }

    func test_givenZeroSizedCanvas_whenLaidOut_thenPositionsStayFinite() {
        let layout = ForceDirectedLayout()
        let ids = ["A", "B", "C"]
        let edges = [ForceDirectedLayout.Edge(from: "A", to: "B")]

        let positions = layout.positions(nodeIDs: ids, edges: edges, size: .zero)

        XCTAssertEqual(positions.count, 3)
        for point in positions.values {
            XCTAssertTrue(point.x.isFinite)
            XCTAssertTrue(point.y.isFinite)
        }
    }
}
