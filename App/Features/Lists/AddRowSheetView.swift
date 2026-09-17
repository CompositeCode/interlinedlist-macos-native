// AddRowSheetView
//
// The Add Row form (GitHub #50). macOS had none — rows were created empty and
// filled in through the inspector afterwards, which is why the per-column help
// text, placeholders and validation rules had nowhere to appear.
//
// The "Add another after saving" checkbox is the keyboard-ergonomics win the web
// documents: saving keeps you on the form, empties it, counts up, and returns
// focus to the first field, so bulk entry never needs the mouse between rows.
// Its state is persisted across lists and visits, as the help page specifies.
//
// Pure SwiftUI; no AppKit. Decision 0003: consumes only `InterlinedDomain`.

import SwiftUI
import InterlinedDomain

struct AddRowSheetView: View {

    let listId: String
    let schema: ListSchema
    /// Called after each successful save so the host can fold the new row in.
    var onSaved: () -> Void = {}

    @Environment(\.appEnvironment) private var environment
    @Environment(\.dismiss) private var dismiss

    /// Remembered across lists and across visits, as the web documents.
    @AppStorage("lists.addRow.addAnotherAfterSaving") private var addAnother = false

    @State private var viewModel: AddRowViewModel?
    @FocusState private var focusedKey: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            if let viewModel {
                form(viewModel)
                Divider()
                footer(viewModel)
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(width: 460, height: 520)
        .task {
            guard viewModel == nil, let environment else { return }
            viewModel = AddRowViewModel(
                lists: environment.lists,
                listId: listId,
                schema: schema,
                addAnotherAfterSaving: addAnother
            )
            focusedKey = schema.orderedFields.first?.key
        }
    }

    private var header: some View {
        HStack {
            Text("Add Row").font(.ilTitle(18))
            Spacer()
            if let count = viewModel?.savedCount, count > 0 {
                // The running confirmation. With the sheet staying open, this is
                // the only signal that a row actually went in.
                Text("^[\(count) row](inflect: true) added")
                    .font(.ilMono(10))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
    }

    @ViewBuilder
    private func form(_ viewModel: AddRowViewModel) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if schema.fields.isEmpty {
                    Text("This list has no columns yet. Add some in Edit Schema first.")
                        .font(.ilBody())
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(schema.orderedFields) { field in
                        fieldEditor(field, viewModel: viewModel)
                    }
                }
            }
            .padding(12)
        }
        .onChange(of: viewModel.shouldRefocusFirstField) { _, shouldRefocus in
            // "the cursor returns to the first field" — the difference between
            // bulk entry that needs the mouse between rows and bulk entry that
            // does not.
            guard shouldRefocus else { return }
            focusedKey = schema.orderedFields.first?.key
            viewModel.consumeRefocusRequest()
            onSaved()
        }
        .onChange(of: viewModel.didFinish) { _, finished in
            if finished { onSaved(); dismiss() }
        }
    }

    @ViewBuilder
    private func fieldEditor(_ field: SchemaField, viewModel: AddRowViewModel) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Text(field.label.isEmpty ? field.key : field.label)
                    .font(.caption.weight(.semibold))
                if field.isRequired == true {
                    Text("required")
                        .font(.ilMono(9))
                        .foregroundStyle(.secondary)
                }
            }

            switch field.type {
            case .boolean:
                Toggle("", isOn: Binding(
                    get: { if case .bool(let v) = viewModel.value(forKey: field.key) { return v } else { return false } },
                    set: { viewModel.setValue(.bool($0), forKey: field.key) }
                ))
                .toggleStyle(.checkbox)
                .labelsHidden()
                .accessibilityLabel(field.label)

            case .select:
                Picker("", selection: Binding(
                    get: { viewModel.value(forKey: field.key).displayText },
                    set: { viewModel.setValue($0.isEmpty ? .null : .string($0), forKey: field.key) }
                )) {
                    // A leading empty tag so an optional select can be left unset
                    // — without it the picker would silently pick the first
                    // option for the user.
                    Text("—").tag("")
                    ForEach(field.enumValues ?? [], id: \.self) { option in
                        Text(option).tag(option)
                    }
                }
                .labelsHidden()
                .accessibilityLabel(field.label)

            default:
                TextField(
                    field.placeholder ?? "",
                    text: Binding(
                        get: { viewModel.value(forKey: field.key).displayText },
                        set: { viewModel.setValue($0.isEmpty ? .null : .string($0), forKey: field.key) }
                    )
                )
                .textFieldStyle(.roundedBorder)
                .focused($focusedKey, equals: field.key)
            }

            if let helpText = field.helpText, !helpText.isEmpty {
                Text(helpText)
                    .font(.ilMono(10))
                    .foregroundStyle(.secondary)
            }
            if let failure = viewModel.failures[field.key] {
                Text(failure)
                    .font(.ilMono(10))
                    .foregroundStyle(.red)
            }
        }
    }

    @ViewBuilder
    private func footer(_ viewModel: AddRowViewModel) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let error = viewModel.error {
                Text(error.localizedDescription)
                    .font(.ilMono(10))
                    .foregroundStyle(.orange)
            }
            HStack {
                Toggle("Add another after saving", isOn: Binding(
                    get: { addAnother },
                    set: { newValue in
                        addAnother = newValue
                        viewModel.addAnotherAfterSaving = newValue
                    }
                ))
                .toggleStyle(.checkbox)
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Add Row") {
                    Task { await viewModel.save() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(viewModel.isSaving || schema.fields.isEmpty)
                if viewModel.isSaving {
                    ProgressView().controlSize(.small)
                }
            }
        }
        .padding(12)
    }
}
