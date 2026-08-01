// DocumentTemplatePickerView
//
// Sheet for "New Document from Template…" (feature-gaps.md §1.4, the-gaps.md
// G12). Presents two sections:
//
//   • "Built-in" — the bundled `DocumentTemplate.builtIn` catalog (Blank /
//     Meeting Notes / Daily Log / PRD). Selecting one seeds a fresh document
//     from its starter Markdown through `DocumentsListViewModel.createDocument`.
//     This is a purely client-side path; unchanged from the original picker.
//
//   • "Your templates" — the user's own **server-side** saved templates
//     (`DocumentTemplateRef`), fetched by `ServerTemplatesViewModel`. Selecting
//     one calls `createFromTemplate` and then reloads the documents list so the
//     new document appears, opening it in the editor.
//
// The server section is loaded lazily and its failures are non-fatal: if the
// fetch throws, the built-in section still renders and the error is surfaced in
// a subtle inline row. An empty result shows a "No saved templates yet" row with
// a "Seed defaults" affordance.
//
// Pure SwiftUI; no AppKit involvement. Per Decision 0003 the view imports only
// InterlinedDomain.

import SwiftUI
import InterlinedDomain

struct DocumentTemplatePickerView: View {

    /// The list view model that owns the create path. Bindable so the sheet
    /// reacts to its `error` and any in-flight state.
    @Bindable var viewModel: DocumentsListViewModel

    /// Drives the "Your templates" section — the server-side catalog. Bindable
    /// so the sheet reacts to its load / create state.
    @Bindable var serverTemplates: ServerTemplatesViewModel

    /// Called with the created document on success so the caller (the root
    /// view) can bind the editor to it. Not called on failure.
    let onCreated: (Document) -> Void

    /// The built-in catalog to present. Defaults to the bundled built-ins;
    /// injectable so previews can substitute a list.
    var builtInTemplates: [DocumentTemplate] = DocumentTemplate.builtIn

    @Environment(\.dismiss) private var dismiss
    @State private var selection: TemplateSelection?
    @State private var isCreating = false

    /// A unified selection across both sections so a single `List` selection
    /// binding drives the primary action regardless of which kind is picked.
    private enum TemplateSelection: Hashable {
        case builtIn(DocumentTemplate.ID)
        case server(DocumentTemplateRef.ID)
    }

    private var selectedBuiltIn: DocumentTemplate? {
        guard case let .builtIn(id) = selection else { return nil }
        return builtInTemplates.first { $0.id == id }
    }

    private var selectedServer: DocumentTemplateRef? {
        guard case let .server(id) = selection else { return nil }
        return serverTemplates.templates.first { $0.id == id }
    }

    private var canCreate: Bool {
        (selectedBuiltIn != nil || selectedServer != nil) && !isCreating
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New Document from Template")
                .font(.ilTitle(18))
                .padding(.top, 4)

            List(selection: $selection) {
                builtInSection
                serverSection
            }
            .listStyle(.inset)
            .frame(minHeight: 220)

            if let error = viewModel.error {
                Text(error.localizedDescription)
                    .font(.ilMono(10))
                    .foregroundStyle(Color.accentColor)
            }

            if let createError = serverTemplates.createError {
                Text(createError.localizedDescription)
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
                .disabled(!canCreate)
            }
        }
        .padding(20)
        .frame(minWidth: 440, minHeight: 380)
        .onAppear {
            // Preselect the first built-in (Blank) so the primary action is
            // always live when the sheet opens.
            if selection == nil, let first = builtInTemplates.first {
                selection = .builtIn(first.id)
            }
        }
        .task {
            // Load the server section lazily; failure is non-fatal so the
            // built-in section above is unaffected.
            await serverTemplates.loadTemplates()
        }
    }

    // MARK: - Sections

    private var builtInSection: some View {
        Section("Built-in") {
            ForEach(builtInTemplates) { template in
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
                .tag(TemplateSelection.builtIn(template.id))
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(template.name). \(template.summary)")
            }
        }
    }

    @ViewBuilder
    private var serverSection: some View {
        Section("Your templates") {
            if serverTemplates.isLoading && serverTemplates.templates.isEmpty {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Loading your templates…")
                        .font(.ilMono(10))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            } else if let loadError = serverTemplates.loadError {
                Text("Couldn't load your templates: \(loadError.localizedDescription)")
                    .font(.ilMono(10))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 2)
            } else if serverTemplates.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("No saved templates yet")
                        .font(.ilMono(10))
                        .foregroundStyle(.secondary)
                    Button("Seed defaults") {
                        Task { await serverTemplates.seedDefaults() }
                    }
                    .buttonStyle(.link)
                    .font(.ilMono(10))
                    .disabled(serverTemplates.isLoading)
                }
                .padding(.vertical, 2)
            } else {
                ForEach(serverTemplates.templates) { template in
                    HStack(spacing: 6) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(template.title)
                                .font(.ilBody())
                                .fontWeight(.medium)
                            if let path = template.relativePath, !path.isEmpty {
                                Text(path)
                                    .font(.ilMono(10))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        if serverTemplates.pendingTemplateIDs.contains(template.id) {
                            Spacer()
                            ProgressView().controlSize(.small)
                        }
                    }
                    .padding(.vertical, 2)
                    .tag(TemplateSelection.server(template.id))
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(template.title). Your saved template.")
                }
            }
        }
    }

    // MARK: - Actions

    private func create() async {
        isCreating = true
        defer { isCreating = false }

        if let builtIn = selectedBuiltIn {
            if let created = await viewModel.createDocument(from: builtIn) {
                onCreated(created)
                dismiss()
            }
            // On failure the view model's `error` is surfaced above and the
            // sheet stays open so the user can retry or cancel.
        } else if let server = selectedServer {
            if let created = await serverTemplates.createFromTemplate(server) {
                onCreated(created)
                dismiss()
            }
            // On failure the server VM's `createError` is set; the sheet stays
            // open. (Surfaced below the list via the error row.)
        }
    }
}
