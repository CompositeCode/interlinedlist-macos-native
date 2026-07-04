// ListConnectionsView
//
// The M3 list-connections graph sheet (PLAN.md §6 M3). SwiftUI-only:
// a `Canvas` draws the edges and node circles, and an overlay of
// invisible-tappable views hosts the gestures (drag to move a
// node, drag from one node onto another to add an edge, tap an
// edge to remove). No `NSViewRepresentable`.
//
// v1 ships the deterministic radial layout (see
// `ListConnectionsViewModel`); force-directed physics is a planned
// upgrade. The view doesn't run a simulation loop.

import SwiftUI
import InterlinedDomain

struct ListConnectionsView: View {

    let listId: String
    let knownLists: [OwnedList]
    let environment: AppEnvironment

    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: ListConnectionsViewModel?
    @State private var canvasSize: CGSize = .zero
    @State private var dragSourceID: String?
    @State private var dragLocation: CGPoint?
    @State private var pendingNewEdge: PendingEdge?
    @State private var edgeIDPendingRemove: String?
    @State private var addEdgeLabel: String = ""

    private static let nodeRadius: CGFloat = 28

    var body: some View {
        Group {
            if let viewModel {
                content(viewModel: viewModel)
            } else {
                ProgressView()
                    .padding()
            }
        }
        .frame(minWidth: 720, minHeight: 540)
        .task {
            if viewModel == nil {
                let model = ListConnectionsViewModel(
                    lists: environment.lists,
                    eventBus: environment.listsEventBus,
                    focusListId: listId,
                    knownLists: knownLists
                )
                viewModel = model
                await model.load()
                await subscribe(viewModel: model)
            }
        }
    }

