// DocumentInviteView
//
// The document email-invite landing (work-consolidation.md G24). Presented as
// a sheet when a `…/documents/invite/{token}` link is opened — pasted, or
// delivered via the `interlinedlist://` deep-link scheme.
//
// It shows what the invite grants and ends in "Accept in your browser", and
// that is the whole surface by design: `POST /api/documents/invite/{token}`
// is session-cookie-only in the live spec, so this app cannot claim an invite.
// Rendering an accept button here would be an affordance that always fails.
// Instead the landing states the branch the person is in and hands off a link.
// Accepting is documented as always free, so there is no entitlement gate.
//
// Mirrors `ResolveShareView`'s shape (header / branch / footer, sheet-sized)
// so the two landings feel like one family — but it is a separate view for a
// separate route, not a case bolted onto that one.
//
// Pure SwiftUI; no AppKit. Decision 0003: consumes only `InterlinedDomain`.

import SwiftUI
import InterlinedDomain

struct DocumentInviteView: View {

    let parsed: ParsedDocumentInvite
    let environment: AppEnvironment

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var viewModel: DocumentInviteViewModel?

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
        .frame(minWidth: 420, minHeight: 280)
        .task {
            if viewModel == nil {
                let model = DocumentInviteViewModel(
                    documents: environment.documentsService,
                    token: parsed.token,
                    webBaseURL: environment.shareBaseURL
                )
                viewModel = model
                await model.resolve()
            }
        }
    }

    @ViewBuilder
    private func content(viewModel: DocumentInviteViewModel) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            if viewModel.isLoading, viewModel.invite == nil {
                ProgressView("Opening invite…")
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 24)
            } else if let error = viewModel.error, viewModel.invite == nil {
                errorState(error: error, viewModel: viewModel)
            } else if let invite = viewModel.invite {
                resolvedState(invite: invite, viewModel: viewModel)
            }

            Spacer()
            footer(viewModel: viewModel)
        }
        .padding(16)
    }

    // MARK: - States

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Document Invitation")
                .font(.ilTitle())
            Text("Someone invited you to a document on InterlinedList.")
                .font(.ilBody())
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func resolvedState(
        invite: DocumentInvite,
        viewModel: DocumentInviteViewModel
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            LabeledContent("Document") {
                Text(viewModel.displayTitle)
                    .font(.ilBody())
            }
            LabeledContent("Access") {
                Text(roleDescription(invite.role))
                    .font(.ilBody())
            }

            Divider()

            // One line per branch. The copy names the *browser* explicitly in
            // every case, because that is where the invite is completed.
            switch viewModel.nextStep {
            case .alreadyAccepted:
                stepMessage(
                    icon: "checkmark.circle",
                    text: "You've already accepted this invitation. Open the document in your browser."
                )
            case .signInInBrowser:
                stepMessage(
                    icon: "person.crop.circle.badge.questionmark",
                    text: "Sign in on the web to accept. Invitations are accepted in the browser, not in this app."
                )
            case .wrongAccount:
                stepMessage(
                    icon: "person.crop.circle.badge.exclamationmark",
                    text: "The account signed in on the web doesn't match the invited address. Switch accounts in your browser, then accept."
                )
            case .acceptInBrowser, .none:
                stepMessage(
                    icon: "safari",
                    text: "Accepting an invitation happens in your browser. Accepting is free — no subscription required."
                )
            }
        }
    }

    private func stepMessage(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)
            Text(text)
                .font(.ilBody())
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func errorState(
        error: Error,
        viewModel: DocumentInviteViewModel
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(Color.accentColor)
                    .accessibilityHidden(true)
                Text("This invitation can't be opened")
                    .font(.ilSubtitle())
            }
            // The server answers one 404 for unknown / expired / revoked /
            // deleted so tokens can't be probed; say all four rather than
            // guessing which one it was.
            Text("The link may have expired, been revoked, or the document may no longer exist.")
                .font(.ilBody())
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(error.localizedDescription)
                .font(.ilMono(10))
                .foregroundStyle(.secondary)
            Button("Try again") {
                Task { await viewModel.resolve() }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    private func footer(viewModel: DocumentInviteViewModel) -> some View {
        HStack {
            Button("Close") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Spacer()
            if let url = viewModel.acceptURL {
                Button {
                    openURL(url)
                } label: {
                    Label(acceptButtonTitle(viewModel.nextStep), systemImage: "arrow.up.forward.app")
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .help("Opens interlinedlist.com — invitations are accepted in the browser")
            }
        }
    }

    // MARK: - Copy

    private func acceptButtonTitle(_ step: DocumentInviteViewModel.NextStep?) -> String {
        switch step {
        case .alreadyAccepted: return "Open in Browser"
        case .signInInBrowser: return "Sign In in Browser"
        case .wrongAccount:    return "Open in Browser"
        case .acceptInBrowser, .none: return "Accept in Browser"
        }
    }

    /// Turns the wire role into the phrasing the web uses for the same grant.
    private func roleDescription(_ role: String) -> String {
        switch role.lowercased() {
        case "watcher":      return "View only"
        case "collaborator": return "Can edit"
        case "manager":      return "Can manage"
        default:             return role
        }
    }
}
