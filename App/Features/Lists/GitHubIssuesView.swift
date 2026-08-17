// GitHubIssuesView
//
// The issue browser sheet for a GitHub-backed list (work-consolidation.md G4).
// Lists a repo's issues (filterable by state), creates new issues, and posts
// comments — all through `GitHubIssuesViewModel`. When the account has no
// linked GitHub identity the sheet shows a "Link GitHub" call-to-action that
// reuses the existing native OAuth flow (`LinkedAccountsViewModel`), then
// reloads on success.
//
// SwiftUI-only (no AppKit / NSViewRepresentable).

import SwiftUI
import InterlinedDomain

struct GitHubIssuesView: View {

    let repo: String
    let environment: AppEnvironment

    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: GitHubIssuesViewModel?
    @State private var linker: LinkedAccountsViewModel?
    @State private var showsNewIssue = false
    @State private var selectedIssue: GitHubIssue?

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
        .frame(minWidth: 640, minHeight: 520)
        .task {
            if viewModel == nil {
                let model = GitHubIssuesViewModel(github: environment.github, repo: repo)
                viewModel = model
                await model.load()
            }
        }
        .sheet(isPresented: $showsNewIssue) {
            if let viewModel {
                newIssueSheet(viewModel: viewModel)
            }
        }
        .sheet(item: $selectedIssue) { issue in
            if let viewModel {
                GitHubIssueDetailView(initialIssue: issue, viewModel: viewModel)
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "ladybug")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text("Issues").font(.headline)
                Text(repo).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if let viewModel, viewModel.linkState == .linked {
                Picker("State", selection: filterBinding(viewModel: viewModel)) {
                    ForEach(GitHubIssueFilter.allCases) { state in
                        Text(state.rawValue.capitalized).tag(state)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 220)

                Button {
                    showsNewIssue = true
                } label: {
                    Label("New Issue", systemImage: "plus")
                }
            }
            Button("Done") { dismiss() }
        }
        .padding()
    }

    private func filterBinding(viewModel: GitHubIssuesViewModel) -> Binding<GitHubIssueFilter> {
        Binding(
            get: { viewModel.filter },
            set: { newValue in Task { await viewModel.setFilter(newValue) } }
        )
    }

    // MARK: - Content

    @ViewBuilder
    private func content(viewModel: GitHubIssuesViewModel) -> some View {
        switch viewModel.linkState {
        case .notLinked:
            linkCTA(viewModel: viewModel)
        case .unknown, .linked:
            issuesList(viewModel: viewModel)
        }
    }

    @ViewBuilder
    private func issuesList(viewModel: GitHubIssuesViewModel) -> some View {
        if viewModel.isLoading && viewModel.issues.isEmpty {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewModel.issues.isEmpty {
            ContentUnavailableView(
                "No \(viewModel.filter == .all ? "" : viewModel.filter.rawValue + " ")issues",
                systemImage: "checkmark.circle",
                description: Text("Create the first issue with the New Issue button.")
            )
        } else {
            List(viewModel.issues) { issue in
                Button {
                    selectedIssue = issue
                } label: {
                    GitHubIssueRow(issue: issue)
                }
                .buttonStyle(.plain)
            }
            .overlay(alignment: .bottom) {
                if let error = viewModel.error {
                    errorBar(error)
                }
            }
        }
    }

    // MARK: - Link CTA

    private func linkCTA(viewModel: GitHubIssuesViewModel) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "link.badge.plus")
                .font(.system(size: 42))
                .foregroundStyle(.secondary)
            Text("Link your GitHub account")
                .font(.title3.weight(.semibold))
            Text("Connect GitHub to browse and create issues for this list. You’ll return to InterlinedList when you’re done.")
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
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func linkGitHub(viewModel: GitHubIssuesViewModel) async {
        let model = linker ?? LinkedAccountsViewModel(userService: environment.userService)
        linker = model
        await model.linkNatively(provider: .github)
        if model.nativeLinkSuccess {
            await viewModel.reloadAfterLink()
        }
    }

    // MARK: - New issue

    private func newIssueSheet(viewModel: GitHubIssuesViewModel) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("New Issue").font(.headline)
            TextField("Title", text: Binding(get: { viewModel.newIssueTitle }, set: { viewModel.newIssueTitle = $0 }))
                .textFieldStyle(.roundedBorder)
            TextEditor(text: Binding(get: { viewModel.newIssueBody }, set: { viewModel.newIssueBody = $0 }))
                .frame(minHeight: 160)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
            HStack {
                Spacer()
                Button("Cancel") { showsNewIssue = false }
                Button {
                    Task {
                        await viewModel.createIssue()
                        if viewModel.error == nil { showsNewIssue = false }
                    }
                } label: {
                    if viewModel.isCreating { ProgressView().controlSize(.small) } else { Text("Create") }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!viewModel.canCreateIssue)
            }
        }
        .padding()
        .frame(minWidth: 460, minHeight: 300)
    }

    private func errorBar(_ error: Error) -> some View {
        Label(error.localizedDescription, systemImage: "exclamationmark.triangle")
            .font(.caption)
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.thinMaterial)
    }
}

// MARK: - GitHubIssueRow

