// ExportView
//
// The M7 Data Export sheet (PLAN.md §1 "Data Exports", §6 M7).
// Presented as a `.sheet` from `MainWindowView` whenever one of the
// four `ExportMenuCommands` notifications fires.
//
// The view is a thin shell over `ExportViewModel`:
//   - Creates the view model once in `.task` using `\.appEnvironment`.
//   - When an `initialExportType` is supplied (triggered by a menu
//     command), calls `export(_:)` immediately so the save panel
//     follows without an extra tap.
//   - The `.fileExporter` modifier opens the macOS save panel when
//     `viewModel.pendingExport` becomes non-nil; clears it on dismiss.
//
// Per Decision 0003 this file imports `InterlinedDomain` only —
// no `InterlinedKit`, no `AppKit`, no `NSSavePanel`.

import SwiftUI
import UniformTypeIdentifiers
import InterlinedDomain

// MARK: - ExportView

struct ExportView: View {

    @Environment(\.appEnvironment) private var environment
    @State private var viewModel: ExportViewModel?

    /// When set, the view auto-triggers this export as soon as the view
    /// model is ready. Nil means the user picks manually from the list.
    let initialExportType: ExportViewModel.ExportType?

    init(initialExportType: ExportViewModel.ExportType? = nil) {
        self.initialExportType = initialExportType
    }

    var body: some View {
        Group {
            if let viewModel {
                ExportContentView(viewModel: viewModel)
            } else {
                ProgressView()
                    .frame(minWidth: 480, minHeight: 280)
            }
        }
        .task {
            guard viewModel == nil, let environment else { return }
            let vm = ExportViewModel(exportsService: environment.exportsService)
            viewModel = vm
            if let initialExportType {
                vm.export(initialExportType)
            }
        }
    }
}

// MARK: - ExportContentView

/// Inner view that takes a non-optional `ExportViewModel` so bindings
/// and the `.fileExporter` modifier can reference it without optionals.
private struct ExportContentView: View {

    @Bindable var viewModel: ExportViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            Text("Export Data")
                .font(.ilTitle())
                .padding([.top, .horizontal], 20)
                .frame(maxWidth: .infinity, alignment: .leading)

            Form {
                ForEach(ExportViewModel.ExportType.allCases) { type in
                    ExportRowView(type: type, viewModel: viewModel)
                }
            }
            .formStyle(.grouped)

            if let errorMessage = viewModel.errorMessage {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(ILColor.amber)
                    Text(errorMessage)
                        .font(.ilBody())
                        .foregroundStyle(ILColor.textBody)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(ILColor.amber.opacity(0.12))
                .cornerRadius(ILMetric.radiusMd)
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
            }

            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(20)
        }
        .frame(minWidth: 480)
        .overlay {
            if viewModel.isExporting {
                Color.black.opacity(0.2)
                ProgressView("Exporting…")
                    .padding(24)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: ILMetric.radiusLg))
            }
        }
        .fileExporter(
            isPresented: Binding(
                get: { viewModel.pendingExport != nil },
                set: { if !$0 { viewModel.pendingExport = nil } }
            ),
            document: ExportDocument(viewModel.pendingExport),
            contentType: .commaSeparatedText,
            defaultFilename: viewModel.activeExport?.defaultFilename ?? "export"
        ) { result in
            viewModel.pendingExport = nil
            if case .failure(let error) = result {
                viewModel.errorMessage = error.localizedDescription
            }
        }
    }
}

// MARK: - ExportRowView

private struct ExportRowView: View {

    let type: ExportViewModel.ExportType
    @Bindable var viewModel: ExportViewModel

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(type.rawValue)
                    .font(.ilBodyMedium())
                Text(type.exportDescription)
                    .font(.ilBody())
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Export CSV…") {
                viewModel.export(type)
            }
            .disabled(viewModel.isExporting)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - ExportDocument

/// A `FileDocument` that wraps raw CSV bytes for use with SwiftUI's
/// `.fileExporter` modifier (macOS 12+). The domain `CSVExport` carries
/// the server bytes; this adapter is the only AppKit-free way to present
/// a save panel without `NSSavePanel`.
struct ExportDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.commaSeparatedText]

    let data: Data

    /// Builds a document from a `CSVExport`. Accepts `nil` so the
    /// `.fileExporter`'s `document:` parameter is always satisfied even
    /// before `pendingExport` becomes non-nil; `isPresented` controls
    /// when the dialog actually appears.
    init(_ export: CSVExport?) {
        self.data = export?.data ?? Data()
    }

    init(configuration: ReadConfiguration) throws {
        self.data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
