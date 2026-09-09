// ResolveShareView
//
// The shared-resource landing (work-consolidation.md G3). Presented as a sheet when
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
            if parsed.mode == .invite {
                // An email invite is a different landing with a different
                // ending (the accept step is session-only, so it happens in
                // the browser). Branching here rather than in `MainWindowView`
                // keeps the deep-link plumbing to a single routed sheet.
                InviteLandingView(parsed: parsed, environment: environment)
            } else if let viewModel {
                content(viewModel: viewModel)
            } else {
                ProgressView()
                    .accessibilityLabel("Opening shared link")
                    .padding()
            }
        }
        .frame(minWidth: 420, minHeight: 300)
        .task {
            guard parsed.mode == .share else { return }
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

            if parsed.kind == .list {
                sharedRows(viewModel: viewModel)
            }
        }
    }

    /// The shared list's rows (work-consolidation.md G23). A read-only share is
    /// only useful if it shows the list; the token authorises this read on its
    /// own, so the rows appear whether or not the viewer is signed in.
    @ViewBuilder
    private func sharedRows(viewModel: ResolveShareViewModel) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider()
            if viewModel.isLoadingRows {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Loading rows")
            } else if let rowsError = viewModel.rowsError {
                // Scoped to the rows section: the title and role above stay
                // on screen, because they resolved fine.
                VStack(alignment: .leading, spacing: 4) {
                    Label("Couldn't load this list's rows", systemImage: "exclamationmark.triangle")
                        .font(.ilMono(11))
                        .foregroundStyle(.secondary)
                    Text(rowsError.localizedDescription)
                        .font(.ilMono(10))
                        .foregroundStyle(.secondary)
                    Button("Try Again") {
                        Task { await viewModel.loadRows() }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            } else if viewModel.rows.isEmpty {
                if viewModel.hasLoadedRowsOnce {
                    Text("This list has no rows yet.")
                        .font(.ilMono(11))
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("\(viewModel.rows.count) row\(viewModel.rows.count == 1 ? "" : "s")")
                    .font(.ilMono(10))
                    .foregroundStyle(.secondary)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(viewModel.rows) { row in
                            sharedRowCard(row: row, columns: viewModel.columns)
                        }
                    }
                }
                .frame(maxHeight: 220)
            }
        }
    }

    private func sharedRowCard(row: ListRow, columns: [String]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(columns, id: \.self) { column in
                if let value = row.fields[column] {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(column)
                            .font(.ilMono(10))
                            .foregroundStyle(.secondary)
                        Text(value.displayText)
                            .font(.ilMono(11))
                            .lineLimit(2)
                    }
                }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.06))
        .accessibilityElement(children: .combine)
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
