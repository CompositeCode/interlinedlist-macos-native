// ListConnectionsViewModel
//
// Drives `ListConnectionsView` — the M3 interactive connections
// graph (PLAN.md §6 M3, "List connections"). Per the user's plan
// answer: interactive (drag nodes, drag-to-add-edge, tap-to-remove),
// SwiftUI-only (no `NSViewRepresentable`).
//
// **Implementation choice — deterministic radial layout for v1.**
// We shipped the deterministic path rather than the force-directed
// physics simulation. The brief allowed either, and a deterministic
// layout is testable, stable, and degrades gracefully when the
// connection set is large. The view drives drag with state updates;
// the layout function recomputes positions when nodes change so
// freshly-added nodes find a home without a relayout dance.
//
// TODO(M3.x): swap the radial layout for a force-directed pass
// (repulsion + spring on each `TimelineView(.animation)` frame)
// once we have enough real connection data to tune the parameters.

import Foundation
import Observation
import CoreGraphics
import InterlinedDomain

@MainActor
@Observable
final class ListConnectionsViewModel {

    /// A renderable graph node. Identity is the list id.
    struct Node: Identifiable, Equatable {
        let id: String
        let title: String
        var position: CGPoint
        var isFocused: Bool
    }

    private let lists: ListsServicing
    private let eventBus: ListsEventBus
    let focusListId: String

    /// All connections involving the focus list. Edges are rendered
    /// against the `Node` positions below.
    private(set) var edges: [ListConnection] = []
    /// All known list titles by id. Populated from a parent's loaded
    /// list set so we don't refetch every neighbour.
    private(set) var nodes: [Node] = []

    private(set) var isLoading: Bool = false
    private(set) var error: Error?

    /// Default render area; callers should pass the actual canvas
    /// size to `layout(in:)` but the initial layout uses this.
    static let defaultCanvasSize = CGSize(width: 600, height: 400)

    init(
        lists: ListsServicing,
        eventBus: ListsEventBus,
        focusListId: String,
        knownLists: [OwnedList] = []
    ) {
        self.lists = lists
        self.eventBus = eventBus
        self.focusListId = focusListId
        seedKnownLists(knownLists)
    }

    func load() async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            edges = try await lists.connections(of: focusListId)
            rebuildNodes()
            layout(in: Self.defaultCanvasSize)
            error = nil
        } catch {
            self.error = error
        }
    }

    /// Adds a connection between two existing list ids. Optimistic
    /// snapshot + service call.
    func addConnection(from: String, to: String, label: String?) async {
        guard from != to else { return }
        let snapshot = edges
        do {
            let created = try await lists.addConnection(
                fromListId: from,
                toListId: to,
                label: label
            )
            edges.append(created)
            eventBus.post(.connectionAdded(created))
            error = nil
        } catch {
            edges = snapshot
            self.error = error
        }
    }

    /// Removes a connection by id.
    func removeConnection(id: String) async {
        let snapshot = edges
        edges.removeAll { $0.id == id }
        do {
            try await lists.removeConnection(connectionId: id)
            eventBus.post(.connectionRemoved(id: id))
            error = nil
        } catch {
            edges = snapshot
            self.error = error
        }
    }

    /// Updates a node's position (called from the view's drag
    /// gesture). The drag is non-physics — the new position sticks.
    func setNodePosition(id: String, to position: CGPoint) {
        guard let index = nodes.firstIndex(where: { $0.id == id }) else { return }
        nodes[index].position = position
    }

    /// Recomputes a deterministic radial layout in the given canvas
    /// size. Focus list at center, neighbours equally spaced on the
    /// circumference. Deterministic so tests can assert positions.
    func layout(in size: CGSize) {
        guard !nodes.isEmpty else { return }
        let center = CGPoint(x: size.width / 2.0, y: size.height / 2.0)
        let radius = min(size.width, size.height) * 0.35
        let focus = nodes.first { $0.isFocused }
        let neighbours = nodes.filter { !$0.isFocused }
        let total = neighbours.count
        for (index, node) in nodes.enumerated() {
            if node.isFocused {
                nodes[index].position = center
                continue
            }
            // Index among neighbours determines angle.
            guard let neighbourIndex = neighbours.firstIndex(where: { $0.id == node.id })
            else { continue }
            let angle = 2.0 * Double.pi * Double(neighbourIndex) / Double(max(total, 1))
            let x = center.x + CGFloat(cos(angle)) * radius
            let y = center.y + CGFloat(sin(angle)) * radius
            nodes[index].position = CGPoint(x: x, y: y)
        }
        _ = focus // silence unused-warning when no focus
    }

    /// Applies a `ListsEvent`. Connection events arrive from any
    /// other open instance of this view.
    func apply(event: ListsEvent) {
        switch event {
        case .connectionAdded(let connection):
            // Only ingest if it's involving the focused list.
            guard connection.fromListId == focusListId ||
                    connection.toListId == focusListId else { return }
            if !edges.contains(where: { $0.id == connection.id }) {
                edges.append(connection)
                rebuildNodes()
            }
        case .connectionRemoved(let id):
            if edges.contains(where: { $0.id == id }) {
                edges.removeAll { $0.id == id }
                rebuildNodes()
            }
        case .listDeleted(let id):
            // Drop edges and nodes that reference the deleted list.
            edges.removeAll { $0.fromListId == id || $0.toListId == id }
            nodes.removeAll { $0.id == id }
        default:
            break
        }
    }

    /// Seeds the known-lists name index so freshly-loaded edges can
    /// render a label without a per-list refetch.
    func seedKnownLists(_ lists: [OwnedList]) {
        // Preserve any existing nodes' positions; only update titles.
        var titles: [String: String] = [:]
        for list in lists {
            titles[list.id] = list.title
        }
        for index in nodes.indices {
            if let title = titles[nodes[index].id] {
                nodes[index] = Node(
                    id: nodes[index].id,
                    title: title,
                    position: nodes[index].position,
                    isFocused: nodes[index].isFocused
                )
            }
        }
        // Stash the index for `rebuildNodes` lookups.
        knownTitles = titles
    }

    private var knownTitles: [String: String] = [:]

    /// Rebuilds the `nodes` array from `edges`, preserving any
    /// existing positions so a drag-and-drop user doesn't see
    /// their node jump back to a default spot.
    private func rebuildNodes() {
        let existing = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })
        var nextNodes: [Node] = []
        // Focus list always present.
        let focusTitle = knownTitles[focusListId] ?? "This list"
        if let existingFocus = existing[focusListId] {
            nextNodes.append(Node(
                id: focusListId,
                title: focusTitle,
                position: existingFocus.position,
                isFocused: true
            ))
        } else {
            nextNodes.append(Node(
                id: focusListId,
                title: focusTitle,
                position: .zero,
                isFocused: true
            ))
        }
        // Every other id involved in an edge.
        var seen: Set<String> = [focusListId]
        for edge in edges {
            for neighbour in [edge.fromListId, edge.toListId] where !seen.contains(neighbour) {
                let title = knownTitles[neighbour] ?? neighbour
                if let existingNode = existing[neighbour] {
                    nextNodes.append(Node(
                        id: neighbour,
                        title: title,
                        position: existingNode.position,
                        isFocused: false
                    ))
                } else {
                    nextNodes.append(Node(
                        id: neighbour,
                        title: title,
                        position: .zero,
                        isFocused: false
                    ))
                }
                seen.insert(neighbour)
            }
        }
        nodes = nextNodes
    }
}
