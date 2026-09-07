// TagCompletionViewModel
//
// Drives the composer's tag-completion popover (work-consolidation.md G20).
//
// Deliberately owned by the *view*, not by `ComposerViewModel`: completion is a
// presentation affordance over the existing free-form `tagsInput` string, so
// keeping it separate leaves the composer's publish path — and its signature —
// untouched.
//
// The composer's tag field is comma/space separated, so completion applies to
// the **last token being typed**; earlier tokens are already committed.
//
// Per Decision 0003 this view model consumes only `InterlinedDomain`.

import Foundation
import Observation
import InterlinedDomain

@MainActor
@Observable
final class TagCompletionViewModel {

    private let service: TagsServicing?
    /// How long to wait after the last keystroke before asking the server.
    private let debounce: Duration
    /// The in-flight lookup, cancelled when a newer keystroke supersedes it.
    private var task: Task<Void, Never>?

    private(set) var suggestions: [String] = []

    /// True when there is something to show. The view binds its popover to this.
    var isShowing: Bool { !suggestions.isEmpty }

    init(service: TagsServicing?, debounce: Duration = .milliseconds(200)) {
        self.service = service
        self.debounce = debounce
    }

    /// Call on every change to the raw tag-input string.
    func input(changed raw: String) {
        task?.cancel()
        let prefix = Self.activeToken(in: raw)
        // One character is too weak a prefix to be useful and matches most of
        // the corpus; wait for a second before asking.
        guard let service, prefix.count >= 2 else {
            suggestions = []
            return
        }
        task = Task { [debounce] in
            try? await Task.sleep(for: debounce)
            guard !Task.isCancelled else { return }
            do {
                let found = try await service.suggestions(prefix: prefix, limit: 8)
                guard !Task.isCancelled else { return }
                // Drop anything already committed earlier in the field.
                let committed = Set(Self.committedTokens(in: raw).map { $0.lowercased() })
                suggestions = found.filter { !committed.contains($0.lowercased()) }
            } catch {
                // Completion is an optional nicety — a failed lookup silently
                // shows nothing rather than interrupting composition with an
                // error the user cannot act on.
                suggestions = []
            }
        }
    }

    /// Replaces the token being typed with `suggestion`, returning the new field
    /// value. Leaves a trailing space so the next tag can be typed immediately.
    func apply(_ suggestion: String, to raw: String) -> String {
        var tokens = Self.committedTokens(in: raw)
        tokens.append(suggestion)
        suggestions = []
        task?.cancel()
        return tokens.joined(separator: " ") + " "
    }

    func dismiss() {
        task?.cancel()
        suggestions = []
    }

    // MARK: - Token parsing
    //
    // Mirrors `ComposerViewModel.normalise(tags:)`: split on commas and
    // whitespace, strip a leading `#`.

    private static let separators = CharacterSet(charactersIn: ", \t\n")

    /// The token currently being typed — the trailing fragment. Empty when the
    /// field ends in a separator (nothing is being typed right now).
    static func activeToken(in raw: String) -> String {
        guard let last = raw.unicodeScalars.last, !separators.contains(last) else { return "" }
        let fragment = raw.components(separatedBy: separators as CharacterSet).last ?? ""
        return fragment.hasPrefix("#") ? String(fragment.dropFirst()) : fragment
    }

    /// Every token except the one being typed.
    static func committedTokens(in raw: String) -> [String] {
        var parts = raw
            .components(separatedBy: separators as CharacterSet)
            .map { $0.hasPrefix("#") ? String($0.dropFirst()) : $0 }
            .filter { !$0.isEmpty }
        // If the field does not end in a separator, the final part is still
        // being typed and is not yet committed.
        if let last = raw.unicodeScalars.last, !separators.contains(last), !parts.isEmpty {
            parts.removeLast()
        }
        return parts
    }
}
