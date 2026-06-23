// MessageRowView
//
// Single timeline row: author identity, relative timestamp, body
// (plain text for M2 — Markdown rendering is deferred to a later
// milestone), tag chips, dig count, and a repost indicator. Uses SF
// Symbols and the brand `AccentColor` from the asset catalog (PLAN.md
// §9). Every interactive affordance carries a VoiceOver label; sizes
// honour Dynamic Type by leaning on `.font(.body)` /
// `.font(.subheadline)`.
//
// M2 additions:
// - The dig label becomes a tappable button that flips the dig state
//   optimistically via the host's `onToggleDig` closure.
// - Context menu with "Repost", "Edit", "Delete". Edit / Delete
//   render only when `canEdit` is true (ownership-gated per PLAN.md
//   §6 M2 — never enabled-but-broken).
// - Host wires the actions via closures so the row stays passive and
//   reusable across the timeline, message detail header, and the
//   replies list.

import SwiftUI
import InterlinedDomain

struct MessageRowView: View {

    let message: Message

    /// Whether the current viewer is the author and the row should
    /// expose Edit / Delete. The host decides this — typically by
    /// asking `TimelineViewModel.canEdit(message:currentUserID:)`.
    var canEdit: Bool = false

    /// Optional dig-toggle handler. When `nil`, the dig glyph renders
    /// as plain text (no button) — used in preview / static contexts.
    var onToggleDig: ((Message) -> Void)? = nil

    /// Optional repost handler. When `nil`, the "Repost" menu item is
    /// hidden.
    var onRepost: ((Message) -> Void)? = nil

    /// Optional edit handler. Only invoked when `canEdit` is true.
    var onEdit: ((Message) -> Void)? = nil

    /// Optional delete handler. Only invoked when `canEdit` is true.
    /// The host is responsible for the confirmation dialog.
    var onDelete: ((Message) -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            if let repost = message.repost {
                repostBanner(original: repost.original)
            }
            bodyText
            if !message.tags.isEmpty {
                tagChips
            }
            footer
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .contextMenu {
            contextMenuItems
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
    }

    // MARK: - Sections

    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            avatar
            VStack(alignment: .leading, spacing: 2) {
                Text(message.author.displayName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text("@\(message.author.username)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(Self.relativeFormatter.localizedString(for: message.createdAt, relativeTo: .now))
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Posted \(Self.fullFormatter.string(from: message.createdAt))")
        }
    }

    private var avatar: some View {
        AsyncImage(url: message.author.avatarURL) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            default:
                Image(systemName: "person.crop.circle.fill")
                    .resizable()
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 32, height: 32)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }

    private var bodyText: some View {
        // Plain text in M2; Markdown source rendering lands in a
        // later milestone alongside richer composer affordances.
        // `.body` honours Dynamic Type.
        Text(message.text)
            .font(.body)
            .foregroundStyle(.primary)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var tagChips: some View {
        // A wrapping run of small badges. `FlowLayout` is iOS 17+ only,
        // so we use a horizontal stack with wrapping by way of `Lazy`
        // grids would over-engineer it — for M1 the row count is small
        // and a single horizontal stack is fine.
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(message.tags, id: \.self) { tag in
                    Text("#\(tag)")
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.accentColor.opacity(0.15), in: Capsule())
                        .foregroundStyle(Color.accentColor)
                        .accessibilityLabel("Tag \(tag)")
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 16) {
            digButton

            if message.repostCount > 0 {
                Label("\(message.repostCount)", systemImage: "arrow.2.squarepath")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("\(message.repostCount) reposts")
            }

            if let count = message.replyCount, count > 0 {
                Label("\(count)", systemImage: "bubble.left")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("\(count) replies")
            }

            if message.visibility == .private {
                Label("Private", systemImage: "lock")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Private post")
            }

            Spacer()
        }
    }

    /// Dig label: a button when the host supplied a handler,
    /// otherwise the static label used in preview contexts.
    @ViewBuilder
    private var digButton: some View {
        if let onToggleDig {
            Button {
                onToggleDig(message)
            } label: {
                digLabel
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                "\(message.didDig ? "Undig" : "Dig") — \(message.digCount) total"
            )
        } else {
            digLabel
                .accessibilityLabel(
                    "\(message.digCount) digs\(message.didDig ? ", you dug this" : "")"
                )
        }
    }

    private var digLabel: some View {
        Label(
            "\(message.digCount)",
            systemImage: message.didDig ? "hand.thumbsup.fill" : "hand.thumbsup"
        )
        .font(.caption)
        .foregroundStyle(message.didDig ? Color.accentColor : .secondary)
    }

    @ViewBuilder
    private var contextMenuItems: some View {
        if let onRepost {
            Button {
                onRepost(message)
            } label: {
                Label("Repost", systemImage: "arrow.2.squarepath")
            }
        }

        // Ownership-gated. When the session hasn't resolved
        // (`canEdit == false`), the menu items are simply absent so
        // the user never sees an enabled-but-broken affordance.
        if canEdit {
            if let onEdit {
                Button {
                    onEdit(message)
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
            }
            if let onDelete {
                Button(role: .destructive) {
                    onDelete(message)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
    }

    private func repostBanner(original: Message) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.2.squarepath")
                .font(.caption)
            Text("Reposted from @\(original.author.username)")
                .font(.caption)
        }
        .foregroundStyle(.secondary)
        .accessibilityLabel("Reposted from @\(original.author.username)")
    }

    // MARK: - Helpers

    private var accessibilitySummary: String {
        var parts: [String] = []
        parts.append("\(message.author.displayName), @\(message.author.username)")
        parts.append(Self.fullFormatter.string(from: message.createdAt))
        parts.append(message.text)
        if !message.tags.isEmpty {
            parts.append("Tags: \(message.tags.joined(separator: ", "))")
        }
        parts.append("\(message.digCount) digs")
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
