// SecuritySessionsView
//
// Settings ▸ Security (work-consolidation.md G19) — the account's active
// sessions with a per-row Revoke action. The honest complement to a
// never-expiring sync token: if a machine is lost, this is where the user cuts
// it off.
//
// SwiftUI-only (no AppKit). Consumes only `InterlinedDomain` per Decision 0003.

import SwiftUI
import InterlinedDomain

struct SecuritySessionsView: View {

    @Environment(\.appEnvironment) private var environment
    @State private var viewModel: SessionsViewModel?
    /// The session awaiting confirmation, when revoking would sign us out.
    @State private var pendingCurrentRevoke: ActiveSession?

    var body: some View {
        Group {
            if let viewModel {
                content(viewModel)
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task {
            if viewModel == nil {
                let model = SessionsViewModel(service: environment?.sessions)
                viewModel = model
                await model.load()
            }
        }
    }

    @ViewBuilder
    private func content(_ viewModel: SessionsViewModel) -> some View {
        if viewModel.isUnavailable {
            SettingsUnavailableView(
                title: "Sessions unavailable",
                message: "This build has no sessions service configured."
            )
        } else {
            Form {
                if let error = viewModel.error {
                    Section { SettingsErrorRow(error: error) }
                }
                Section("Active sessions") {
                    if viewModel.isLoading && viewModel.sessions.isEmpty {
                        ProgressView()
                    } else if viewModel.sessions.isEmpty {
                        Text("No active sessions.").foregroundStyle(.secondary)
                    } else {
                        ForEach(viewModel.sessions) { session in
                            row(session, viewModel: viewModel)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .confirmationDialog(
                "Revoke this session?",
                isPresented: Binding(
                    get: { pendingCurrentRevoke != nil },
                    set: { if !$0 { pendingCurrentRevoke = nil } }
                ),
                presenting: pendingCurrentRevoke
            ) { session in
                Button("Revoke and sign out", role: .destructive) {
                    Task { await viewModel.revoke(session); pendingCurrentRevoke = nil }
                }
                Button("Cancel", role: .cancel) { pendingCurrentRevoke = nil }
            } message: { _ in
                Text("This is the session this app is using. Revoking it signs you out on this Mac.")
            }
        }
    }

    @ViewBuilder
    private func row(_ session: ActiveSession, viewModel: SessionsViewModel) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(session.deviceLabel)
                    if session.isCurrent {
                        Text("This Mac")
                            .font(.caption2)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(.tint.opacity(0.15), in: Capsule())
                    }
                }
                if let lastUsed = session.lastUsedAt {
                    Text("Last used \(lastUsed.formatted(.relative(presentation: .named)))")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if viewModel.revokingID == session.id {
                ProgressView().controlSize(.small)
            } else {
                Button("Revoke") {
                    if session.isCurrent {
                        pendingCurrentRevoke = session
                    } else {
                        Task { await viewModel.revoke(session) }
                    }
                }
                .disabled(viewModel.revokingID != nil)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            session.isCurrent
                ? "\(session.deviceLabel), this Mac's session"
                : session.deviceLabel
        )
    }
}
