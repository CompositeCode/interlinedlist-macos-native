import Foundation
import InterlinedKit

/// A tag with its recent usage count (work-consolidation.md G20). Feeds the
/// timeline's trending strip; `TagsService.suggestions` feeds the composer's
/// completion popover with bare names.
public struct TrendingTag: Sendable, Equatable, Identifiable {
    /// The tag text without a leading `#`.
    public let name: String
    public let count: Int
    public let lastUsedAt: Date?

    /// The tag name is the stable identity — the API has no separate tag id.
    public var id: String { name }

    public init(name: String, count: Int = 0, lastUsedAt: Date? = nil) {
        self.name = name
        self.count = count
        self.lastUsedAt = lastUsedAt
    }
}

extension TrendingTag {
    /// Maps the DTO, normalising away a leading `#` so callers can render the
    /// sigil themselves without risking a double `##`.
    public init(from dto: TrendingTagDTO) {
        self.init(
            name: TrendingTag.normalise(dto.tag),
            count: dto.count ?? 0,
            lastUsedAt: dto.lastUsedAt
        )
    }

    /// Strips a single leading `#` and surrounding whitespace.
    static func normalise(_ raw: String) -> String {
        var trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("#") { trimmed.removeFirst() }
        return trimmed
    }
}