private struct GitHubIssueRow: View {
    let issue: GitHubIssue

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: issue.state == .closed ? "checkmark.circle.fill" : "smallcircle.circle")
                .foregroundStyle(issue.state == .closed ? .purple : .green)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                Text(issue.title.isEmpty ? "#\(issue.number)" : issue.title)
                    .fontWeight(.medium)
                if !issue.labels.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(issue.labels) { label in
                            Text(label.name)
                                .font(.caption2)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Capsule().fill(.quaternary))
                        }
                    }
                }
                HStack(spacing: 8) {
                    Text("#\(issue.number)")
                    if let login = issue.author?.login { Text("· \(login)") }
                    if issue.commentCount > 0 {
                        Label("\(issue.commentCount)", systemImage: "text.bubble")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

// MARK: - GitHubIssueDetailView

private struct GitHubIssueDetailView: View {
    let initialIssue: GitHubIssue
    let viewModel: GitHubIssuesViewModel

    @Environment(\.dismiss) private var dismiss
    @State private var commentText: String = ""
    @State private var selectedLabels: Set<String> = []
    @State private var selectedAssignees: Set<String> = []

    /// The live copy from the view model (reflects in-place edits), falling
    /// back to the snapshot the sheet was presented with.
    private var issue: GitHubIssue {
        viewModel.issues.first { $0.number == initialIssue.number } ?? initialIssue
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            editingBar
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let body = issue.body, !body.isEmpty {
                        Text(body).textSelection(.enabled)
                    } else {
                        Text("No description provided.").foregroundStyle(.secondary)
                    }
                    if !issue.labels.isEmpty {
                        HStack(spacing: 4) {
                            ForEach(issue.labels) { label in
                                Text(label.name).font(.caption2)
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(Capsule().fill(.quaternary))
                            }
                        }
                    }
                    if !issue.assignees.isEmpty {
                        Text("Assignees: " + issue.assignees.map { "@\($0.login)" }.joined(separator: ", "))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            }
            Divider()
            commentBar
        }
        .frame(minWidth: 520, minHeight: 480)
        .task {
            selectedLabels = Set(issue.labels.map(\.name))
            selectedAssignees = Set(issue.assignees.map(\.login))
            await viewModel.loadEditingCatalog()
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(issue.title.isEmpty ? "#\(issue.number)" : issue.title).font(.headline)
                HStack(spacing: 6) {
                    Text(issue.state == .closed ? "Closed" : "Open")
                        .font(.caption).foregroundStyle(issue.state == .closed ? .purple : .green)
                    Text("#\(issue.number)").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let url = issue.url {
                Link(destination: url) { Label("Open on GitHub", systemImage: "arrow.up.forward.square") }
            }
            Button("Done") { dismiss() }
        }
        .padding()
    }

    private var editingBar: some View {
        HStack(spacing: 8) {
            Button {
                Task { await viewModel.toggleState(issue) }
            } label: {
                if issue.state == .closed {
                    Label("Reopen", systemImage: "arrow.counterclockwise.circle")
                } else {
                    Label("Close", systemImage: "checkmark.circle")
                }
            }
            .disabled(viewModel.isUpdating)

            Menu {
                if viewModel.labelCatalog.isEmpty {
                    Text(viewModel.isLoadingCatalog ? "Loading…" : "No labels")
                }
                ForEach(viewModel.labelCatalog) { label in
                    Button {
                        toggle(label.name, in: &selectedLabels) { newSet in
                            Task { await viewModel.setLabels(Array(newSet), on: issue) }
                        }
                    } label: {
                        Label(label.name, systemImage: selectedLabels.contains(label.name) ? "checkmark" : "circle")
                    }
                }
            } label: {
                Label("Labels", systemImage: "tag")
            }
            .disabled(viewModel.isUpdating)

            Menu {
                if viewModel.assignableUsers.isEmpty {
                    Text(viewModel.isLoadingCatalog ? "Loading…" : "No assignable users")
                }
                ForEach(viewModel.assignableUsers) { user in
                    Button {
                        toggle(user.login, in: &selectedAssignees) { newSet in
                            Task { await viewModel.setAssignees(Array(newSet), on: issue) }
                        }
                    } label: {
                        Label("@\(user.login)", systemImage: selectedAssignees.contains(user.login) ? "checkmark" : "circle")
                    }
                }
            } label: {
                Label("Assignees", systemImage: "person.crop.circle.badge.plus")
            }
            .disabled(viewModel.isUpdating)

            if viewModel.isUpdating { ProgressView().controlSize(.small) }
            Spacer()
        }
        .padding(.horizontal).padding(.vertical, 8)
    }

    private var commentBar: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Add a comment…", text: $commentText, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...4)
            Button {
                Task {
                    await viewModel.addComment(to: issue, body: commentText)
                    if viewModel.error == nil { commentText = "" }
                }
            } label: {
                if viewModel.isCommenting { ProgressView().controlSize(.small) } else { Text("Comment") }
            }
            .buttonStyle(.borderedProminent)
            .disabled(commentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isCommenting)
        }
        .padding()
    }

    /// Flips membership of `value` in `set` and hands the new set to `apply`.
    private func toggle(_ value: String, in set: inout Set<String>, apply: (Set<String>) -> Void) {
        if set.contains(value) { set.remove(value) } else { set.insert(value) }
        apply(set)
    }
}
