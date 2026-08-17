import Foundation
import CoreGraphics

/// A pure, deterministic force-directed (spring/repulsion) graph layout.
///
/// Given a set of nodes and undirected edges, this computes a 2-D position
/// for every node such that:
///   * every pair of nodes repels the other (a Coulomb-style inverse force),
///   * every edge pulls its two endpoints together (a Hooke-style spring),
///   * the whole arrangement is iterated with a cooling schedule until it
///     settles, then normalized and centered into the requested `CGSize`.
///
/// The algorithm is a Fruchterman–Reingold variant. It is intentionally a
/// value type with no reference to `Date`, `arc4random`, or any other source
/// of nondeterminism: the same `(nodeIDs, edges, size)` input always yields
/// byte-identical output. Initial positions are seeded on a circle by node
/// index (angle `2πi/n`), the iteration count is fixed, and all arithmetic is
/// deterministic. This makes the layout unit-testable independent of SwiftUI
/// — it lives in `InterlinedDomain` and depends only on `CoreGraphics`.
public struct ForceDirectedLayout: Sendable, Equatable {

    /// Tunable parameters. Defaults are chosen to give a readable spread for
    /// the small (order-of-tens-of-nodes) list-connection graphs the app draws.
    public struct Parameters: Sendable, Equatable {
        /// Number of relaxation iterations. Fixed for determinism.
        public var iterations: Int
        /// Multiplier on the ideal edge length `k = idealLengthScale * sqrt(area / n)`.
        /// Larger values spread the graph out more.
        public var idealLengthScale: Double
        /// Fraction of the initial temperature that a single node may move on
        /// the first iteration (as a fraction of the smaller canvas dimension).
        public var initialTemperatureFraction: Double
        /// Inset (in points) kept between the graph's bounding box and every
        /// edge of the canvas after normalization.
        public var margin: Double
        /// Radius, as a fraction of the smaller canvas dimension, of the circle
        /// on which nodes are deterministically seeded.
        public var seedRadiusFraction: Double

        public init(
            iterations: Int = 300,
            idealLengthScale: Double = 0.9,
            initialTemperatureFraction: Double = 0.1,
            margin: Double = 40,
            seedRadiusFraction: Double = 0.35
        ) {
            self.iterations = iterations
            self.idealLengthScale = idealLengthScale
            self.initialTemperatureFraction = initialTemperatureFraction
            self.margin = margin
            self.seedRadiusFraction = seedRadiusFraction
        }
    }

    public var parameters: Parameters

    public init(parameters: Parameters = Parameters()) {
        self.parameters = parameters
    }

    /// An undirected edge between two node ids. Direction is irrelevant to the
    /// spring force, so callers may pass a directed connection either way.
    public struct Edge: Sendable, Equatable, Hashable {
        public let from: String
        public let to: String
        public init(from: String, to: String) {
            self.from = from
            self.to = to
        }
    }

    /// Smallest separation (in points) the simulation will treat two nodes as
    /// having. Guards every division so coincident nodes can never produce a
    /// `NaN`/`inf` displacement.
    private static let minSeparation: Double = 0.01

