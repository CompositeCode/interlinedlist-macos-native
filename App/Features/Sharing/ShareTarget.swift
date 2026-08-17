// ShareTarget
//
// The resource a share-links panel is scoped to (work-consolidation.md G3). A list
// or a document — the `ShareLinksViewModel` switches on this to dispatch
// to the `list*` or `document*` half of `SharingServicing`, so the view
// layer builds one panel regardless of which resource it's sharing.
//
// Per decision 0003, this type lives in the App layer and depends on
// `InterlinedDomain` only.

import Foundation

/// Identifies which resource a share-links panel manages links for.
enum ShareTarget: Equatable, Hashable {
    case list(id: String)
    case document(id: String)

    /// The underlying resource id, used for the debounce key and for
    /// building/parsing share URLs.
    var id: String {
        switch self {
        case .list(let id): return id
        case .document(let id): return id
        }
    }

    /// Whether this target is a document (vs. a list) — drives the copy in
    /// the panel header and the URL path segment (`documents` vs `lists`).
    var isDocument: Bool {
        if case .document = self { return true }
        return false
    }

    /// Human-facing noun for the header ("list" / "document").
    var noun: String { isDocument ? "document" : "list" }
}
