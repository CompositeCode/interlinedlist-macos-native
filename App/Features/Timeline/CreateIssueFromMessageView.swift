// CreateIssueFromMessageView
//
// Sheet for the "Create GitHub issue from message" overflow action
// (work-consolidation.md G4, App UI slice 2). Presents a repo picker + a
// pre-filled title/body drawn from the message, creates the issue, and shows a
// confirmation with a link to it. When the account has no linked GitHub
// identity it shows a "Link GitHub" CTA reusing the native OAuth flow.
//
// SwiftUI-only (no AppKit / NSViewRepresentable).

import SwiftUI
import InterlinedDomain

struct CreateIssueFromMessageView: View {

    let message: Message
    let environment: AppEnvironment

    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: CreateIssueFromMessageViewModel?
    @State private var linker: LinkedAccountsViewModel?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            Group {
                if let viewModel {
                    content(viewModel: viewModel)
                } else {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .frame(minWidth: 520, minHeight: 480)
        .task {
            if viewModel == nil {
                let model = CreateIssueFromMessageViewModel(
                    github: environment.github,
                    message: message,
                    webBaseURL: environment.shareBaseURL
                )
                viewModel = model
                await model.loadRepos()
            }
        }
    }

    private var header: some View {
        HStack {
            Image(systemName: "ladybug")
                .foregroundStyle(.secondary)
            Text("Create GitHub Issue").font(.headline)
            Spacer()
            Button("Cancel") { dismiss() }
        }
        .padding()
    }

    @ViewBuilder
    private func content(viewModel: CreateIssueFromMessageViewModel) -> some View {
        switch viewModel.linkState {
        case .notLinked:
            linkCTA(viewModel: viewModel)
        case .unknown, .linked:
            if let created = viewModel.createdIssue {
                successState(issue: created)
            } else {
                form(viewModel: viewModel)
            }
        }
    }

    // MARK: - Form

    @ViewBuilder
    private func form(viewModel: CreateIssueFromMessageViewModel) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if viewModel.isLoadingRepos {
                HStack { ProgressView().controlSize(.small); Text("Loading repositories…").foregroundStyle(.secondary) }
            } else if viewModel.repos.isEmpty {
                Text("No repositories were found for your linked GitHub account.")
                    .foregroundStyle(.secondary)
            } else {
                Picker("Repository", selection: Binding(
                    get: { viewModel.selectedRepo ?? viewModel.repos.first?.fullName ?? "" },
                    set: { viewModel.selectedRepo = $0 }
                )) {
                    ForEach(viewModel.repos) { repo in
                        Text(repo.fullName).tag(repo.fullName)
                    }
                }
            }

            TextField("Title", text: Binding(get: { viewModel.title }, set: { viewModel.title = $0 }))
                .textFieldStyle(.roundedBorder)

            Text("Description").font(.caption).foregroundStyle(.secondary)
            TextEditor(text: Binding(get: { viewModel.body }, set: { viewModel.body = $0 }))
                .frame(minHeight: 180)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))

            if let error = viewModel.error {
                Label(error.localizedDescription, systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button {
                    Task { await viewModel.create() }
                } label: {
                    if viewModel.isCreating { ProgressView().controlSize(.small) } else { Text("Create Issue") }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!viewModel.canCreate)
            }
        }
        .padding()
    }

    // MARK: - Success

    private func successState(issue: GitHubIssue) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 42))
                .foregroundStyle(.green)
            Text("Issue #\(issue.number) created")
                .font(.title3.weight(.semibold))
            Text(issue.title)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            HStack {
                if let url = issue.url {
                    Link(destination: url) { Label("Open on GitHub", systemImage: "arrow.up.forward.square") }
                }
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Link CTA

    private func linkCTA(viewModel: CreateIssueFromMessageViewModel) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "link.badge.plus")
                .font(.system(size: 42))
                .foregroundStyle(.secondary)
            Text("Link your GitHub account")
                .font(.title3.weight(.semibold))
            Text("Connect GitHub to create an issue from this post. You’ll return to InterlinedList when you’re done.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
            Button {
                Task { await linkGitHub(viewModel: viewModel) }
            } label: {
                if linker?.isLinking == true {
                    ProgressView().controlSize(.small)
                } else {
                    Label("Link GitHub", systemImage: "arrow.up.forward.app")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(linker?.isLinking == true)

            if let error = linker?.linkError {
                Text(error.localizedDescription)
                    .font(.caption).foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func linkGitHub(viewModel: CreateIssueFromMessageViewModel) async {
        let model = linker ?? LinkedAccountsViewModel(userService: environment.userService)
        linker = model
        await model.linkNatively(provider: .github)
        if model.nativeLinkSuccess {
            await viewModel.reloadAfterLink()
        }
    }
}