    /// Computes a deterministic position for every id in `nodeIDs`.
    ///
    /// - Parameters:
    ///   - nodeIDs: The nodes to place. Order is significant only in that it
    ///     seeds the deterministic starting circle; the returned dictionary is
    ///     keyed by id, so callers need not preserve order.
    ///   - edges: Undirected springs. Edges referencing an id not in `nodeIDs`
    ///     are ignored.
    ///   - size: The target canvas. Positions are normalized to fit inside it
    ///     with `parameters.margin` of inset on every side.
    /// - Returns: A map from node id to its `CGPoint` within `size`. Empty when
    ///   `nodeIDs` is empty. A single node is centered.
    public func positions(
        nodeIDs: [String],
        edges: [Edge],
        size: CGSize
    ) -> [String: CGPoint] {
        guard !nodeIDs.isEmpty else { return [:] }

        let width = max(Double(size.width), 1)
        let height = max(Double(size.height), 1)
        let center = SIMD2(width / 2.0, height / 2.0)

        // A single node has nothing to relax against — center it.
        guard nodeIDs.count > 1 else {
            return [nodeIDs[0]: CGPoint(x: center.x, y: center.y)]
        }

        let count = nodeIDs.count
        let indexOf = Dictionary(
            uniqueKeysWithValues: nodeIDs.enumerated().map { ($0.element, $0.offset) }
        )

        // Ideal edge length: the classic FR `k = C * sqrt(area / n)`.
        let area = width * height
        let k = max(parameters.idealLengthScale * (area / Double(count)).squareRoot(),
                    Self.minSeparation)

        // 1) Deterministic seeding on a circle: node i at angle 2πi/n.
        let seedRadius = min(width, height) * parameters.seedRadiusFraction
        var points: [SIMD2<Double>] = (0..<count).map { i in
            let angle = 2.0 * Double.pi * Double(i) / Double(count)
            return SIMD2(
                center.x + seedRadius * cos(angle),
                center.y + seedRadius * sin(angle)
            )
        }

        // Precompute edge index pairs once (skip unknown / self edges).
        let edgePairs: [(Int, Int)] = edges.compactMap { edge in
            guard let a = indexOf[edge.from],
                  let b = indexOf[edge.to],
                  a != b else { return nil }
            return (a, b)
        }

        // 2) Iterate with a linear cooling schedule.
        var temperature = min(width, height) * parameters.initialTemperatureFraction
        let cooling = temperature / Double(max(parameters.iterations, 1))

        var displacement = [SIMD2<Double>](repeating: SIMD2(0, 0), count: count)

        for _ in 0..<parameters.iterations {
            for i in 0..<count { displacement[i] = SIMD2(0, 0) }

            // Repulsion: every unordered pair pushes apart with force k²/d.
            for i in 0..<count {
                for j in (i + 1)..<count {
                    let delta = points[i] - points[j]
                    let distance = max((delta.x * delta.x + delta.y * delta.y).squareRoot(),
                                       Self.minSeparation)
                    let magnitude = (k * k) / distance
                    let unit = delta / distance
                    let force = unit * magnitude
                    displacement[i] += force
                    displacement[j] -= force
                }
            }

            // Attraction: each edge pulls its endpoints together with force d²/k.
            for (a, b) in edgePairs {
                let delta = points[a] - points[b]
                let distance = max((delta.x * delta.x + delta.y * delta.y).squareRoot(),
                                   Self.minSeparation)
                let magnitude = (distance * distance) / k
                let unit = delta / distance
                let force = unit * magnitude
                displacement[a] -= force
                displacement[b] += force
            }

            // Apply, capping each node's step by the current temperature.
            for i in 0..<count {
                let disp = displacement[i]
                let length = max((disp.x * disp.x + disp.y * disp.y).squareRoot(),
                                 Self.minSeparation)
                let capped = min(length, temperature)
                points[i] += (disp / length) * capped
            }

            temperature = max(temperature - cooling, 0)
        }

        // 3) Normalize the settled cloud into the canvas with a margin inset.
        return normalized(points, ids: nodeIDs, width: width, height: height)
    }

    /// Scales and translates `points` so their bounding box fits inside the
    /// canvas with `parameters.margin` of inset, preserving aspect ratio.
    /// Coincident clouds (all points equal) collapse to the canvas center.
    private func normalized(
        _ points: [SIMD2<Double>],
        ids: [String],
        width: Double,
        height: Double
    ) -> [String: CGPoint] {
        var minX = Double.greatestFiniteMagnitude
        var minY = Double.greatestFiniteMagnitude
        var maxX = -Double.greatestFiniteMagnitude
        var maxY = -Double.greatestFiniteMagnitude
        for p in points {
            minX = Swift.min(minX, p.x)
            minY = Swift.min(minY, p.y)
            maxX = Swift.max(maxX, p.x)
            maxY = Swift.max(maxY, p.y)
        }

        let margin = Swift.min(parameters.margin, Swift.min(width, height) / 2.0 - 1)
        let usableWidth = Swift.max(width - 2 * margin, 1)
        let usableHeight = Swift.max(height - 2 * margin, 1)

        let spanX = maxX - minX
        let spanY = maxY - minY

        // Uniform scale to preserve the graph's shape; guard zero spans.
        let scaleX = spanX > Self.minSeparation ? usableWidth / spanX : Double.greatestFiniteMagnitude
        let scaleY = spanY > Self.minSeparation ? usableHeight / spanY : Double.greatestFiniteMagnitude
        let scale = Swift.min(scaleX, scaleY)
        // If both spans collapsed, every point sits at the canvas center.
        let effectiveScale = scale.isFinite ? scale : 0

        // Center the scaled bounding box inside the usable area.
        let scaledSpanX = spanX * effectiveScale
        let scaledSpanY = spanY * effectiveScale
        let offsetX = margin + (usableWidth - scaledSpanX) / 2.0
        let offsetY = margin + (usableHeight - scaledSpanY) / 2.0

        var result: [String: CGPoint] = [:]
        result.reserveCapacity(ids.count)
        for (index, id) in ids.enumerated() {
            let p = points[index]
            let x = offsetX + (p.x - minX) * effectiveScale
            let y = offsetY + (p.y - minY) * effectiveScale
            // Final clamp: normalization keeps us in-bounds, but clamp defends
            // against any floating-point drift so callers get a hard guarantee.
            let clampedX = Swift.min(Swift.max(x, 0), width)
            let clampedY = Swift.min(Swift.max(y, 0), height)
            result[id] = CGPoint(x: clampedX, y: clampedY)
        }
        return result
    }
}
