// SearchRootView
//
// Global search surface (the-gaps.md G5). A single search field over the
// current user's messages, lists, and documents, with the hits grouped
// under three sections. The view is a thin shell over `SearchViewModel`:
// it binds the field, dispatches submit / clear, and renders whichever
// state the view model is in.
//
// Row rendering reuses the existing App-layer row components where they
// exist — `MessageRowView` for message hits and `ListRowSummaryView` for
// list hits — so search results look identical to their home surfaces. A
// small inline `DocumentSearchRow` covers documents (the Documents
// feature's own row is file-private).
//
// Deep-linking: tapping a message hit routes the sidebar to Timeline and
// asks it to open that message (the same `.notificationDeepLink` channel
// the system-banner router uses); tapping a list hit routes to Lists.
// Documents open the editor is deferred — tapping a document hit routes
// to the Documents section so the user lands on the right surface.
//
// Per decision 0003, this view consumes only `InterlinedDomain`.

import SwiftUI
import InterlinedDomain

struct SearchRootView: View {

    @Environment(\.appEnvironment) private var environment

    @State private var viewModel: SearchViewModel?

    /// Focus the field on appear and when the ⌘F menu command fires so the
    /// user can start typing immediately.
    @FocusState private var searchFieldFocused: Bool

    var body: some View {
        NavigationStack {
            Group {
                if let viewModel {
                    searchBody(viewModel: viewModel)
                } else {
                    unconfiguredState
                }
            }
            .navigationTitle("Search")
        }
        .task {
            if viewModel == nil, let environment {
                viewModel = SearchViewModel(service: environment.search)
            }
            searchFieldFocused = true
        }
        // ⌘F focuses the field. `SearchMenuCommands` posts this; the
        // sidebar has already switched to `.search` by the time it fires.
        .onReceive(NotificationCenter.default.publisher(for: .searchFocus)) { _ in
            searchFieldFocused = true
        }
    }

    // MARK: - Body sections

    @ViewBuilder
    private func searchBody(viewModel: SearchViewModel) -> some View {
        VStack(spacing: 0) {
            searchField(viewModel: viewModel)
            Divider()
            content(viewModel: viewModel)
        }
    }

    @ViewBuilder
    private func searchField(viewModel: SearchViewModel) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField(
                "Search messages, lists, and documents",
                text: Binding(
                    get: { viewModel.query },
                    set: { viewModel.query = $0 }
                )
            )
            .textFieldStyle(.roundedBorder)
            .focused($searchFieldFocused)
            .onSubmit {
                Task { await viewModel.searchNow() }
            }
            .accessibilityLabel("Search query")

            if viewModel.isSearching {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Searching")
            } else if !viewModel.query.isEmpty {
                Button {
                    viewModel.clear()
                    searchFieldFocused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private func content(viewModel: SearchViewModel) -> some View {
        if let error = viewModel.error {
            errorState(error: error, viewModel: viewModel)
        } else if !viewModel.hasSearched {
            promptState
        } else if viewModel.results.isEmpty {
            emptyState(query: viewModel.query)
        } else {
            resultsList(viewModel: viewModel)
        }
    }

    @ViewBuilder
    private func resultsList(viewModel: SearchViewModel) -> some View {
        let results = viewModel.results
        List {
            if !results.messages.isEmpty {
                Section("Messages") {
                    ForEach(results.messages) { message in
                        Button {
                            openMessage(id: message.id)
                        } label: {
                            MessageRowView(message: message)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Opens in the timeline")
                    }
                }
            }
            if !results.lists.isEmpty {
                Section("Lists") {
                    ForEach(results.lists) { summary in
                        Button {
                            openLists()
                        } label: {
                            ListRowSummaryView(summary: summary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Opens in the Lists section")
                    }
                }
            }
            if !results.documents.isEmpty {
                Section("Documents") {
                    ForEach(results.documents) { document in
                        Button {
                            openDocuments()
                        } label: {
                            DocumentSearchRow(document: document)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Opens in the Documents section")
                    }
                }
            }
        }
        .listStyle(.inset)
    }

    // MARK: - Deep-link routing

    /// Route the sidebar to Timeline and open the tapped message. Reuses
    /// the `.notificationDeepLink` channel `MainWindowView` already
    /// observes for system-banner taps, so no new routing wiring is
    /// needed in the main window.
    private func openMessage(id: String) {
        NotificationCenter.default.post(
            name: .notificationDeepLink,
            object: NotificationTarget.message(id: id)
        )
    }

    private func openLists() {
        NotificationCenter.default.post(
            name: .notificationDeepLink,
            object: NotificationTarget.list(id: "")
        )
    }

    /// No `.documents` case exists on the deep-link router, so route via
    /// the dedicated documents-show channel the menu command uses.
    private func openDocuments() {
        NotificationCenter.default.post(name: .searchShowDocuments, object: nil)
    }

    // MARK: - States

    private var promptState: some View {
        VStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.ilDisplay(36))
                .foregroundStyle(Color.accentColor)
            Text("Search InterlinedList")
                .font(.ilSubtitle())
            Text("Find messages, lists, and documents across your account.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func emptyState(query: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "tray")
                .font(.ilDisplay(36))
                .foregroundStyle(.secondary)
            Text("No results")
                .font(.ilSubtitle())
            Text("Nothing matched \u{201C}\(query.trimmingCharacters(in: .whitespacesAndNewlines))\u{201D}.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func errorState(error: Error, viewModel: SearchViewModel) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.ilDisplay(36))
                .foregroundStyle(Color.accentColor)
            Text("Search failed")
                .font(.ilSubtitle())
            Text(error.localizedDescription)
                .font(.ilSubtitle())
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("Try again") {
                Task { await viewModel.searchNow() }
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var unconfiguredState: some View {
        VStack(spacing: 8) {
            Image(systemName: "wrench.adjustable")
                .font(.ilDisplay(36))
                .foregroundStyle(.secondary)
            Text("Search unavailable")
                .font(.ilSubtitle())
            Text("AppEnvironment is not injected into the view tree.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - DocumentSearchRow

/// Compact document hit row — title, an excerpt of the Markdown body, and
/// a relative "updated" stamp. Kept local to the Search feature because
/// the Documents feature's own row component is file-private.
private struct DocumentSearchRow: View {
    let document: Document

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "doc.text")
                    .foregroundStyle(Color.accentColor)
                    .accessibilityHidden(true)
                Text(document.title.isEmpty ? "Untitled document" : document.title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer(minLength: 8)
            }
            if !excerpt.isEmpty {
                Text(excerpt)
                    .font(.ilSubtitle())
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Label(
                Self.relativeFormatter.localizedString(for: document.updatedAt, relativeTo: .now),
                systemImage: "clock"
            )
            .font(.ilMono(10))
            .foregroundStyle(.secondary)
            .accessibilityLabel("Updated \(Self.fullFormatter.string(from: document.updatedAt))")
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
    }

    /// First non-empty line of the Markdown body, trimmed.
    private var excerpt: String {
        document.body.markdown
            .split(separator: "\n", omittingEmptySubsequences: true)
            .first
            .map { String($0).trimmingCharacters(in: .whitespaces) } ?? ""
    }

    private var accessibilitySummary: String {
        var parts: [String] = [document.title.isEmpty ? "Untitled document" : document.title]
        if !excerpt.isEmpty { parts.append(excerpt) }
        parts.append("Updated \(Self.fullFormatter.string(from: document.updatedAt))")
        return parts.joined(separator: ". ")
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()

    private static let fullFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}
