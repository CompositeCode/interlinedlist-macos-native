// ListConnectionsViewModel
//
// Drives `ListConnectionsView` — the M3 interactive connections
// graph (PLAN.md §6 M3, "List connections"). Per the user's plan
// answer: interactive (drag nodes, drag-to-add-edge, tap-to-remove),
// SwiftUI-only (no `NSViewRepresentable`).
//
// **Implementation choice — deterministic force-directed layout.**
// `layout(in:)` delegates to `ForceDirectedLayout` (in
// `InterlinedDomain`): a pure Fruchterman–Reingold pass with
// edge-springs pulling connected lists together and pairwise
// repulsion pushing everything apart, iterated with a fixed cooling
// schedule and then normalized/centered into the canvas. The layout
// is a deterministic function of (node ids, edges, size) — nodes are
// seeded on a circle by index, the iteration count is fixed, and no
// `Date`/`arc4random` is used — so the same graph always lays out
// identically and the physics is unit-testable without SwiftUI. The
// view drives drag with state updates; a dragged node's position is
// preserved across relayouts so the user doesn't see it jump home.

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

    /// The deterministic force-directed layout engine. A pure value
    /// type living in `InterlinedDomain`; injected so tests can tune
    /// iteration counts if needed, but the default is production.
    private let layoutEngine: ForceDirectedLayout

    /// Node ids the user has explicitly dragged. Their positions are
    /// pinned across relayouts so a drag doesn't get overwritten by
    /// the next physics pass.
    private var pinnedNodeIds: Set<String> = []

    init(
        lists: ListsServicing,
        eventBus: ListsEventBus,
        focusListId: String,
        knownLists: [OwnedList] = [],
        layoutEngine: ForceDirectedLayout = ForceDirectedLayout()
    ) {
        self.lists = lists
        self.eventBus = eventBus
        self.focusListId = focusListId
        self.layoutEngine = layoutEngine
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
    /// gesture). The drag is non-physics — the new position sticks and
    /// the node is pinned so subsequent relayouts don't move it.
    func setNodePosition(id: String, to position: CGPoint) {
        guard let index = nodes.firstIndex(where: { $0.id == id }) else { return }
        nodes[index].position = position
        pinnedNodeIds.insert(id)
    }

    /// Recomputes a deterministic force-directed layout in the given
    /// canvas size by delegating to `ForceDirectedLayout`. Connected
    /// lists cluster (edge springs), all nodes repel each other, and
    /// the settled cloud is normalized/centered into the canvas.
    ///
    /// Deterministic: same nodes + edges + size ⇒ identical positions.
    /// Nodes the user has dragged are pinned and keep their position.
    func layout(in size: CGSize) {
        guard !nodes.isEmpty else { return }
        let ids = nodes.map(\.id)
        let layoutEdges = edges.map {
            ForceDirectedLayout.Edge(from: $0.fromListId, to: $0.toListId)
        }
        let positions = layoutEngine.positions(
            nodeIDs: ids,
            edges: layoutEdges,
            size: size
        )
        for index in nodes.indices {
            let id = nodes[index].id
            // Honour user drags; only reflow un-pinned nodes.
            guard !pinnedNodeIds.contains(id) else { continue }
            if let point = positions[id] {
                nodes[index].position = point
            }
        }
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
