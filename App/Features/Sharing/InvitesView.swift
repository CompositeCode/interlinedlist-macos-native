// InvitesView
//
// The "Invite by email" sheet for a list or a document (work-consolidation.md
// G3). Mirrors the web sharing dialog's invite section: a compose row (email +
// role + Send invite) atop a "Pending invites" table (email, role, status,
// expiry, revoke). Presented from the Lists and Documents toolbars.
//
// One view serves both resources via `ShareTarget`; the view model dispatches
// to the list/document half of the service.
//
// Clipboard without AppKit: when a send returns a claim url, a SwiftUI
// `ShareLink` offers it (the system share sheet includes "Copy") — no
// `NSPasteboard` (Decision 0004 SwiftUI-only).

import SwiftUI
import InterlinedDomain

struct InvitesView: View {

    let target: ShareTarget
    let environment: AppEnvironment

    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: InvitesViewModel?

    var body: some View {
        Group {
            if let viewModel {
                content(viewModel: viewModel)
            } else {
                ProgressView()
                    .accessibilityLabel("Loading invites")
                    .padding()
            }
        }
        .frame(minWidth: 560, minHeight: 480)
        .task {
            if viewModel == nil {
                let model = InvitesViewModel(service: environment.sharing, target: target)
                viewModel = model
                await model.load()
            }
        }
    }

    @ViewBuilder
    private func content(viewModel: InvitesViewModel) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            if viewModel.showSubscriberUpsell {
                subscriberUpsell(viewModel: viewModel)
            } else {
                composeForm(viewModel: viewModel)
            }
            Divider()
            pendingInvites(viewModel: viewModel)
            if let error = viewModel.error {
                Label(error.localizedDescription, systemImage: "exclamationmark.triangle")
                    .font(.ilMono(11))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 6)
            }
            Divider()
            footer
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Invite by email")
                .font(.ilTitle(20))
            Text("Send an email invite to someone who doesn't have an account yet, or invite by email instead of searching. They get access when they accept.")
                .font(.ilMono(10))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
    }

    // MARK: - Compose form

    @ViewBuilder
    private func composeForm(viewModel: InvitesViewModel) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                TextField("name@example.com", text: Binding(
                    get: { viewModel.newEmail },
                    set: { viewModel.newEmail = $0 }
                ))
                .textFieldStyle(.roundedBorder)
                .onSubmit { Task { await viewModel.send() } }
                .accessibilityLabel("Invitee email address")

                Picker("Role", selection: Binding(
                    get: { viewModel.newRole },
                    set: { viewModel.newRole = $0 }
                )) {
                    ForEach(ShareRole.allCases) { role in
                        Text(role.label).tag(role)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 130)
                .accessibilityLabel("Role for the invite")

                Button {
                    Task { await viewModel.send() }
                } label: {
                    if viewModel.isSending {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Send invite")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isSending)
            }

            if let url = viewModel.lastSentURL {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .accessibilityHidden(true)
                    Text("Invite sent.")
                        .font(.ilMono(11))
                        .foregroundStyle(.secondary)
                    SwiftUI.ShareLink(item: url) { Text("Share link") }
                    Spacer()
                    Button("Dismiss") { viewModel.clearSentURL() }
                        .buttonStyle(.plain)
                        .font(.ilMono(11))
                }
            }
        }
        .padding(12)
    }

    // MARK: - Pending invites

    @ViewBuilder
    private func pendingInvites(viewModel: InvitesViewModel) -> some View {
        List {
            Section("Pending invites (\(viewModel.invites.count))") {
                if viewModel.invites.isEmpty, viewModel.isLoading, !viewModel.hasLoadedOnce {
                    ProgressView().accessibilityLabel("Loading invites").frame(maxWidth: .infinity)
                } else if viewModel.invites.isEmpty {
                    Text("No pending invites.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(viewModel.invites) { invite in
                        inviteRow(viewModel: viewModel, invite: invite)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func inviteRow(viewModel: InvitesViewModel, invite: ShareInvite) -> some View {
        HStack(spacing: 10) {
            Text(invite.email)
                .font(.ilBody())
                .frame(minWidth: 160, alignment: .leading)
                .textSelection(.enabled)
            Text(invite.role.label)
                .font(.ilMono(10))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(0.12), in: Capsule())
            Text(invite.accepted ? "Accepted" : "Pending")
                .font(.ilMono(10))
                .foregroundStyle(invite.accepted ? .green : .secondary)
                .frame(width: 76, alignment: .leading)
            Text(expiryLabel(invite.expiresAt))
                .font(.ilMono(10))
                .foregroundStyle(.secondary)
                .frame(width: 90, alignment: .leading)
            Spacer()
            Button(role: .destructive) {
                Task { await viewModel.revoke(token: invite.token) }
            } label: {
                Text("Revoke").foregroundStyle(.red)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("Revoke invite for \(invite.email)")
        }
        .padding(.vertical, 2)
    }

    // MARK: - Upsell / footer

    private func subscriberUpsell(viewModel: InvitesViewModel) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "star.circle.fill")
                .font(.ilDisplay(24))
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text("Email invites are a subscriber feature")
                    .font(.ilBody().weight(.semibold))
                Text("Upgrade your account to invite people by email. Existing invites keep working, and you can still revoke them.")
                    .font(.ilMono(11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Dismiss") { viewModel.dismissUpsell() }
                .buttonStyle(.bordered)
        }
        .padding(12)
        .background(Color.accentColor.opacity(0.08))
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

    private func expiryLabel(_ date: Date?) -> String {
        guard let date else { return "Never" }
        return date.formatted(date: .abbreviated, time: .omitted)
    }
}
