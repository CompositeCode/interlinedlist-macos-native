// PublicUserDocumentsView
//
// The documents column on a public profile (work-consolidation.md G24). The
// web profile has a documents tab; macOS had none.
//
// A self-contained section, not a screen: it owns its view model, its loading
// state and its own empty/error copy, so the host profile view adds it with a
// single line and never learns about `DocumentsServicing`.
//
// The rows are intentionally not openable. `GET /api/users/{username}/
// documents` lists a user's *public* documents but never ships their Markdown,
// and the editor is a first-party surface for documents you own — so this
// column presents titles and dates, and stops there.
//
// Pure SwiftUI; no AppKit. Decision 0003: consumes only `InterlinedDomain`.

import SwiftUI
import InterlinedDomain

struct PublicUserDocumentsView: View {

    /// The handle to show documents for. A change re-triggers the load.
    let username: String

    @Environment(\.appEnvironment) private var environment
    @State private var viewModel: PublicUserDocumentsViewModel?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            if let viewModel {
                content(viewModel: viewModel)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task(id: username) {
            // `@Environment` isn't readable during `init`, so the view model is
            // built here. `task(id:)` also re-runs when the browsed handle
            // changes, which is exactly when a reload is wanted.
            guard let environment else { return }
            let model = viewModel ?? PublicUserDocumentsViewModel(
                documents: environment.documentsService
            )
            viewModel = model
            await model.load(username: username)
        }
    }

    // MARK: - Sections

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "doc.text")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("Public documents")
                .font(.ilSubtitle())
            if viewModel?.isLoading == true {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Loading public documents")
            }
        }
    }

    @ViewBuilder
    private func content(viewModel: PublicUserDocumentsViewModel) -> some View {
        if let error = viewModel.error {
            errorState(error: error, viewModel: viewModel)
        } else if !viewModel.hasLoaded {
            // First load in flight — the header spinner is the only chrome
            // needed; a second placeholder would just flicker.
            EmptyView()
        } else if viewModel.isEmpty {
            Text("@\(username) hasn't published any documents.")
                .font(.ilBody())
                .foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(viewModel.documentsLoaded) { document in
                    PublicDocumentRow(document: document)
                    if document.id != viewModel.documentsLoaded.last?.id {
                        Divider()
                    }
                }
            }
        }
    }

    private func errorState(
        error: Error,
        viewModel: PublicUserDocumentsViewModel
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(error.localizedDescription)
                .font(.ilMono(10))
                .foregroundStyle(.secondary)
            Button("Try again") {
                Task { await viewModel.refresh() }
            }
            .buttonStyle(.bordered)
            .controlSize(.mini)
        }
    }
}

// MARK: - PublicDocumentRow

private struct PublicDocumentRow: View {

    let document: Document

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(document.title.isEmpty ? "Untitled" : document.title)
                .font(.ilBody())
                .lineLimit(1)
            Text(document.updatedAt.formatted(date: .abbreviated, time: .omitted))
                .font(.ilMono(10))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }
}
