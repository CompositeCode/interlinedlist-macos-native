// LinkedAccountsView
//
// The Settings > "Linked accounts" pane (PLAN.md §1 "Profile & account",
// §6 M6). Lists the signed-in account's linked OAuth identities and offers
// a per-provider "Link account ↗" button that opens the web authorize flow
// in the user's default browser via SwiftUI's `openURL` — no AppKit, no
// ASWebAuthenticationSession (browser-handoff v1, per the approved spike).
//
// Mastodon requires an instance host, so its link button first prompts for
// the instance domain before resolving the URL. New identities appear after
// the user returns and taps Refresh.
//
// Per decision 0003 the view consumes only `InterlinedDomain`.

import SwiftUI
import InterlinedDomain

struct LinkedAccountsView: View {

    @Environment(\.appEnvironment) private var environment
    @Environment(\.openURL) private var openURL

    @State private var viewModel: LinkedAccountsViewModel?
    @State private var mastodonInstance: String = ""
    @State private var showMastodonPrompt: Bool = false

    var body: some View {
        Group {
            if let viewModel {
                content(viewModel: viewModel)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task {
            guard viewModel == nil, let environment else { return }
            let vm = LinkedAccountsViewModel(userService: environment.userService)
            viewModel = vm
            await vm.load()
        }
    }

    @ViewBuilder
    private func content(viewModel: LinkedAccountsViewModel) -> some View {
        Form {
            Section {
                if let error = viewModel.loadError, viewModel.identities.isEmpty {
                    Text(error.localizedDescription)
                        .foregroundStyle(.secondary)
                } else if viewModel.identities.isEmpty, !viewModel.isLoading {
                    Text("No linked accounts yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(viewModel.identities) { identity in
                        LinkedIdentityRow(identity: identity)
                    }
                }
            } header: {
                Text("Connected accounts")
            } footer: {
                Text("Linking opens interlinedlist.com in your browser; return here and Refresh once done.")
                    .font(.ilMono(10))
            }

            Section("Link an account") {
                ForEach(viewModel.linkableProviders, id: \.wireToken) { provider in
                    Button {
                        link(provider: provider, viewModel: viewModel)
                    } label: {
                        Label {
                            Text("Link \(provider.displayName) \(Image(systemName: "arrow.up.right"))")
                        } icon: {
                            Image(systemName: provider.iconName)
                        }
                    }
                }
                if let error = viewModel.linkError {
                    Text(error.localizedDescription)
                        .font(.ilMono(10))
                        .foregroundStyle(Color.accentColor)
                }
            }
        }
        .formStyle(.grouped)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await viewModel.load() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(viewModel.isLoading)
            }
        }
        .alert("Mastodon instance", isPresented: $showMastodonPrompt) {
            TextField("mastodon.social", text: $mastodonInstance)
            Button("Cancel", role: .cancel) {}
            Button("Continue") {
                if let url = viewModel.linkURL(for: .mastodon, instance: mastodonInstance) {
                    openURL(url)
                }
                mastodonInstance = ""
            }
        } message: {
            Text("Enter the host of your Mastodon instance (e.g. mastodon.social).")
        }
    }

    private func link(provider: IdentityProvider, viewModel: LinkedAccountsViewModel) {
        if provider == .mastodon {
            showMastodonPrompt = true
            return
        }
        if let url = viewModel.linkURL(for: provider) {
            openURL(url)
        }
    }
}

// MARK: - LinkedIdentityRow

private struct LinkedIdentityRow: View {
    let identity: LinkedIdentity

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: identity.provider.iconName)
                .frame(width: 22)
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(identity.provider.displayName)
                    .font(.ilBody())
                    .fontWeight(.medium)
                if let handle = identity.handle {
                    Text(handle)
                        .font(.ilMono(10))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let connectedAt = identity.connectedAt {
                Text(connectedAt, format: .dateTime.year().month().day())
                    .font(.ilMono(9))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(rowAccessibilityLabel)
    }

    private var rowAccessibilityLabel: String {
        var parts = [identity.provider.displayName]
        if let handle = identity.handle { parts.append(handle) }
        if let connectedAt = identity.connectedAt {
            parts.append("connected \(connectedAt.formatted(date: .abbreviated, time: .omitted))")
        }
        return parts.joined(separator: ", ")
    }
}

// MARK: - IdentityProvider presentation

extension IdentityProvider {

    /// Human-readable label. `.other` surfaces the raw token capitalized so
    /// an unrecognized provider still renders a legible name.
    var displayName: String {
        switch self {
        case .github:   return "GitHub"
        case .mastodon: return "Mastodon"
        case .bluesky:  return "Bluesky"
        case .linkedin: return "LinkedIn"
        case .other(let raw):
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "Account" : trimmed.capitalized
        }
    }

    /// SF Symbol approximating the provider (no third-party brand glyphs in
    /// the symbol set). `.other` falls back to a generic link icon.
    var iconName: String {
        switch self {
        case .github:   return "chevron.left.forwardslash.chevron.right"
        case .mastodon: return "number.square"
        case .bluesky:  return "cloud"
        case .linkedin: return "briefcase"
        case .other:    return "link"
        }
    }
}
