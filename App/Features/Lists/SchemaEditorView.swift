// SchemaEditorView
//
// The M3 schema editor (PLAN.md §6 M3, user's plan answer: per-field
// form builder, no DSL textarea). One row per `SchemaField`: name,
// type picker, nullable toggle, drag handle. Read-only when the
// caller's role isn't `.owner`.

import SwiftUI
import InterlinedDomain

struct SchemaEditorView: View {

    let listId: String
    let environment: AppEnvironment

    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: SchemaEditorViewModel?
    @State private var isLoading: Bool = true
    @State private var loadError: Error?
    @State private var fieldIDPendingDelete: UUID?

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
                    .padding()
                    .frame(minWidth: 480, minHeight: 360)
            } else if let viewModel {
                editorBody(viewModel: viewModel)
            } else if let loadError {
                errorState(loadError)
            } else {
                Text("Schema unavailable")
                    .foregroundStyle(.secondary)
                    .padding()
            }
        }
        .frame(minWidth: 540, minHeight: 460)
        .task {
            await loadSchema()
        }
    }

    @ViewBuilder
    private func editorBody(viewModel: SchemaEditorViewModel) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            header(viewModel: viewModel)
            Divider()
            List {
                ForEach(viewModel.fields) { field in
                    fieldRow(viewModel: viewModel, field: field)
                }
                .onMove { source, destination in
                    viewModel.moveFields(from: source, to: destination)
                }
                if viewModel.isEditable {
                    Button {
                        viewModel.addField()
                    } label: {
                        Label("Add field", systemImage: "plus")
                    }
                }
            }
            if let error = viewModel.error {
                Divider()
                Label(error.localizedDescription, systemImage: "exclamationmark.triangle")
                    .padding(8)
            }
            Divider()
            footer(viewModel: viewModel)
        }
        .confirmationDialog(
            "Remove this field?",
            isPresented: Binding(
                get: { fieldIDPendingDelete != nil },
                set: { if !$0 { fieldIDPendingDelete = nil } }
            ),
            presenting: fieldIDPendingDelete
        ) { id in
            Button("Remove", role: .destructive) {
                viewModel.removeField(id: id)
                fieldIDPendingDelete = nil
            }
            Button("Cancel", role: .cancel) {
                fieldIDPendingDelete = nil
            }
        } message: { _ in
            Text("Existing row values for this field will be discarded on save.")
        }
    }

    @ViewBuilder
    private func header(viewModel: SchemaEditorViewModel) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Schema")
                .font(.title3.weight(.semibold))
            if viewModel.isEditable {
                Text("Add, edit, and reorder the columns. Save to apply.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("You don't have permission to edit this schema.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
    }

    @ViewBuilder
    private func fieldRow(
        viewModel: SchemaEditorViewModel,
        field: SchemaEditorViewModel.EditableField
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                TextField("Field name", text: Binding(
                    get: { field.name },
                    set: { newValue in
                        if let index = viewModel.fields.firstIndex(where: { $0.id == field.id }) {
                            viewModel.fields[index].name = newValue
                        }
                    }
                ))
                .textFieldStyle(.roundedBorder)
                .disabled(!viewModel.isEditable)

                Picker("Type", selection: Binding(
                    get: { field.type },
                    set: { viewModel.setType($0, forFieldID: field.id) }
                )) {
                    ForEach(SchemaFieldType.allCases, id: \.self) { type in
                        Text(label(for: type)).tag(type)
                    }
                }
                .pickerStyle(.menu)
                .disabled(!viewModel.isEditable)

                Toggle("Nullable", isOn: Binding(
                    get: { field.nullable },
                    set: { newValue in
                        if let index = viewModel.fields.firstIndex(where: { $0.id == field.id }) {
                            viewModel.fields[index].nullable = newValue
                        }
                    }
                ))
                .toggleStyle(.checkbox)
                .disabled(!viewModel.isEditable)

                if viewModel.isEditable {
                    Button {
                        fieldIDPendingDelete = field.id
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove field")
                }
            }
            if let error = viewModel.validationError(for: field) {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    @ViewBuilder
    private func footer(viewModel: SchemaEditorViewModel) -> some View {
        HStack {
            Button("Cancel", role: .cancel) {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)
            Spacer()
            if viewModel.isSaving {
                ProgressView()
                    .controlSize(.small)
                    .padding(.trailing, 4)
            }
            Button("Save") {
                Task { await viewModel.save() }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!viewModel.isEditable || !viewModel.isValid || viewModel.isSaving)
            .keyboardShortcut(.defaultAction)
        }
        .padding(12)
    }

    @ViewBuilder
    private func errorState(_ error: Error) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 36))
                .foregroundStyle(Color.accentColor)
            Text("Couldn't load schema")
                .font(.headline)
            Text(error.localizedDescription)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("Close") { dismiss() }
                .buttonStyle(.borderedProminent)
        }
        .padding()
    }

    private func loadSchema() async {
        isLoading = true
        defer { isLoading = false }
        do {
            // Load schema + the caller's role together so the editor
            // knows whether to render read-only mode.
            async let schema = environment.lists.schema(of: listId)
            async let status = environment.lists.myWatcherStatus(of: listId)
            let loadedSchema = try await schema
            let watcher = try await status
            viewModel = SchemaEditorViewModel(
                lists: environment.lists,
                eventBus: environment.listsEventBus,
                listId: listId,
                role: watcher.role ?? .owner,
                initialSchema: loadedSchema
            )
        } catch {
            loadError = error
        }
    }

    private func label(for type: SchemaFieldType) -> String {
        switch type {
        case .text: return "Text"
        case .number: return "Number"
        case .boolean: return "Boolean"
        case .date: return "Date"
        case .url: return "URL"
        case .email: return "Email"
        }
    }
}
