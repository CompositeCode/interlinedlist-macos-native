// DocumentTemplatePickerView
//
// Sheet for "New Document from Template…" (feature-gaps.md §1.4). Lists the
// bundled `DocumentTemplate.builtIn` catalog (name + summary); on selection it
// asks `DocumentsListViewModel.createDocument(from:)` to seed a new document
// with the template's starter Markdown and route it through the normal create
// path, then reports the created document to the caller so the editor can bind
// to it.
//
// This is a client-side feature — there is no templates endpoint, so the view
// reads the static catalog directly (no service, no AppEnvironment wiring). If
// the API later exposes templates, swap the catalog source; this view's shape
// does not change.
//
// Pure SwiftUI; no AppKit involvement. Per Decision 0003 the view imports only
// InterlinedDomain.

import SwiftUI
import InterlinedDomain

struct DocumentTemplatePickerView: View {

    /// The list view model that owns the create path. Bindable so the sheet
    /// reacts to its `error` and any in-flight state.
    @Bindable var viewModel: DocumentsListViewModel

    /// Called with the created document on success so the caller (the root
    /// view) can bind the editor to it. Not called on failure.
    let onCreated: (Document) -> Void

    /// The catalog to present. Defaults to the bundled built-ins; injectable so
    /// previews and future server-backed catalogs can substitute a list.
    var templates: [DocumentTemplate] = DocumentTemplate.builtIn

    @Environment(\.dismiss) private var dismiss
    @State private var selectedTemplateID: DocumentTemplate.ID?
    @State private var isCreating = false

    private var selectedTemplate: DocumentTemplate? {
        guard let selectedTemplateID else { return nil }
        return templates.first { $0.id == selectedTemplateID }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New Document from Template")
                .font(.ilTitle(18))
                .padding(.top, 4)

            List(selection: $selectedTemplateID) {
                ForEach(templates) { template in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(template.name)
                            .font(.ilBody())
                            .fontWeight(.medium)
                        Text(template.summary)
                            .font(.ilMono(10))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    .padding(.vertical, 2)
                    .tag(template.id)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(template.name). \(template.summary)")
                }
            }
            .listStyle(.inset)
            .frame(minHeight: 200)

            if let error = viewModel.error {
                Text(error.localizedDescription)
                    .font(.ilMono(10))
                    .foregroundStyle(Color.accentColor)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Create") {
                    Task { await create() }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(selectedTemplate == nil || isCreating)
            }
        }
        .padding(20)
        .frame(minWidth: 420, minHeight: 340)
        .onAppear {
            // Preselect the first template (Blank) so the primary action is
            // always live when the sheet opens.
            if selectedTemplateID == nil {
                selectedTemplateID = templates.first?.id
            }
        }
    }

    private func create() async {
        guard let template = selectedTemplate else { return }
        isCreating = true
        defer { isCreating = false }
        if let created = await viewModel.createDocument(from: template) {
            onCreated(created)
            dismiss()
        }
        // On failure the view model's `error` is surfaced above and the sheet
        // stays open so the user can retry or cancel.
    }
}
