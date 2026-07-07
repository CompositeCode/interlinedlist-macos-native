// AddWatcherSheetView
//
// Sheet for inviting a user to watch a list by handle (NW-1). Calls
// WatchersViewModel.lookupAndAdd to resolve the handle, then
// WatchersViewModel.addWatcher on confirm.
//
// Per Decision 0003 the view imports only InterlinedDomain.

import SwiftUI
import InterlinedDomain

struct AddWatcherSheetView: View {

    @Bindable var viewModel: WatchersViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var handleInput: String = ""
    @State private var selectedRole: WatcherRole = .viewer

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add Watcher")
                .font(.ilTitle(18))
                .padding(.top, 4)

            VStack(alignment: .leading, spacing: 8) {
                Text("Handle")
                    .font(.ilMono(10))
                    .foregroundStyle(.secondary)
                HStack {
                    TextField("@username", text: $handleInput)
                        .textFieldStyle(.roundedBorder)
                    Button("Search") {
                        Task { await viewModel.lookupAndAdd(handle: handleInput) }
                    }
                    .buttonStyle(.bordered)
                    .disabled(handleInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                              || viewModel.isLookingUp)
                }
                if viewModel.isLookingUp {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            if let found = viewModel.foundUser {
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    Text("Found user")
                        .font(.ilMono(10))
                        .foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        Image(systemName: "person.crop.circle")
                            .font(.ilBody())
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(found.displayName ?? found.username)
                                .font(.ilBody())
                                .fontWeight(.medium)
                            Text("@\(found.username)")
                                .font(.ilMono(10))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }

                    HStack {
                        Text("Role")
                            .font(.ilMono(10))
                            .foregroundStyle(.secondary)
                        Picker("Role", selection: $selectedRole) {
                            Text("Viewer").tag(WatcherRole.viewer)
                            Text("Editor").tag(WatcherRole.editor)
                            Text("Owner").tag(WatcherRole.owner)
                        }
                        .pickerStyle(.menu)
                        .frame(width: 120)
                        Spacer()
                    }
                }

                HStack {
                    Spacer()
                    Button("Add") {
                        Task {
                            await viewModel.addWatcher(userId: found.id, role: selectedRole)
                            if viewModel.error == nil {
                                dismiss()
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.pendingOperations.contains(found.id))
                }
            }

            if let error = viewModel.error {
                Text(error.localizedDescription)
                    .font(.ilMono(10))
                    .foregroundStyle(Color.accentColor)
            }

            Spacer()

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(minWidth: 380, minHeight: 260)
    }
}
