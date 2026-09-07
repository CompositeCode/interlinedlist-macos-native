// CreateFromViewModel
//
// Drives the "Create from…" sheet (work-consolidation.md G16) — turning
// messages, lists, rows, a document, or a highlighted selection into a new list,
// a new document, or both.
//
// The form is the interesting part: the server derives the content, but the
// *shape* (title, visibility, columns, styles) is the user's, and its rejection
// messages are unusually unhelpful — a wrong column shape reports a missing
// `key` property even when one is present. So this view model keeps a local
// completeness gate and only enables Create when the request can actually
// succeed.
//
// Per Decision 0003 this view model consumes only `InterlinedDomain`.

import Foundation
import Observation
import InterlinedDomain

@MainActor
@Observable
final class CreateFromViewModel {

    // MARK: - Inputs

    private let materialize: MaterializeServicing
    let source: MaterializeSourceRef

    // MARK: - Form state

    var output: MaterializeOutput {
        didSet { syncSpecsToOutput() }
    }

    var listTitle: String
    var listDescription: String = ""
    var listIsPublic = false
    var includeSourceData = true
    private(set) var columns: [MaterializeColumn]

    var documentTitle: String
    var documentFolderPath: String = ""
    var documentIsPublic = false
    var bulletStyle: MaterializeBulletStyle = .bulleted
    var rowStyle: MaterializeRowStyle = .table

    // MARK: - Progress

    private(set) var isCreating = false
    private(set) var errorMessage: String?
    private(set) var outcome: MaterializeOutcome?

    init(
        source: MaterializeSourceRef,
        materialize: MaterializeServicing,
        output: MaterializeOutput = .list,
        authorHandle: String? = nil
    ) {
        self.source = source
        self.materialize = materialize
        self.output = output
        let title = source.defaultTitle(authorHandle: authorHandle)
        self.listTitle = title
        self.documentTitle = title
        self.columns = MaterializeColumn.defaults(for: source)
    }

    // MARK: - Derived

    /// Whether Create can proceed. Mirrors the server's own requirements so the
    /// button disables instead of the request failing with a misleading message.
    var canCreate: Bool { !isCreating && spec.isComplete }

    var showsListSection: Bool { output.createsList }
    var showsDocumentSection: Bool { output.createsDocument }

    /// The spec as currently edited.
    var spec: MaterializeSpec {
        MaterializeSpec(
            source: source,
            output: output,
            list: output.createsList
                ? .init(
                    title: listTitle,
                    description: listDescription.isEmpty ? nil : listDescription,
                    isPublic: listIsPublic,
                    columns: columns,
                    includeSourceData: includeSourceData
                )
                : nil,
            document: output.createsDocument
                ? .init(
                    title: documentTitle,
                    folderPath: documentFolderPath.isEmpty ? nil : documentFolderPath,
                    isPublic: documentIsPublic,
                    listStyle: bulletStyle,
                    rowDataStyle: rowStyle
                )
                : nil
        )
    }

    // MARK: - Column editing

    func renameColumn(id: MaterializeColumn.ID, to name: String) {
        guard let index = columns.firstIndex(where: { $0.id == id }) else { return }
        columns[index].name = name
    }

    func setColumnType(id: MaterializeColumn.ID, to type: MaterializeColumnType) {
        guard let index = columns.firstIndex(where: { $0.id == id }) else { return }
        columns[index].type = type
    }

    func removeColumn(id: MaterializeColumn.ID) {
        columns.removeAll { $0.id == id }
    }

    /// Adds an empty column with a unique key, since the key identifies the
    /// column both here and on the created list.
    func addColumn() {
        let base = "column"
        var index = columns.count + 1
        var key = "\(base)_\(index)"
        while columns.contains(where: { $0.key == key }) {
            index += 1
            key = "\(base)_\(index)"
        }
        columns.append(MaterializeColumn(key: key, name: "Column \(index)", type: .text))
    }

    func restoreDefaultColumns() {
        columns = MaterializeColumn.defaults(for: source)
    }

    // MARK: - Creating

    func create() async {
        guard canCreate else { return }
        isCreating = true
        errorMessage = nil
        defer { isCreating = false }

        do {
            outcome = try await materialize.create(spec)
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    /// A user-facing sentence for the result, used by the sheet's success state.
    var outcomeSummary: String? {
        guard let outcome, !outcome.isEmpty else { return nil }
        switch (outcome.listId, outcome.documentId) {
        case (.some, .some): return "Created a list and a document."
        case (.some, nil): return "Created \(outcome.listTitle.map { "“\($0)”" } ?? "the list")."
        case (nil, .some): return "Created \(outcome.documentTitle.map { "“\($0)”" } ?? "the document")."
        default: return nil
        }
    }

    static func message(for error: Error) -> String {
        switch error {
        case MaterializeError.incompleteSpec:
            return "Add a title and at least one column first."
        default:
            return error.localizedDescription
        }
    }

    // MARK: - Internals

    /// Keeps the two titles in step while they are still untouched defaults, so
    /// switching to "List & Doc" does not present an empty second title field.
    private func syncSpecsToOutput() {
        if output.createsDocument, documentTitle.trimmingCharacters(in: .whitespaces).isEmpty {
            documentTitle = listTitle
        }
        if output.createsList, listTitle.trimmingCharacters(in: .whitespaces).isEmpty {
            listTitle = documentTitle
        }
    }
}
