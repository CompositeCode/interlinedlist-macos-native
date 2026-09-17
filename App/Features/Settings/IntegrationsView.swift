// IntegrationsView
//
// Settings ▸ Integrations (GitHub #47 / G33) — every connected provider in one
// place, with Link, Verify and Disconnect as each row's actions.
//
// `LinkedAccountsView` could only **link**. Once an account was connected there
// was no way to check it, reconfigure it, or remove it from the Mac.
//
// The rows are **data-driven** rather than a switch statement per provider: what
// a row offers comes from `IdentityProvider`'s capability flags, so adding a
// provider does not mean finding every place that enumerates them. That is also
// what makes Mastodon work — it is the one provider that supports several
// connections, and it renders as one row per instance.
//
// Pure SwiftUI; no AppKit. Decision 0003: consumes only `InterlinedDomain`.

import SwiftUI
import InterlinedDomain

struct IntegrationsView: View {

    @Environment(\.appEnvironment) private var environment
    @Environment(\.openURL) private var openURL
    @State private var viewModel: IntegrationsViewModel?
    @State private var pendingDisconnect: LinkedIdentity?

    var body: some View {
        Form {
            if let viewModel {
                connectedSection(viewModel)
                githubSection(viewModel)
                connectSection(viewModel)
                if let error = viewModel.loadError {
                    Section {
                        Text(error.localizedDescription)
                            .font(.ilMono(10))
                            .foregroundStyle(.orange)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .task {
            guard viewModel == nil, let environment else { return }
            let model = IntegrationsViewModel(user: environment.userService)
            viewModel = model
            await model.load()
        }
        .confirmationDialog(
            "Disconnect \(pendingDisconnect?.provider.displayName ?? "")?",
            isPresented: Binding(
                get: { pendingDisconnect != nil },
                set: { if !$0 { pendingDisconnect = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Disconnect", role: .destructive) {
                guard let identity = pendingDisconnect, let viewModel else { return }
                pendingDisconnect = nil
                Task { await viewModel.disconnect(identity) }
            }
            Button("Cancel", role: .cancel) { pendingDisconnect = nil }
        } message: {
            // The consequence is the question. A generic "are you sure" tells
            // the user nothing they did not already know.
            if let identity = pendingDisconnect, let viewModel {
                Text(viewModel.disconnectConsequence(for: identity))
            }
        }
    }

    // MARK: - Connected

    @ViewBuilder
    private func connectedSection(_ viewModel: IntegrationsViewModel) -> some View {
        Section("Connected") {
            if viewModel.isLoading && viewModel.identities.isEmpty {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Loading connections…").foregroundStyle(.secondary)
                }
            } else if viewModel.connectedIdentities.isEmpty {
                Text("No accounts are connected yet.")
                    .font(.ilMono(10))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(viewModel.connectedIdentities) { identity in
                    identityRow(identity, viewModel: viewModel)
                }
            }
        }
    }

    @ViewBuilder
    private func identityRow(
        _ identity: LinkedIdentity,
        viewModel: IntegrationsViewModel
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: identity.provider.iconName)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    // The instance is part of the identity for Mastodon, so it
                    // belongs in the title — two rows reading "Mastodon" would
                    // be indistinguishable.
                    Text(rowTitle(identity))
                        .font(.ilBody())
                    if let handle = identity.handle, !handle.isEmpty {
                        Text(handle)
                            .font(.ilMono(10))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 8)

                if identity.provider.isVerifiable {
                    Button("Verify") {
                        Task { await viewModel.verify(identity) }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(viewModel.isVerifying(identity) || viewModel.isDisconnecting(identity))
                }
                if identity.provider.isDisconnectable {
                    Button("Disconnect", role: .destructive) {
                        pendingDisconnect = identity
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(viewModel.isDisconnecting(identity))
                }
                if viewModel.isVerifying(identity) || viewModel.isDisconnecting(identity) {
                    ProgressView().controlSize(.mini)
                }
            }

            statusLine(identity, viewModel: viewModel)
        }
        .padding(.vertical, 2)
    }

    private func rowTitle(_ identity: LinkedIdentity) -> String {
        guard let instance = identity.instance, !instance.isEmpty else {
            return identity.provider.displayName
        }
        return "\(identity.provider.displayName) · \(instance)"
    }

    @ViewBuilder
    private func statusLine(
        _ identity: LinkedIdentity,
        viewModel: IntegrationsViewModel
    ) -> some View {
        // Precedence matters: an error from this row's own last action is more
        // useful than a stale verify result, and both beat the connected-at
        // date. One line, not three.
        if let failure = viewModel.rowErrors[identity.id] {
            Text(failure)
                .font(.ilMono(10))
                .foregroundStyle(.orange)
        } else if let verified = viewModel.verifyResults[identity.id] {
            Label(
                verified ? "Connection is working" : "Connection isn't responding — reconnect it",
                systemImage: verified ? "checkmark.circle" : "exclamationmark.triangle"
            )
            .font(.ilMono(10))
            .foregroundStyle(verified ? Color.secondary : Color.orange)
        } else if let lastVerified = identity.lastVerifiedAt {
            Text("Last checked \(lastVerified.formatted(date: .abbreviated, time: .omitted))")
                .font(.ilMono(10))
                .foregroundStyle(.secondary)
        } else if let connectedAt = identity.connectedAt {
            Text("Connected \(connectedAt.formatted(date: .abbreviated, time: .omitted))")
                .font(.ilMono(10))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - GitHub

    @ViewBuilder
    private func githubSection(_ viewModel: IntegrationsViewModel) -> some View {
        if let github = viewModel.github {
            Section("GitHub") {
                if !github.isConfigured {
                    // A different message from "you have not linked GitHub":
                    // no amount of user action fixes this one.
                    Text("GitHub sign-in isn't configured on InterlinedList, so linking a GitHub account won't work right now.")
                        .font(.ilMono(10))
                        .foregroundStyle(.orange)
                } else if let url = github.manageOrgAccessURL {
                    Button("Update organization access…") { openURL(url) }
                    Text("Opens GitHub, where you grant or revoke this app's access to your organizations. Needed before a GitHub-backed list can read an org's issues.")
                        .font(.ilMono(10))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Connect

    @ViewBuilder
    private func connectSection(_ viewModel: IntegrationsViewModel) -> some View {
        Section("Connect an account") {
            ForEach(viewModel.connectableProviders, id: \.wireToken) { provider in
                HStack(spacing: 8) {
                    Image(systemName: provider.iconName)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    Text(provider.displayName)
                    if provider.supportsMultipleInstances {
                        Text("· you can connect several instances")
                            .font(.ilMono(10))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }
            // Linking itself stays in the Linked Accounts pane, which owns the
            // OAuth session and the Mastodon instance prompt. Duplicating that
            // flow here would mean two copies of an authorization handshake.
            Text("Connecting an account happens in Settings ▸ Linked accounts, which handles the sign-in window.")
                .font(.ilMono(10))
                .foregroundStyle(.secondary)
        }
    }
}
