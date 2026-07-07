// WatchersView
//
// The M3 sharing panel sheet (PLAN.md §6 M3 list sharing).
// Role-edit-for-existing-watchers only — invite-new-user UX waits
// for an upstream lookup endpoint (`NEXT-WORK.md` NW-1). The
// infobox at the bottom makes the gap intentional and visible.

import SwiftUI
import InterlinedDomain

struct WatchersView: View {

    let listId: String
    let environment: AppEnvironment

    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: WatchersViewModel?
    @State private var userIDPendingRemove: String?
    @State private var showAddWatcher: Bool = false

    var body: some View {
        Group {
            if let viewModel {
                content(viewModel: viewModel)
            } else {
                ProgressView()
                    .accessibilityLabel("Loading sharing panel")
                    .padding()
            }
        }
        .frame(minWidth: 480, minHeight: 380)
        .task {
            if viewModel == nil {
                let model = WatchersViewModel(
                    lists: environment.lists,
                    userService: environment.userService,
                    eventBus: environment.listsEventBus,
                    listId: listId
                )
                viewModel = model
                await model.load()
                await subscribe(viewModel: model)
            }
        }
    }

    @ViewBuilder
    private func content(viewModel: WatchersViewModel) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            header(viewModel: viewModel)
            Divider()
            List {
                if viewModel.watchers.isEmpty, viewModel.isLoading {
                    ProgressView()
                        .accessibilityLabel("Loading watchers")
                        .frame(maxWidth: .infinity)
                } else if viewModel.watchers.isEmpty {
                    Text("No watchers yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(viewModel.watchers) { watcher in
                        watcherRow(viewModel: viewModel, watcher: watcher)
                    }
                }
            }
            if let error = viewModel.error {
                Label(error.localizedDescription, systemImage: "exclamationmark.triangle")
                    .padding(8)
            }
            Divider()
            footer
        }
        .sheet(isPresented: $showAddWatcher) {
            AddWatcherSheetView(viewModel: viewModel)
        }
        .confirmationDialog(
            "Remove this watcher?",
            isPresented: Binding(
                get: { userIDPendingRemove != nil },
                set: { if !$0 { userIDPendingRemove = nil } }
            ),
            presenting: userIDPendingRemove
        ) { id in
            Button("Remove", role: .destructive) {
                Task {
                    await viewModel.remove(userId: id)
                    userIDPendingRemove = nil
                }
            }
            Button("Cancel", role: .cancel) {
                userIDPendingRemove = nil
            }
        } message: { _ in
            Text("This user will lose access to the list.")
        }
    }

    private func header(viewModel: WatchersViewModel) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Share")
                    .font(.ilTitle(20))
                Text("Manage who can see and edit this list.")
                    .font(.ilMono(10))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Add Watcher") {
                showAddWatcher = true
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
    }

    @ViewBuilder
    private func watcherRow(viewModel: WatchersViewModel, watcher: ListWatcher) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "person.crop.circle")
                .font(.ilMono(24))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(watcher.username ?? watcher.userId)
                    .font(.ilBody())
                if let username = watcher.username {
                    Text("@\(username)")
                        .font(.ilMono(10))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Picker("Role", selection: Binding(
                get: { watcher.role },
                set: { newRole in
                    Task { await viewModel.setRole(userId: watcher.userId, role: newRole) }
                }
            )) {
                Text("Owner").tag(WatcherRole.owner)
                Text("Editor").tag(WatcherRole.editor)
                Text("Viewer").tag(WatcherRole.viewer)
            }
            .pickerStyle(.menu)
            .frame(width: 100)
            .accessibilityLabel("Role for \(watcher.username ?? watcher.userId)")

            Button {
                userIDPendingRemove = watcher.userId
            } label: {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove \(watcher.username ?? watcher.userId)")
        }
        .padding(.vertical, 2)
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

    private func subscribe(viewModel: WatchersViewModel) async {
        Task { [weak viewModel] in
            for await event in environment.listsEventBus.events() {
                guard let viewModel else { return }
                viewModel.apply(event: event)
            }
        }
    }
}
