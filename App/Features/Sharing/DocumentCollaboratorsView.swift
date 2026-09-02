// DocumentCollaboratorsView
//
// The "Document Access & Permissions" sheet — the document analogue of a
// list's WatchersView (work-consolidation.md G3). Mirrors the web sharing
// dialog's top section: search for a user, choose the role new users get,
// optionally email them, then manage everyone in "Users with access" (change
// role, get a link, remove).
//
// Clipboard without AppKit: the per-row "Get link" uses SwiftUI's built-in
// `ShareLink` (the system share sheet, which includes "Copy") to hand the
// document's canonical URL to the user. No `NSPasteboard`, no `import AppKit`
// (Decision 0004 SwiftUI-only).
//
// Subscriber gate: adding a user / changing a role is subscriber-only; the
// view model raises `showSubscriberUpsell`, and this view swaps in an upsell
// callout instead of an error banner.

import SwiftUI
import InterlinedDomain

struct DocumentCollaboratorsView: View {

    let documentId: String
    let environment: AppEnvironment

    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: DocumentCollaboratorsViewModel?
    @State private var userIDPendingRemove: String?

    var body: some View {
        Group {
            if let viewModel {
                content(viewModel: viewModel)
            } else {
                ProgressView()
                    .accessibilityLabel("Loading access list")
                    .padding()
            }
        }
        .frame(minWidth: 560, minHeight: 520)
        .task {
            if viewModel == nil {
                let model = DocumentCollaboratorsViewModel(service: environment.sharing, documentId: documentId)
                viewModel = model
                await model.load()
            }
        }
    }

    @ViewBuilder
    private func content(viewModel: DocumentCollaboratorsViewModel) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    inviteControls(viewModel: viewModel)
                    if viewModel.showSubscriberUpsell {
                        subscriberUpsell(viewModel: viewModel)
                    }
                    Divider()
                    accessList(viewModel: viewModel)
                }
                .padding(12)
            }
            if let error = viewModel.error {
                errorBanner(error)
            }
            Divider()
            footer
        }
        .confirmationDialog(
            "Remove this person's access?",
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
            Button("Cancel", role: .cancel) { userIDPendingRemove = nil }
        } message: { _ in
            Text("This user will lose access to the document.")
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Document Access & Permissions")
                .font(.ilTitle(20))
            Text("Invite specific people. They get access without making this document public.")
                .font(.ilMono(10))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
    }

    // MARK: - Search + add controls

    @ViewBuilder
    private func inviteControls(viewModel: DocumentCollaboratorsViewModel) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                TextField(
                    "Search by username, display name, or email…",
                    text: Binding(
                        get: { viewModel.searchQuery },
                        set: { viewModel.searchQuery = $0 }
                    )
                )
                .textFieldStyle(.roundedBorder)
                .onSubmit { Task { await viewModel.search() } }
                .accessibilityLabel("Search for a person to add")

                Button {
                    Task { await viewModel.search() }
                } label: {
                    if viewModel.isSearching {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Search")
                    }
                }
                .disabled(viewModel.isSearching)
            }

            HStack(spacing: 12) {
                Text("Role for new users")
                    .font(.ilMono(11))
                    .foregroundStyle(.secondary)
                Picker("Role for new users", selection: Binding(
                    get: { viewModel.newRole },
                    set: { viewModel.newRole = $0 }
                )) {
                    ForEach(ShareRole.allCases) { role in
                        Text("\(role.label) — \(roleHint(role))").tag(role)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(maxWidth: 320, alignment: .leading)
            }

            Toggle(isOn: Binding(
                get: { viewModel.notify },
                set: { viewModel.notify = $0 }
            )) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Email this person")
                    Text("Sends an email invite. Uncheck to share silently (in-app notification only).")
                        .font(.ilMono(10))
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.checkbox)

            searchResults(viewModel: viewModel)
        }
    }

    @ViewBuilder
    private func searchResults(viewModel: DocumentCollaboratorsViewModel) -> some View {
        if !viewModel.searchResults.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(viewModel.searchResults) { candidate in
                    HStack(spacing: 10) {
                        Image(systemName: "person.crop.circle")
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(candidate.displayLabel).font(.ilBody())
                            if let username = candidate.username {
                                Text("@\(username)").font(.ilMono(10)).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Button("Add") {
                            Task { await viewModel.add(candidate: candidate) }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(viewModel.isAdding)
                    }
                    .padding(6)
                    .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
                }
            }
        }
    }

    // MARK: - Users with access

    @ViewBuilder
    private func accessList(viewModel: DocumentCollaboratorsViewModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Users with access (\(viewModel.collaborators.count))")
                .font(.ilBody().weight(.semibold))

            if viewModel.collaborators.isEmpty, viewModel.isLoading, !viewModel.hasLoadedOnce {
                ProgressView().accessibilityLabel("Loading users").frame(maxWidth: .infinity)
            } else if viewModel.collaborators.isEmpty {
                Text("No one has been given direct access yet.")
                    .font(.ilMono(11))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(viewModel.collaborators) { collaborator in
                    collaboratorRow(viewModel: viewModel, collaborator: collaborator)
                }
            }
        }
    }

    @ViewBuilder
    private func collaboratorRow(viewModel: DocumentCollaboratorsViewModel, collaborator: Collaborator) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "person.crop.circle.fill")
                .font(.ilDisplay(22))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(collaborator.displayLabel).font(.ilBody())
                if let username = collaborator.username {
                    Text("@\(username)").font(.ilMono(10)).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Picker("Role", selection: Binding(
                get: { collaborator.role },
                set: { newRole in
                    Task { await viewModel.setRole(userId: collaborator.userId, role: newRole) }
                }
            )) {
                ForEach(ShareRole.allCases) { role in
                    Text(role.label).tag(role)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: 120)
            .accessibilityLabel("Role for \(collaborator.displayLabel)")

            if let url = documentURL {
                SwiftUI.ShareLink(item: url) { Text("Get link") }
                    .accessibilityLabel("Get a link for \(collaborator.displayLabel)")
            }

            Button(role: .destructive) {
                userIDPendingRemove = collaborator.userId
            } label: {
                Text("Remove").foregroundStyle(.red)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("Remove \(collaborator.displayLabel)")
        }
        .padding(.vertical, 2)
    }

    // MARK: - Upsell / error / footer

    private func subscriberUpsell(viewModel: DocumentCollaboratorsViewModel) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "star.circle.fill")
                .font(.ilDisplay(24))
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text("Inviting people is a subscriber feature")
                    .font(.ilBody().weight(.semibold))
                Text("Upgrade your account to grant per-person access. You can still view and remove existing collaborators.")
                    .font(.ilMono(11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Dismiss") { viewModel.dismissUpsell() }
                .buttonStyle(.bordered)
        }
        .padding(10)
        .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }

    private func errorBanner(_ error: Error) -> some View {
        Label(error.localizedDescription, systemImage: "exclamationmark.triangle")
            .font(.ilMono(11))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.bottom, 6)
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

    // MARK: - Helpers

    /// The document's canonical web URL, offered by each row's "Get link". Built
    /// from the share base so no kit import leaks in (Decision 0003).
    private var documentURL: URL? {
        environment.shareBaseURL
            .appendingPathComponent("documents")
            .appendingPathComponent(documentId)
    }

    private func roleHint(_ role: ShareRole) -> String {
        switch role {
        case .watcher: return "Can view this document."
        case .collaborator: return "Can view and edit."
        case .manager: return "Can view, edit, and manage."
        }
    }
}
