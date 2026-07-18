// RowInspectorView
//
// Right-side inspector pane for the currently-selected row of a
// list (PLAN.md §6 M3 row inspector). Renders per-type input
// controls for each schema field, calling
// `ListRowsViewModel.updateRow` on commit.
//
// Drives its own subscription to `ListRowsViewModel` selection so
// the inspector reflects the current row state. The inspector
// doesn't own the view model — `ListRowsView` does — but it reads
// the selection so the pane stays in sync.

import SwiftUI
import InterlinedDomain
import Textual

struct RowInspectorView: View {

    let viewModel: ListRowsViewModel?

    @State private var editingValues: [String: String] = [:]

    var body: some View {
        Group {
            if let viewModel, let row = viewModel.selectedRow {
                inspector(viewModel: viewModel, row: row)
            } else {
                placeholder
            }
        }
    }

    @ViewBuilder
    private func inspector(viewModel: ListRowsViewModel, row: ListRow) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Row")
                    .font(.ilTitle(20))
                Divider()
                if viewModel.schema.fields.isEmpty {
                    ForEach(row.fields.keys.sorted(), id: \.self) { key in
                        cellEditor(
                            key: key,
                            type: .text,
                            options: [],
                            current: row.fields[key] ?? .null,
                            row: row,
                            viewModel: viewModel
                        )
                    }
                } else {
                    ForEach(viewModel.schema.fields) { field in
                        cellEditor(
                            key: field.name,
                            type: field.type,
                            options: field.enumValues ?? [],
                            current: row.fields[field.name] ?? .null,
                            row: row,
                            viewModel: viewModel
                        )
                    }
                }
            }
            .padding(12)
        }
    }

    @ViewBuilder
    private func cellEditor(
        key: String,
        type: SchemaFieldType,
        options: [String],
        current: ListCellValue,
        row: ListRow,
        viewModel: ListRowsViewModel
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(key)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            switch type {
            case .text, .url, .email, .date, .number:
                TextField(label(for: type), text: Binding(
                    get: { editingValues[key] ?? current.displayText },
                    set: { editingValues[key] = $0 }
                ))
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    commitChange(row: row, key: key, type: type, viewModel: viewModel)
                }
            case .boolean:
                Toggle("", isOn: Binding(
                    get: {
                        if let pending = editingValues[key] {
                            return pending == "true"
                        }
                        if case .bool(let value) = current { return value }
                        return false
                    },
                    set: { newValue in
                        editingValues[key] = newValue ? "true" : "false"
                        commitChange(row: row, key: key, type: type, viewModel: viewModel)
                    }
                ))
                .accessibilityLabel(key)
            case .select:
                selectEditor(
                    key: key,
                    options: options,
                    current: current,
                    row: row,
                    viewModel: viewModel
                )
            case .markdown:
                markdownEditor(
                    key: key,
                    current: current,
                    row: row,
                    viewModel: viewModel
                )
            }
        }
    }

    /// A `Picker` constrained to the column's option set. The stored value is
    /// the chosen option's raw text; committing routes through the same
    /// `updateRow` path as every other cell. A leading empty tag models "no
    /// selection" so a nullable select can be cleared.
    @ViewBuilder
    private func selectEditor(
        key: String,
        options: [String],
        current: ListCellValue,
        row: ListRow,
        viewModel: ListRowsViewModel
    ) -> some View {
        Picker("", selection: Binding(
            get: { editingValues[key] ?? current.displayText },
            set: { newValue in
                editingValues[key] = newValue
                commitChange(row: row, key: key, type: .select, viewModel: viewModel)
            }
        )) {
            Text("—").tag("")
            ForEach(options, id: \.self) { option in
                Text(option).tag(option)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .accessibilityLabel(key)
    }

    /// An editable multiline field previewed with the same `Textual` renderer
    /// Documents uses (`StructuredText(markdown:)`). Edits are buffered in
    /// `editingValues` and committed on the explicit "Save" control — a
    /// `TextEditor` has no `onSubmit`, and auto-committing every keystroke
    /// would fire a write per character.
    @ViewBuilder
    private func markdownEditor(
        key: String,
        current: ListCellValue,
        row: ListRow,
        viewModel: ListRowsViewModel
    ) -> some View {
        let source = editingValues[key] ?? current.displayText
        VStack(alignment: .leading, spacing: 6) {
            TextEditor(text: Binding(
                get: { editingValues[key] ?? current.displayText },
                set: { editingValues[key] = $0 }
            ))
            .font(.ilMono(12))
            .frame(minHeight: 100)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.secondary.opacity(0.3))
            )
            .accessibilityLabel(key)
            if !source.isEmpty {
                StructuredText(markdown: source)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityLabel("\(key) preview")
            }
            HStack {
                Spacer()
                Button("Save") {
                    commitChange(row: row, key: key, type: .markdown, viewModel: viewModel)
                }
                .controlSize(.small)
                .disabled(editingValues[key] == nil)
            }
        }
    }

    private func commitChange(
        row: ListRow,
        key: String,
        type: SchemaFieldType,
        viewModel: ListRowsViewModel
    ) {
        let input = editingValues[key] ?? ""
        let newValue = ListRowsViewModel.parse(input, as: type)
        var newFields = row.fields
        newFields[key] = newValue
        editingValues[key] = nil
        Task { await viewModel.updateRow(id: row.id, fields: newFields) }
    }

    private var placeholder: some View {
        VStack(spacing: 8) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.ilDisplay(36))
                .foregroundStyle(.secondary)
            Text("Row inspector")
                .font(.ilSubtitle())
            Text("Select a row to inspect its fields.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func label(for type: SchemaFieldType) -> String {
        switch type {
        case .text: return "Text"
        case .number: return "Number"
        case .boolean: return "Boolean"
        case .date: return "ISO-8601 date"
        case .url: return "URL"
        case .email: return "Email"
        case .select: return "Select"
        case .markdown: return "Markdown"
        }
    }

}
