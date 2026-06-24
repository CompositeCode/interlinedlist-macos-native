// DocumentEditorView
//
// Side-by-side Markdown editor + preview for the M4 Documents feature
// (PLAN.md §6 M4, §5 Native macOS Experience). Pure SwiftUI:
//   - Left: vanilla `TextEditor` bound to `viewModel.body`.
//   - Right: `Textual.StructuredText(markdown:)` (Decision 0004).
//
// A horizontal Markdown toolbar above the editor inserts boilerplate at
// the end of the buffer (Bold / Italic / Code / Link / H1-H3 / List /
// Image). The image button forwards to the view model's `uploadImage`
// path so the same code path drives drag-drop and the toolbar.
//
// Drag-and-drop is handled via SwiftUI's `.dropDestination(for: Data.self)`
// so no AppKit involvement is required (PLAN.md §5; Decision 0004
// SwiftUI-only constraint).

import SwiftUI
import InterlinedDomain
import Textual

struct DocumentEditorView: View {

    let viewModel: DocumentEditorViewModel
    let onOpenLocalCopy: (Document.ID) -> Void

    var body: some View {
        VStack(spacing: 0) {
            if let pending = viewModel.conflict {
                ConflictBannerView(
                    pending: pending,
                    onOpenLocalCopy: onOpenLocalCopy,
                    onDismiss: { viewModel.dismissConflict() }
                )
            }

            titleField
                .padding(.horizontal, 12)
                .padding(.top, 8)

            markdownToolbar
                .padding(.horizontal, 12)
                .padding(.vertical, 6)

            HSplitView {
                editorPane
                    .frame(minWidth: 240)
                previewPane
                    .frame(minWidth: 240)
            }
        }
    }

    // MARK: - Title field

    private var titleField: some View {
        TextField(
            "Untitled document",
            text: Binding(
                get: { viewModel.title },
                set: { viewModel.title = $0 }
            )
        )
        .textFieldStyle(.plain)
        .font(.title2.weight(.semibold))
    }

    // MARK: - Toolbar

    private var markdownToolbar: some View {
        HStack(spacing: 4) {
            toolbarButton(label: "B", help: "Bold", systemName: "bold") {
                insert("**bold**")
            }
            toolbarButton(label: "I", help: "Italic", systemName: "italic") {
                insert("_italic_")
            }
            toolbarButton(label: "<>", help: "Code", systemName: "chevron.left.forwardslash.chevron.right") {
                insert("`code`")
            }
            Divider().frame(height: 16)
            toolbarButton(label: "H1", help: "Heading 1", systemName: "textformat.size.larger") {
                insertOnNewLine("# Heading 1")
            }
            toolbarButton(label: "H2", help: "Heading 2", systemName: "textformat.size") {
                insertOnNewLine("## Heading 2")
            }
            toolbarButton(label: "H3", help: "Heading 3", systemName: "textformat.size.smaller") {
                insertOnNewLine("### Heading 3")
            }
            Divider().frame(height: 16)
            toolbarButton(label: "Link", help: "Link", systemName: "link") {
                insert("[link](https://)")
            }
            toolbarButton(label: "List", help: "Bulleted list", systemName: "list.bullet") {
                insertOnNewLine("- item")
            }
            toolbarButton(label: "Img", help: "Image", systemName: "photo") {
                showImagePicker = true
            }
            Spacer()
            if viewModel.isSaving {
                ProgressView()
                    .controlSize(.small)
            } else if viewModel.hasUnsavedChanges {
                Text("Unsaved")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Saved")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .fileImporter(
            isPresented: $showImagePicker,
            allowedContentTypes: [.image],
            allowsMultipleSelection: false,
            onCompletion: handleImagePick
        )
    }

    @ViewBuilder
    private func toolbarButton(label: String, help: String, systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
        }
        .buttonStyle(.borderless)
        .help(help)
        .accessibilityLabel(label)
    }

    // MARK: - Editor pane

    private var editorPane: some View {
        TextEditor(
            text: Binding(
                get: { viewModel.body },
                set: { viewModel.body = $0 }
            )
        )
        .font(.system(.body, design: .monospaced))
        .padding(8)
        .background(Color(white: 0.98))
        .dropDestination(for: Data.self) { items, _ in
            guard let data = items.first else { return false }
            Task { await viewModel.uploadImage(data, suggestedName: nil) }
            return true
        }
    }

    // MARK: - Preview pane

    private var previewPane: some View {
        ScrollView {
            // Textual exposes `StructuredText(markdown:)` as the
            // block-level Markdown view (per the library's README +
            // public API check — see Decision 0004). The matching
            // inline-only entry point is `InlineText`, which is
            // intentionally not used here because the preview is a
            // full document.
            StructuredText(markdown: viewModel.body)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
        }
    }

    // MARK: - State held by the view itself

    @State private var showImagePicker: Bool = false

    // MARK: - Helpers

    private func insert(_ snippet: String) {
        viewModel.body.append(snippet)
    }

    private func insertOnNewLine(_ snippet: String) {
        if viewModel.body.isEmpty || viewModel.body.hasSuffix("\n") {
            viewModel.body.append(snippet)
        } else {
            viewModel.body.append("\n" + snippet)
        }
    }

    private func handleImagePick(_ result: Result<[URL], Error>) {
        switch result {
        case .failure:
            // The file picker already reports its own errors to the
            // user; nothing to do here.
            return
        case .success(let urls):
            guard let url = urls.first else { return }
            Task {
                let didStart = url.startAccessingSecurityScopedResource()
                defer { if didStart { url.stopAccessingSecurityScopedResource() } }
                guard let data = try? Data(contentsOf: url) else { return }
                await viewModel.uploadImage(data, suggestedName: url.lastPathComponent)
            }
        }
    }
}
