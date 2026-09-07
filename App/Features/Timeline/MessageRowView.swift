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
// - Context menu with "Push", "Edit", "Delete". Edit / Delete
//   render only when `canEdit` is true (ownership-gated per PLAN.md
//   §6 M2 — never enabled-but-broken).
// - Host wires the actions via closures so the row stays passive and
//   reusable across the timeline, message detail header, and the
//   replies list.

import SwiftUI
import InterlinedDomain

struct MessageRowView: View {

    /// Read for the account's link-preview preference and the image-proxy
    /// decision (G21). The row stays otherwise passive.
    @EnvironmentObject private var environment: AppEnvironment

    let message: Message

    /// Whether the current viewer is the author and the row should
    /// expose Edit / Delete. The host decides this — typically by
    /// asking `TimelineViewModel.canEdit(message:currentUserID:)`.
    var canEdit: Bool = false

    /// Every optional action the host wires in — dig, reply, push, edit,
    /// delete, moderation, and "create GitHub issue". Defaults to `.none`
    /// so preview and read-only contexts (search results) render the row
    /// with no interactive affordances at all.
    var actions: MessageRowActions = .none

    /// Opens "Create from…" for this message (work-consolidation.md G16).

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            if let repost = message.repost {
                repostBanner(original: repost.original)
            }
            bodyText
            if !renderablePreviews.isEmpty {
                linkPreviews
            }
            if !message.crossPostLocations.isEmpty {
                crossPostLinks
            }
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
        .accessibilityAction(named: "I Dig!") {
            actions.onToggleDig?(message)
        }
        .accessibilityAction(named: "Reply") {
            actions.onReply?(message)
        }
        .accessibilityAction(named: "Push") {
            actions.onPush?(message)
        }
    }

    // MARK: - Sections

    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            avatar
            VStack(alignment: .leading, spacing: 2) {
                Text(message.author.displayName)
                    .font(.ilTitle())
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text("@\(message.author.username)")
                    .font(.ilMono(10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(Self.relativeFormatter.localizedString(for: message.createdAt, relativeTo: .now))
                .font(.ilMono(10))
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
            .font(.ilBody())
            .foregroundStyle(.primary)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// The subset of `message.linkPreviews` the domain deems worth showing
    /// (feature-gaps §1.5). A bare URL with no resolved metadata is filtered
    /// out here — the row degrades to no card rather than an empty one.
    ///
    /// Gated on the account's "Show link previews" preference (G21). That
    /// toggle shipped in Settings ▸ Preferences with no reader outside the
    /// Settings pane, so turning it off had no effect anywhere; this is the
    /// reader. `showLinkPreviews` defaults to true, matching the server
    /// default, so a row renders normally before preferences have loaded.
    private var renderablePreviews: [LinkPreview] {
        guard environment.userPreferences.showLinkPreviews else { return [] }
        return message.linkPreviews.filter(\.isRenderable)
    }

    private var linkPreviews: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(renderablePreviews) { preview in
                LinkPreviewCardView(
                    preview: preview,
                    // Instagram thumbnails must go through the server proxy
                    // (their CDN blocks hotlinking); everything else loads
                    // directly. The service owns that host test.
                    imageURL: environment.linkMetadata?.displayImageURL(for: preview)
                        ?? preview.imageURL
                )
            }
        }
    }

    /// Links to the external copies a cross-posted message landed on
    /// (`message.crossPostLocations`, projected from the server's
    /// `crossPostUrls`). Rendered as a wrapping run of tappable pills — each a
    /// SwiftUI `Link`, so a tap opens the destination via the system URL handler
    /// with no AppKit involvement (App target SwiftUI-only constraint). The
    /// "should this show?" gate lives on the message (non-empty locations); the
    /// view stays passive. Mirrors the `tagChips` chip idiom for visual parity.
    private var crossPostLinks: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                Label("Also on", systemImage: "arrow.up.forward.app")
                    .labelStyle(.titleAndIcon)
                    .font(.ilMono(9))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)

                ForEach(message.crossPostLocations) { location in
                    Link(destination: location.url) {
                        Text(location.displayName)
                            .font(.ilMono(9))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(ILColor.primary.opacity(0.15), in: Capsule())
                            .foregroundStyle(Color.accentColor)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("View this post on \(location.displayName)")
                    .accessibilityHint("Opens the cross-posted copy in your browser")
                }
            }
        }
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
                        .font(.ilMono(9))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(ILColor.primary.opacity(0.15), in: Capsule())
                        .foregroundStyle(Color.accentColor)
                        .accessibilityLabel("Tag \(tag)")
                }
            }
        }
    }

    /// The row's action bar. Order matches the web's message actions:
    /// Reply, I Dig!, Push, Push & Comment, Link.
    ///
    /// Reply / Dig / Push degrade to a plain count label when the host wired
    /// no handler (search results, previews), so a read-only row still shows
    /// the numbers without offering a control that would do nothing. Link is
    /// unconditional — it is a pure client-side permalink and needs no host
    /// wiring, so it works everywhere the message has an id.
    private var footer: some View {
        HStack(spacing: 16) {
            replyButton
            digButton
            pushButton
            pushAndCommentButton
            linkButton

            if message.visibility == .private {
                Label("Private", systemImage: "lock")
                    .font(.ilMono(10))
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Private post")
            }

            Spacer()
        }
    }

    /// Shared shape for every action-bar item: an icon with an optional
    /// count beside it. `nil` count renders icon-only rather than an empty
    /// title, so a zero never reads as a stray glyph.
    @ViewBuilder
    private func actionLabel(count: Int?, systemImage: String, tint: Color) -> some View {
        if let count, count > 0 {
            Label("\(count)", systemImage: systemImage)
                .font(.ilMono(10))
                .foregroundStyle(tint)
        } else {
            Image(systemName: systemImage)
                .font(.ilMono(10))
                .foregroundStyle(tint)
        }
    }

    /// Reply. Routes to the message-detail composer via the host rather than
    /// opening a second write surface.
    @ViewBuilder
    private var replyButton: some View {
        let count = message.replyCount ?? 0
        if let onReply = actions.onReply {
            Button {
                onReply(message)
            } label: {
                actionLabel(count: count, systemImage: "arrowshape.turn.up.left", tint: .secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(count > 0 ? "Reply \u{2014} \(count) replies" : "Reply")
            .help("Reply to this post")
        } else if count > 0 {
            actionLabel(count: count, systemImage: "arrowshape.turn.up.left", tint: .secondary)
                .accessibilityLabel("\(count) replies")
        }
    }

    /// Bare, one-tap Push (repost with no commentary).
    @ViewBuilder
    private var pushButton: some View {
        if let onPush = actions.onPush {
            Button {
                onPush(message)
            } label: {
                actionLabel(count: message.repostCount, systemImage: "arrow.2.squarepath", tint: .secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                message.repostCount > 0
                    ? "Push \u{2014} \(message.repostCount) pushes"
                    : "Push"
            )
            .help("Push this post to your followers")
        } else if message.repostCount > 0 {
            actionLabel(count: message.repostCount, systemImage: "arrow.2.squarepath", tint: .secondary)
                .accessibilityLabel("\(message.repostCount) pushes")
        }
    }

    /// Push with commentary — opens the host's repost sheet.
    @ViewBuilder
    private var pushAndCommentButton: some View {
        if let onPushAndComment = actions.onPushAndComment {
            Button {
                onPushAndComment(message)
            } label: {
                actionLabel(count: nil, systemImage: "quote.bubble", tint: .secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Push and comment")
            .help("Push this post with your own commentary")
        }
    }

    /// Link to this specific post. `SwiftUI.ShareLink` (disambiguated from
    /// `InterlinedDomain.ShareLink`) opens the system share sheet, which
    /// includes Copy \u{2014} no `NSPasteboard`, no AppKit in the App target.
    @ViewBuilder
    private var linkButton: some View {
        if let url = message.permalink() {
            SwiftUI.ShareLink(item: url) {
                Image(systemName: "link")
                    .font(.ilMono(10))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Link to this post")
            .help("Share or copy a link to this post")
        }
    }

    /// Dig label: a button when the host supplied a handler,
    /// otherwise the static label used in preview contexts.
    @ViewBuilder
    private var digButton: some View {
        if let onToggleDig = actions.onToggleDig {
            Button {
                onToggleDig(message)
            } label: {
                digLabel
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                "\(message.didDig ? "Undo I Dig!" : "I Dig!") — \(message.digCount) total"
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
        .font(.ilMono(10))
        .foregroundStyle(message.didDig ? Color.accentColor : .secondary)
    }

    @ViewBuilder
    private var contextMenuItems: some View {
        // Every action-bar affordance is mirrored here so both discovery
        // paths (visible bar, right-click) offer the same set.
        if let onReply = actions.onReply {
            Button {
                onReply(message)
            } label: {
                Label("Reply", systemImage: "arrowshape.turn.up.left")
            }
        }

        if let onPush = actions.onPush {
            Button {
                onPush(message)
            } label: {
                Label("Push", systemImage: "arrow.2.squarepath")
            }
        }

        if let onPushAndComment = actions.onPushAndComment {
            Button {
                onPushAndComment(message)
            } label: {
                Label("Push & Comment\u{2026}", systemImage: "quote.bubble")
            }
        }

        if let url = message.permalink() {
            SwiftUI.ShareLink(item: url) {
                Label("Link", systemImage: "link")
            }
        }

        if actions.onReply != nil || actions.onPush != nil || actions.onPushAndComment != nil {
            Divider()
        }

        if let onCreateGitHubIssue = actions.onCreateGitHubIssue {
            Button {
                onCreateGitHubIssue(message)
            } label: {
                Label("Create GitHub Issue\u{2026}", systemImage: "ladybug")
            }
        }

        // "Create from…" (work-consolidation.md G16) — turn this message into a
        // list, a document, or both. Ownership-independent: the source only has
        // to be readable, and the created list or document belongs to the caller.
        if let onCreateFrom = actions.onCreateFrom {
            Button {
                onCreateFrom(message)
            } label: {
                Label("Create from\u{2026}", systemImage: "plus.rectangle.on.folder")
            }
        }

        // Ownership-gated. When the session hasn't resolved
        // (`canEdit == false`), the menu items are simply absent so
        // the user never sees an enabled-but-broken affordance.
        if canEdit {
            if let onEdit = actions.onEdit {
                Button {
                    onEdit(message)
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
            }
            if let onDelete = actions.onDelete {
                Button(role: .destructive) {
                    onDelete(message)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }

        // Moderation (work-consolidation.md G2). Block / Mute target the author;
        // Report opens the host's report sheet for this message. All are
        // ownership-independent (Report satisfies App Store Review
        // Guideline 1.2: User-Generated Content requires a report
        // mechanism). Each item renders only when its handler is wired so
        // static / preview contexts stay clean; no AppKit involvement.
        if actions.onBlock != nil || actions.onMute != nil || actions.onReport != nil {
            Divider()
        }
        if let onBlock = actions.onBlock {
            Button {
                onBlock(message)
            } label: {
                Label("Block @\(message.author.username)", systemImage: "hand.raised")
            }
        }
        if let onMute = actions.onMute {
            Button {
                onMute(message)
            } label: {
                Label("Mute @\(message.author.username)", systemImage: "speaker.slash")
            }
        }
        if let onReport = actions.onReport {
            Button(role: .destructive) {
                onReport(message)
            } label: {
                Label("Report\u{2026}", systemImage: "flag")
            }
        }
    }

    private func repostBanner(original: Message) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.2.squarepath")
                .font(.ilMono(10))
            Text("Pushed from @\(original.author.username)")
                .font(.ilMono(10))
        }
        .foregroundStyle(.secondary)
        .accessibilityLabel("Pushed from @\(original.author.username)")
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
        if !message.crossPostLocations.isEmpty {
            let names = message.crossPostLocations.map(\.displayName).joined(separator: ", ")
            parts.append("Also cross-posted to \(names)")
        }
        parts.append("\(message.digCount) digs")
        if message.repostCount > 0 {
            parts.append("\(message.repostCount) pushes")
        }
        if let replies = message.replyCount, replies > 0 {
            parts.append("\(replies) replies")
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
