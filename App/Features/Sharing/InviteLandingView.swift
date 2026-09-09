// InviteLandingView
//
// The email-invite landing (work-consolidation.md G23 / issue #48). Presented
// by `ResolveShareView` when the opened link is an `…/invite/{token}` rather
// than a `…/shared/{token}`, so `MainWindowView`'s existing share-link sheet is
// the only presentation point either flavour needs.
//
// Deliberately has **no Accept button**: the claim route is session-only in the
// live spec, so a native Accept would 401 every time. The primary action opens
// the invite in the browser, which is where the grant can actually be made.
//
// Per Decision 0003 the view imports only InterlinedDomain.

import SwiftUI
import InterlinedDomain

struct InviteLandingView: View {

    let parsed: ParsedShare
    let environment: AppEnvironment

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var viewModel: InviteLandingViewModel?

    var body: some View {
        Group {
            if let viewModel {
                content(viewModel: viewModel)
            } else {
                ProgressView()
                    .accessibilityLabel("Opening invite")
                    .padding()
            }
        }
        .frame(minWidth: 420, minHeight: 300)
        .task {
            if viewModel == nil {
                let model = InviteLandingViewModel(
                    service: environment.sharing,
                    parsed: parsed,
                    webBaseURL: environment.shareBaseURL
                )
                viewModel = model
                await model.resolve()
            }
        }
    }

    @ViewBuilder
    private func content(viewModel: InviteLandingViewModel) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            if viewModel.isLoading && viewModel.invite == nil {
                ProgressView("Opening invite…")
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 24)
            } else if viewModel.isUnsupportedResource {
                unsupportedState
            } else if let error = viewModel.error, viewModel.invite == nil {
                errorState(error: error, viewModel: viewModel)
            } else if let invite = viewModel.invite {
                resolvedState(invite: invite, guidance: viewModel.guidance)
            }

            Spacer()
            footer(viewModel: viewModel)
        }
        .padding(16)
    }

    // MARK: - States

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("You're Invited")
                .font(.ilTitle(20))
            Text("Someone invited you to a \(parsed.kind == .list ? "list" : "document") by email.")
                .font(.ilMono(10))
                .foregroundStyle(.secondary)
        }
    }

    private func resolvedState(invite: ResolvedListInvite, guidance: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: invite.accepted ? "checkmark.circle.fill" : "envelope.open")
                    .font(.ilDisplay(28))
                    .foregroundStyle(invite.accepted ? Color.green : Color.accentColor)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(invite.resourceTitle ?? "A shared list")
                        .font(.ilSubtitle())
                    Text("Grants \(invite.role.label) access")
                        .font(.ilMono(11))
                        .foregroundStyle(.secondary)
                }
            }

            noticeBox(
                systemImage: invite.wrongAccount
                    ? "person.crop.circle.badge.exclamationmark"
                    : "safari",
                text: guidance
            )
        }
    }

    private var unsupportedState: some View {
        noticeBox(
            systemImage: "safari",
            text: "Open this invite in your browser to see what it grants and accept it."
        )
    }

    private func errorState(error: Error, viewModel: InviteLandingViewModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Couldn't open this invite", systemImage: "exclamationmark.triangle")
                .font(.ilBody().weight(.semibold))
            // The server returns one 404 for unknown / expired / revoked, so
            // the copy names all three rather than guessing.
            Text("The invite may have expired, been revoked, or never existed.")
                .font(.ilMono(11))
                .foregroundStyle(.secondary)
            Text(error.localizedDescription)
                .font(.ilMono(11))
                .foregroundStyle(.secondary)
            Button("Try Again") {
                Task { await viewModel.resolve() }
            }
            .buttonStyle(.bordered)
        }
    }

    private func noticeBox(systemImage: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(text)
                .font(.ilMono(11))
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.08))
    }

    // MARK: - Footer

    @ViewBuilder
    private func footer(viewModel: InviteLandingViewModel) -> some View {
        HStack {
            Button("Close") { dismiss() }
                .buttonStyle(.bordered)
            Spacer()
            if let url = viewModel.acceptInBrowserURL {
                Button("Accept in Browser") {
                    openURL(url)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .help("Accepting an invite needs a web session — the app can't complete it yet")
            }
        }
    }
}
