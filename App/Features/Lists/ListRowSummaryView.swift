// ListRowSummaryView
//
// Single browser-row summary card for a `ListSummary`: title,
// description, visibility badge, and a relative-time "updated" stamp.
// Uses SF Symbols and the brand `AccentColor` from the asset catalog
// (PLAN.md §9). Every interactive affordance carries a VoiceOver
// label; sizes honour Dynamic Type by leaning on `.font(.body)` /
// `.font(.subheadline)`.

import SwiftUI
import InterlinedDomain

struct ListRowSummaryView: View {
    let summary: ListSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            if let description = summary.description, !description.isEmpty {
                Text(description)
                    .font(.ilSubtitle())
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            footer
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
    }

    // MARK: - Sections

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "list.bullet.rectangle")
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)
            Text(summary.title)
                .font(.body.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
            Spacer(minLength: 8)
            if summary.visibility == .private {
                visibilityBadge
            }
        }
    }

    private var visibilityBadge: some View {
        Label("Private", systemImage: "lock")
            .font(.ilMono(10))
            .foregroundStyle(.secondary)
            .accessibilityLabel("Private list")
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if let updatedAt = summary.updatedAt {
                Label(
                    Self.relativeFormatter.localizedString(for: updatedAt, relativeTo: .now),
                    systemImage: "clock"
                )
                .font(.ilMono(10))
                .foregroundStyle(.secondary)
                .accessibilityLabel("Updated \(Self.fullFormatter.string(from: updatedAt))")
            }
            Spacer()
        }
    }

    // MARK: - Helpers

    private var accessibilitySummary: String {
        var parts: [String] = []
        parts.append(summary.title)
        if let description = summary.description, !description.isEmpty {
            parts.append(description)
        }
        if summary.visibility == .private {
            parts.append("Private list")
        }
        if let updatedAt = summary.updatedAt {
            parts.append("Updated \(Self.fullFormatter.string(from: updatedAt))")
        }
        return parts.joined(separator: ". ")
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()

    private static let fullFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}