    @ViewBuilder
    private func content(viewModel: ListConnectionsViewModel) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            graph(viewModel: viewModel)
            if let error = viewModel.error {
                Label(error.localizedDescription, systemImage: "exclamationmark.triangle")
                    .padding(8)
            }
            Divider()
            footer
        }
        .sheet(item: $pendingNewEdge) { pending in
            addEdgeConfirmation(viewModel: viewModel, pending: pending)
        }
        .confirmationDialog(
            "Remove this connection?",
            isPresented: Binding(
                get: { edgeIDPendingRemove != nil },
                set: { if !$0 { edgeIDPendingRemove = nil } }
            ),
            presenting: edgeIDPendingRemove
        ) { id in
            Button("Remove", role: .destructive) {
                Task {
                    await viewModel.removeConnection(id: id)
                    edgeIDPendingRemove = nil
                }
            }
            Button("Cancel", role: .cancel) {
                edgeIDPendingRemove = nil
            }
        } message: { _ in
            Text("This will detach the two lists.")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Connections")
                .font(.ilTitle(20))
            Text("Drag a node onto another to connect lists. Tap a connection to remove it.")
                .font(.ilMono(10))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
    }

    @ViewBuilder
    private func graph(viewModel: ListConnectionsViewModel) -> some View {
        GeometryReader { proxy in
            ZStack {
                edgesCanvas(viewModel: viewModel)
                dragGuideLine
                nodeOverlay(viewModel: viewModel)
            }
            .onAppear {
                canvasSize = proxy.size
                viewModel.layout(in: proxy.size)
            }
            .onChange(of: proxy.size) { _, newValue in
                canvasSize = newValue
                viewModel.layout(in: newValue)
            }
        }
        .background(ILColor.background)
    }

    @ViewBuilder
    private func edgesCanvas(viewModel: ListConnectionsViewModel) -> some View {
        Canvas { context, _ in
            for edge in viewModel.edges {
                guard let fromNode = viewModel.nodes.first(where: { $0.id == edge.fromListId }),
                      let toNode = viewModel.nodes.first(where: { $0.id == edge.toListId }) else {
                    continue
                }
                var path = Path()
                path.move(to: fromNode.position)
                path.addLine(to: toNode.position)
                context.stroke(path, with: .color(.secondary), lineWidth: 2)
                if let label = edge.label, !label.isEmpty {
                    let mid = CGPoint(
                        x: (fromNode.position.x + toNode.position.x) / 2,
                        y: (fromNode.position.y + toNode.position.y) / 2
                    )
                    context.draw(
                        Text(label).font(.ilMono(9)).foregroundColor(.secondary),
                        at: mid
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var dragGuideLine: some View {
        // Visual cue while the user drags from one node onto another.
        if let sourceID = dragSourceID,
           let viewModel = viewModel,
           let source = viewModel.nodes.first(where: { $0.id == sourceID }),
           let dragLocation {
            Path { path in
                path.move(to: source.position)
                path.addLine(to: dragLocation)
            }
            .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [4, 4]))
            .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private func nodeOverlay(viewModel: ListConnectionsViewModel) -> some View {
        ForEach(viewModel.nodes) { node in
            nodeView(node)
                .position(node.position)
                .gesture(nodeDragGesture(node: node, viewModel: viewModel))
                .onTapGesture(count: 2) {
                    // Double-tap to surface edge-removal for connected
                    // edges. Single-tap is reserved for selection.
                    if let firstEdge = viewModel.edges.first(where: {
                        $0.fromListId == node.id || $0.toListId == node.id
                    }) {
                        edgeIDPendingRemove = firstEdge.id
                    }
                }
        }

        // Hit-targets for edges — invisible circles at the midpoint
        // of each edge so the user can tap to remove.
        ForEach(viewModel.edges) { edge in
            if let from = viewModel.nodes.first(where: { $0.id == edge.fromListId }),
               let to = viewModel.nodes.first(where: { $0.id == edge.toListId }) {
                Circle()
                    .fill(Color.clear)
                    .frame(width: 20, height: 20)
                    .contentShape(Circle())
                    .position(
                        x: (from.position.x + to.position.x) / 2,
                        y: (from.position.y + to.position.y) / 2
                    )
                    .onTapGesture {
                        edgeIDPendingRemove = edge.id
                    }
            }
        }
    }

    @ViewBuilder
    private func nodeView(_ node: ListConnectionsViewModel.Node) -> some View {
        let diameter = Self.nodeRadius * 2
        ZStack {
            Circle()
                .fill(node.isFocused ? Color.accentColor : ILColor.surface2)
                .frame(width: diameter, height: diameter)
                .overlay(
                    Circle().stroke(Color.secondary, lineWidth: 1)
                )
            Text(node.title)
                .font(.ilMono(9))
                .foregroundStyle(node.isFocused ? .white : .primary)
                .lineLimit(2)
                .frame(width: diameter - 8)
                .multilineTextAlignment(.center)
        }
    }

    private func nodeDragGesture(
        node: ListConnectionsViewModel.Node,
        viewModel: ListConnectionsViewModel
    ) -> some Gesture {
        DragGesture()
            .onChanged { value in
                if dragSourceID == nil { dragSourceID = node.id }
                dragLocation = value.location
            }
            .onEnded { value in
                // If the drag finished over another node, propose
                // a new connection; otherwise treat the drag as a
                // node-reposition.
                if let target = viewModel.nodes.first(where: {
                    $0.id != node.id &&
                        hypot($0.position.x - value.location.x, $0.position.y - value.location.y)
                        < Self.nodeRadius
                }) {
                    pendingNewEdge = PendingEdge(from: node.id, to: target.id)
                } else {
                    viewModel.setNodePosition(id: node.id, to: value.location)
                }
                dragSourceID = nil
                dragLocation = nil
            }
    }

    @ViewBuilder
    private func addEdgeConfirmation(
        viewModel: ListConnectionsViewModel,
        pending: PendingEdge
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add connection")
                .font(.ilSubtitle())
            Text("Connect \"\(name(of: pending.from, in: viewModel))\" to \"\(name(of: pending.to, in: viewModel))\"?")
                .font(.ilSubtitle())
                .foregroundStyle(.secondary)
            TextField("Label (optional)", text: $addEdgeLabel)
                .textFieldStyle(.roundedBorder)
            HStack {
                Button("Cancel", role: .cancel) {
                    pendingNewEdge = nil
                    addEdgeLabel = ""
                }
                Spacer()
                Button("Connect") {
                    let label = addEdgeLabel.trimmingCharacters(in: .whitespacesAndNewlines)
                    Task {
                        await viewModel.addConnection(
                            from: pending.from,
                            to: pending.to,
                            label: label.isEmpty ? nil : label
                        )
                        addEdgeLabel = ""
                        pendingNewEdge = nil
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
        .frame(minWidth: 380)
    }

    private func name(of id: String, in viewModel: ListConnectionsViewModel) -> String {
        viewModel.nodes.first { $0.id == id }?.title ?? id
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button("Done") { dismiss() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
        }
        .padding(12)
    }

    private func subscribe(viewModel: ListConnectionsViewModel) async {
        Task { [weak viewModel] in
            for await event in environment.listsEventBus.events() {
                guard let viewModel else { return }
                viewModel.apply(event: event)
            }
        }
    }
}

private struct PendingEdge: Identifiable, Equatable {
    let from: String
    let to: String
    var id: String { "\(from)->\(to)" }
}
