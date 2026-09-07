// CreateFromSheet
//
// The "Create from…" form (work-consolidation.md G16). Mirrors the web app's
// modal: pick what to create, name it, choose visibility, and — for a list —
// edit the columns before creating.
//
// Per Decision 0003 this view consumes only `InterlinedDomain`.

import SwiftUI
import InterlinedDomain

struct CreateFromSheet: View {

    let source: MaterializeSourceRef
    let environment: AppEnvironment
    /// Pre-selects the target when the user picked one from the ＋ Create menu.
    var initialOutput: MaterializeOutput = .list
    /// Handle of the source's author, used only for the default title.
    var authorHandle: String?
    /// Called with the created ids so the caller can navigate to them.
    var onCreated: ((MaterializeOutcome) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: CreateFromViewModel?

    var body: some View {
        Group {
            if let viewModel {
                form(viewModel: viewModel)
            } else {
                ProgressView()
                    .accessibilityLabel("Preparing")
                    .padding()
            }
        }
        .frame(minWidth: 560, minHeight: 480)
        .task {
            if viewModel == nil {
                viewModel = CreateFromViewModel(
                    source: source,
                    materialize: environment.materializeService,
                    output: initialOutput,
                    authorHandle: authorHandle
                )
            }
        }
    }

    // MARK: - Form

    private func form(viewModel: CreateFromViewModel) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Create from…")
                .font(.ilTitle())

            Picker("Create", selection: Binding(
                get: { viewModel.output },
                set: { viewModel.output = $0 }
            )) {
                ForEach(MaterializeOutput.allCases) { output in
                    Text(output.label).tag(output)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("What to create")

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if viewModel.showsListSection {
                        listSection(viewModel: viewModel)
                    }
                    if viewModel.showsDocumentSection {
                        documentSection(viewModel: viewModel)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let message = viewModel.errorMessage {
                errorBanner(message)
            }

            Divider()
            footer(viewModel: viewModel)
        }
        .padding(18)
    }

    // MARK: - List

    @ViewBuilder
    private func listSection(viewModel: CreateFromViewModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("List")

            TextField("List title", text: Binding(
                get: { viewModel.listTitle }, set: { viewModel.listTitle = $0 }
            ))
            .textFieldStyle(.roundedBorder)
            .accessibilityLabel("List title")

            TextField("Description (optional)", text: Binding(
                get: { viewModel.listDescription }, set: { viewModel.listDescription = $0 }
            ))
            .textFieldStyle(.roundedBorder)
            .accessibilityLabel("List description")

            Toggle("Make list public", isOn: Binding(
                get: { viewModel.listIsPublic }, set: { viewModel.listIsPublic = $0 }
            ))
            .toggleStyle(.checkbox)

            Toggle("Include source data as rows", isOn: Binding(
                get: { viewModel.includeSourceData }, set: { viewModel.includeSourceData = $0 }
            ))
            .toggleStyle(.checkbox)
            .help("The selected content is added as rows in the new list.")

            columnsEditor(viewModel: viewModel)
        }
    }

    @ViewBuilder
    private func columnsEditor(viewModel: CreateFromViewModel) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                sectionTitle("Columns")
                Spacer()
                Button("Reset") { viewModel.restoreDefaultColumns() }
                    .controlSize(.small)
                Button {
                    viewModel.addColumn()
                } label: {
                    Label("Add column", systemImage: "plus")
                }
                .controlSize(.small)
            }

            if viewModel.columns.isEmpty {
                Text("A list needs at least one column.")
                    .font(.ilMono(10))
                    .foregroundStyle(Color.accentColor)
            }

            ForEach(viewModel.columns) { column in
                HStack(spacing: 8) {
                    TextField("Name", text: Binding(
                        get: { column.name },
                        set: { viewModel.renameColumn(id: column.id, to: $0) }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Column name")

                    Picker("", selection: Binding(
                        get: { column.type },
                        set: { viewModel.setColumnType(id: column.id, to: $0) }
                    )) {
                        ForEach(MaterializeColumnType.allCases) { type in
                            Text(type.label).tag(type)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 130)
                    .accessibilityLabel("Column type for \(column.name)")

                    Button(role: .destructive) {
                        viewModel.removeColumn(id: column.id)
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Remove column \(column.name)")
                }
            }
        }
    }

    // MARK: - Document

    @ViewBuilder
    private func documentSection(viewModel: CreateFromViewModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Document")

            TextField("Document title", text: Binding(
                get: { viewModel.documentTitle }, set: { viewModel.documentTitle = $0 }
            ))
            .textFieldStyle(.roundedBorder)
            .accessibilityLabel("Document title")

            TextField("Folder path (optional)", text: Binding(
                get: { viewModel.documentFolderPath }, set: { viewModel.documentFolderPath = $0 }
            ))
            .textFieldStyle(.roundedBorder)
            .accessibilityLabel("Document folder path")

            Toggle("Make document public", isOn: Binding(
                get: { viewModel.documentIsPublic }, set: { viewModel.documentIsPublic = $0 }
            ))
            .toggleStyle(.checkbox)

            HStack(spacing: 12) {
                Picker("List style", selection: Binding(
                    get: { viewModel.bulletStyle }, set: { viewModel.bulletStyle = $0 }
                )) {
                    ForEach(MaterializeBulletStyle.allCases) { style in
                        Text(style.label).tag(style)
                    }
                }
                .frame(maxWidth: 200)

                Picker("Row data", selection: Binding(
                    get: { viewModel.rowStyle }, set: { viewModel.rowStyle = $0 }
                )) {
                    ForEach(MaterializeRowStyle.allCases) { style in
                        Text(style.label).tag(style)
                    }
                }
                .frame(maxWidth: 200)
            }
        }
    }

    // MARK: - Chrome

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.ilMono(10))
            .foregroundStyle(.secondary)
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color.accentColor)
            Text(message)
                .font(.ilSubtitle())
            Spacer()
        }
        .padding(8)
        .background(ILColor.primary.opacity(0.1), in: RoundedRectangle(cornerRadius: ILMetric.radiusSm))
    }

    private func footer(viewModel: CreateFromViewModel) -> some View {
        HStack {
            Button("Cancel", role: .cancel) { dismiss() }
                .keyboardShortcut(.cancelAction)

            Spacer()

            if viewModel.isCreating {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Creating")
                    .padding(.trailing, 8)
            }

            Button("Create") {
                Task {
                    await viewModel.create()
                    if let outcome = viewModel.outcome, !outcome.isEmpty {
                        onCreated?(outcome)
                        dismiss()
                    }
                }
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(!viewModel.canCreate)
        }
    }
}
