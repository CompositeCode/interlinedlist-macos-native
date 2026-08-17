// ShareLinksView
//
// The "Links" panel of the share sheet for a list or a document
// (work-consolidation.md G3). A create form (role picker over `ShareRole.allCases`
// + optional expiry) atop a list of active links, each with a
// copy/share affordance and a revoke button. Presented as a sheet from
// the Lists toolbar and the Documents editor toolbar.
//
// Clipboard without AppKit: each active link row uses SwiftUI's built-in
// `ShareLink` view (the system share sheet, which includes "Copy") to
// hand the URL to the user. No `NSPasteboard`, no `import AppKit`
// (Decision 0004 SwiftUI-only). Because our domain model is *also* named
// `ShareLink`, this file refers to it as `InterlinedDomain.ShareLink`
// wherever the two could collide.
//
// Subscriber gate: when the view model raises `showSubscriberUpsell`
// (create blocked for a free account), the form area swaps to an upsell
// callout instead of surfacing an error banner.

import SwiftUI
import InterlinedDomain

struct ShareLinksView: View {

    let target: ShareTarget
    let environment: AppEnvironment

    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: ShareLinksViewModel?
    @State private var expiryEnabled: Bool = false

    var body: some View {
        Group {
            if let viewModel {
                content(viewModel: viewModel)
            } else {
                ProgressView()
                    .accessibilityLabel("Loading share links")
                    .padding()
            }
        }
        .frame(minWidth: 520, minHeight: 460)
        .task {
            if viewModel == nil {
                let model = ShareLinksViewModel(service: environment.sharing, target: target)
                viewModel = model
                await model.load()
            }
        }
    }

    @ViewBuilder
    private func content(viewModel: ShareLinksViewModel) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            createForm(viewModel: viewModel)
            Divider()
            activeLinks(viewModel: viewModel)
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
            Text("Share Links")
                .font(.ilTitle(20))
            Text("Create a link anyone can use to open this \(target.noun).")
                .font(.ilMono(10))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
    }

    // MARK: - Create form

    @ViewBuilder
    private func createForm(viewModel: ShareLinksViewModel) -> some View {
        if viewModel.showSubscriberUpsell {
            subscriberUpsell(viewModel: viewModel)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    Picker("Access", selection: Binding(
                        get: { viewModel.newRole },
                        set: { viewModel.newRole = $0 }
                    )) {
                        ForEach(ShareRole.allCases) { role in
                            Text(role.label).tag(role)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 160)
                    .accessibilityLabel("Access level for new link")

                    Toggle("Expires", isOn: Binding(
                        get: { expiryEnabled },
                        set: { on in
                            expiryEnabled = on
                            viewModel.newExpiresAt = on ? (viewModel.newExpiresAt ?? defaultExpiry) : nil
                        }
                    ))
                    .toggleStyle(.checkbox)

                    if expiryEnabled {
                        DatePicker(
                            "Expiry date",
                            selection: Binding(
                                get: { viewModel.newExpiresAt ?? defaultExpiry },
                                set: { viewModel.newExpiresAt = $0 }
                            ),
                            in: Date()...,
                            displayedComponents: [.date]
                        )
                        .labelsHidden()
                        .datePickerStyle(.field)
                    }

                    Spacer()

                    Button {
                        Task { await viewModel.create() }
                    } label: {
                        if viewModel.isCreating {
                            ProgressView().controlSize(.small)
                        } else {
                            Label("Create Link", systemImage: "link.badge.plus")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.isCreating)
                    .accessibilityLabel("Create share link")
                }
                Text(roleHint(viewModel.newRole))
                    .font(.ilMono(10))
                    .foregroundStyle(.secondary)
            }
            .padding(12)
        }
    }

    private func subscriberUpsell(viewModel: ShareLinksViewModel) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "star.circle.fill")
                .font(.ilDisplay(24))
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text("Share links are a subscriber feature")
                    .font(.ilBody().weight(.semibold))
                Text("Upgrade your account to create shareable links for your lists and documents. Existing links keep working, and you can still revoke them.")
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

    // MARK: - Active links

    @ViewBuilder
    private func activeLinks(viewModel: ShareLinksViewModel) -> some View {
        List {
            Section("Active links") {
                if viewModel.links.isEmpty, viewModel.isLoading, !viewModel.hasLoadedOnce {
                    ProgressView()
                        .accessibilityLabel("Loading links")
                        .frame(maxWidth: .infinity)
                } else if viewModel.links.isEmpty {
                    Text("No active links yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(viewModel.links) { link in
                        linkRow(viewModel: viewModel, link: link)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func linkRow(viewModel: ShareLinksViewModel, link: InterlinedDomain.ShareLink) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "link")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(link.role.label)
                    .font(.ilBody())
                Text(subtitle(for: link))
                    .font(.ilMono(10))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            Spacer()
            if let url = shareURL(for: link) {
                // SwiftUI's system ShareLink — includes "Copy" — so no
                // AppKit pasteboard is needed (Decision 0004).
                SwiftUI.ShareLink(item: url) {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel("Share this link")
            }
            Button(role: .destructive) {
                Task { await viewModel.revoke(token: link.token) }
            } label: {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Revoke this link")
        }
        .padding(.vertical, 2)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Spacer()
            Button("Done") { dismiss() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
        }
        .padding(12)
    }

    // MARK: - Presentation helpers

    /// A best-effort share URL: prefer the server-provided `url`, else build
    /// the canonical web URL from the default base + token.
    private func shareURL(for link: InterlinedDomain.ShareLink) -> URL? {
        if let url = link.url { return url }
        let kind: ParsedShare.Kind = target.isDocument ? .document : .list
        return ShareURLParser.webURL(base: environment.shareBaseURL, kind: kind, token: link.token)
    }

    private func subtitle(for link: InterlinedDomain.ShareLink) -> String {
        if let url = shareURL(for: link) { return url.absoluteString }
        return "Token: \(link.token)"
    }

    private func roleHint(_ role: ShareRole) -> String {
        switch role {
        case .watcher: return "Viewers can open and read, but not change anything."
        case .collaborator: return "Editors can open and change content."
        case .manager: return "Admins can open, change content, and manage settings."
        }
    }

    private var defaultExpiry: Date {
        Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date().addingTimeInterval(7 * 86_400)
    }
}
