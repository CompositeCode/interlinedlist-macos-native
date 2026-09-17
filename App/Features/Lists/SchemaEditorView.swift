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
                .font(.ilTitle(20))
            if viewModel.isEditable {
                Text("Add, edit, and reorder the columns. Save to apply.")
                    .font(.ilMono(10))
                    .foregroundStyle(.secondary)
            } else {
                Text("You don't have permission to edit this schema.")
                    .font(.ilMono(10))
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
            if field.type == .select {
                selectOptionsEditor(viewModel: viewModel, field: field)
            }
            // The per-column metadata the server has always stored and no client
            // ever wrote (GitHub #50). Behind a disclosure so the common case —
            // naming a column and picking its type — stays a single line.
            fieldDetailEditor(viewModel: viewModel, field: field)
            if let error = viewModel.validationError(for: field) {
                Text(error)
                    .font(.ilMono(10))
                    .foregroundStyle(.red)
            }
        }
    }

    /// Help text, placeholder, visibility and the validation rules for one
    /// column (GitHub #50).
    ///
    /// The controls offered are **type-dependent**: length rules only for the
    /// text family, range rules only for `number`. Showing a "Min length" on a
    /// checkbox would be a control that cannot do anything, and sending the rule
    /// would put a constraint on the server that nothing enforces.
    @ViewBuilder
    private func fieldDetailEditor(
        viewModel: SchemaEditorViewModel,
        field: SchemaEditorViewModel.EditableField
    ) -> some View {
        DisclosureGroup("Details") {
            VStack(alignment: .leading, spacing: 6) {
                LabeledContent("Help text") {
                    TextField("Shown under the field", text: binding(viewModel, field, \.helpText))
                        .textFieldStyle(.roundedBorder)
                }
                LabeledContent("Placeholder") {
                    TextField("Shown when empty", text: binding(viewModel, field, \.placeholder))
                        .textFieldStyle(.roundedBorder)
                }

                if field.type.acceptsRangeRules {
                    HStack(spacing: 8) {
                        LabeledContent("Min") {
                            TextField("", text: binding(viewModel, field, \.minValue))
                                .textFieldStyle(.roundedBorder)
                        }
                        LabeledContent("Max") {
                            TextField("", text: binding(viewModel, field, \.maxValue))
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                }

                if field.type.acceptsLengthRules {
                    HStack(spacing: 8) {
                        LabeledContent("Min length") {
                            TextField("", text: binding(viewModel, field, \.minLength))
                                .textFieldStyle(.roundedBorder)
                        }
                        LabeledContent("Max length") {
                            TextField("", text: binding(viewModel, field, \.maxLength))
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                    LabeledContent("Pattern") {
                        TextField("Regular expression", text: binding(viewModel, field, \.pattern))
                            .textFieldStyle(.roundedBorder)
                            .font(.ilMono(11))
                    }
                    Text("Checked by InterlinedList when a row is saved. This app doesn’t test it locally — a different regex engine could disagree and reject a value the server would accept.")
                        .font(.ilMono(10))
                        .foregroundStyle(.secondary)
                }

                Toggle("Show this column", isOn: Binding(
                    get: { field.isVisible },
                    set: { newValue in
                        if let index = viewModel.fields.firstIndex(where: { $0.id == field.id }) {
                            viewModel.fields[index].isVisible = newValue
                        }
                    }
                ))
                .toggleStyle(.checkbox)
                Text("A hidden column keeps its data. This isn’t the same as removing it.")
                    .font(.ilMono(10))
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 4)
            .disabled(!viewModel.isEditable)
        }
        .font(.ilMono(11))
    }

    /// One binding shape for every string field on a row, so the
    /// find-the-index-then-mutate dance is written once rather than eleven
    /// times.
    private func binding(
        _ viewModel: SchemaEditorViewModel,
        _ field: SchemaEditorViewModel.EditableField,
        _ keyPath: WritableKeyPath<SchemaEditorViewModel.EditableField, String>
    ) -> Binding<String> {
        Binding(
            get: { field[keyPath: keyPath] },
            set: { newValue in
                if let index = viewModel.fields.firstIndex(where: { $0.id == field.id }) {
                    viewModel.fields[index][keyPath: keyPath] = newValue
                }
            }
        )
    }

    /// Inline, per-option editor shown only for `select` columns. Each option
    /// is an editable text field with a remove button; a trailing "Add option"
    /// button appends a blank option. All mutations route through the view
    /// model so the option array stays owned there.
    @ViewBuilder
    private func selectOptionsEditor(
        viewModel: SchemaEditorViewModel,
        field: SchemaEditorViewModel.EditableField
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Options")
                .font(.ilMono(9))
                .foregroundStyle(.secondary)
            ForEach(Array(field.options.enumerated()), id: \.offset) { index, option in
                HStack(spacing: 6) {
                    TextField("Option", text: Binding(
                        get: { option },
                        set: { viewModel.setOption($0, forFieldID: field.id, at: index) }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .disabled(!viewModel.isEditable)
                    if viewModel.isEditable {
                        Button {
                            viewModel.removeOption(fromFieldID: field.id, at: index)
                        } label: {
                            Image(systemName: "minus.circle")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Remove option")
                    }
                }
            }
            if viewModel.isEditable {
                Button {
                    viewModel.addOption(toFieldID: field.id)
                } label: {
                    Label("Add option", systemImage: "plus")
                        .font(.ilMono(10))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.leading, 8)
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
                    .accessibilityLabel("Saving schema")
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
                .font(.ilDisplay(36))
                .foregroundStyle(Color.accentColor)
            Text("Couldn't load schema")
                .font(.ilSubtitle())
            Text(error.localizedDescription)
                .font(.ilSubtitle())
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
        case .select: return "Select"
        case .markdown: return "Markdown"
        }
    }
}
