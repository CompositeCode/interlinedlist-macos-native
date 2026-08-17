// MarkdownExportRequest
//
// A rendered Markdown export awaiting SwiftUI's `.fileExporter` save panel:
// the composed document text plus a default filename stem (no extension).
//
// Shared by every Markdown-export entry point so they drive one
// `MarkdownFileDocument` save flow (work-consolidation.md §1b):
//   - the Export sheet          → all owned lists     (`ExportViewModel`)
//   - the document editor       → one document        (`DocumentEditorViewModel`)
//   - a message thread          → root + replies       (`MessageDetailViewModel`)
//
// The rendering itself lives in `InterlinedDomain.MarkdownExporter`; this type
// is only the App-layer save-panel payload.

import Foundation

struct MarkdownExportRequest: Equatable {
    /// Filename stem for the save panel (no extension — `.fileExporter`
    /// appends `.md` from the `.markdownText` content type).
    let filename: String
    /// The fully rendered Markdown.
    let text: String
}

extension MarkdownExportRequest {

    /// Sanitises an arbitrary title into a safe, readable filename stem:
    /// lowercased, each run of non-alphanumerics collapsed to a single hyphen,
    /// leading/trailing hyphens trimmed. A title that is empty or all symbols
    /// yields `fallback` so the save panel always has a sensible name.
    static func filenameStem(from title: String, fallback: String) -> String {
        var out = ""
        var lastWasHyphen = false
        for scalar in title.lowercased().unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                out.unicodeScalars.append(scalar)
                lastWasHyphen = false
            } else if !lastWasHyphen {
                out.append("-")
                lastWasHyphen = true
            }
        }
        let trimmed = out.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return trimmed.isEmpty ? fallback : trimmed
    }
}
