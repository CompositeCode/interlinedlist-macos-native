// ResolveShareView
//
// The shared-resource landing (the-gaps.md G3). Presented as a sheet when
// the user opens a `…/lists/shared/{token}` or `…/documents/shared/{token}`
// link — pasted into the landing field or delivered via the
// `interlinedlist://` deep-link scheme. Shows the resolved resource title +
// granted role and, when claimable and signed in, a "Claim access" button.
// When the share needs auth (or no user is resolved), it prompts sign-in
// rather than rendering a broken claim button (ownership-gating).
//
// The current-user id is read from `AppEnvironment.currentUserStore` and
// handed to the view model as a plain `String?`, so the view model stays
// session-graph-free and unit-testable.

import SwiftUI
import InterlinedDomain

struct ResolveShareView: View {

    let parsed: ParsedShare
    let environment: AppEnvironment
    /// Called with the claim's resource id once the user successfully claims
    /// access, so the host can route to the resource (or just dismiss).
    var onClaimed: (ShareClaim) -> Void = { _ in }

    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: ResolveShareViewModel?

    var body: some View {
        Group {
            if let viewModel {
                content(viewModel: viewModel)
            } else {
                ProgressView()
                    .accessibilityLabel("Opening shared link")
                    .padding()
            }
        }
        .frame(minWidth: 420, minHeight: 300)
        .task {
            if viewModel == nil {
                let model = ResolveShareViewModel(
                    service: environment.sharing,
                    parsed: parsed,
                    currentUserID: environment.currentUserStore.currentUserID
                )
                viewModel = model
                await model.resolve()
            }
        }
    }

    @ViewBuilder
    private func content(viewModel: ResolveShareViewModel) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            if viewModel.isLoading && viewModel.resolved == nil {
                ProgressView("Resolving link…")
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 24)
            } else if let error = viewModel.error, viewModel.resolved == nil {
                errorState(error: error, viewModel: viewModel)
            } else if viewModel.didClaim {
                claimedState(viewModel: viewModel)
            } else if let resolved = viewModel.resolved {
                resolvedState(resolved: resolved, viewModel: viewModel)
            }

            Spacer()
            footer(viewModel: viewModel)
        }
        .padding(16)
    }

    // MARK: - States

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Shared \(parsed.kind == .list ? "List" : "Document")")
                .font(.ilTitle(20))
            Text("Someone shared this \(parsed.kind == .list ? "list" : "document") with you.")
                .font(.ilMono(10))
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func resolvedState(resolved: ResolvedShare, viewModel: ResolveShareViewModel) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: parsed.kind == .list ? "list.bullet.rectangle" : "doc.text")
                    .font(.ilDisplay(28))
                    .foregroundStyle(Color.accentColor)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(resolved.resource?.title ?? "Shared resource")
                        .font(.ilSubtitle())
                    Text("Grants \(resolved.role.label) access")
                        .font(.ilMono(11))
                        .foregroundStyle(.secondary)
                }
            }

            if viewModel.needsSignIn {
                signInPrompt
            }
        }
    }

    private var signInPrompt: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "person.crop.circle.badge.exclamationmark")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("Sign in to claim access to this \(parsed.kind == .list ? "list" : "document").")
                .font(.ilMono(11))
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.08))
    }

    private func claimedState(viewModel: ResolveShareViewModel) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.ilDisplay(28))
                .foregroundStyle(.green)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Access granted")
                    .font(.ilSubtitle())
                if let role = viewModel.claim?.role {
                    Text("You now have \(role.label) access.")
                        .font(.ilMono(11))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func errorState(error: Error, viewModel: ResolveShareViewModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Couldn't open this link", systemImage: "exclamationmark.triangle")
                .font(.ilBody().weight(.semibold))
            Text(error.localizedDescription)
                .font(.ilMono(11))
                .foregroundStyle(.secondary)
            Button("Try Again") {
                Task { await viewModel.resolve() }
            }
            .buttonStyle(.bordered)
        }
    }

    // MARK: - Footer

    @ViewBuilder
    private func footer(viewModel: ResolveShareViewModel) -> some View {
        HStack {
            Button("Close") { dismiss() }
                .buttonStyle(.bordered)
            Spacer()
            if viewModel.didClaim {
                Button("Open") {
                    if let claim = viewModel.claim { onClaimed(claim) }
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            } else if viewModel.canOfferClaim {
                Button {
                    Task {
                        await viewModel.claimAccess()
                        if let claim = viewModel.claim, viewModel.didClaim {
                            onClaimed(claim)
                        }
                    }
                } label: {
                    if viewModel.isLoading {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Claim Access")
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(viewModel.isLoading)
            }
        }
    }
}
