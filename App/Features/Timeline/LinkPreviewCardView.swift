// LinkPreviewCardView
//
// Renders a single server-resolved rich link preview (feature-gaps §1.5)
// as a tappable card: an AsyncImage thumbnail (when the server resolved
// one), the preview title, and the link's host. The whole card is a
// button that opens the URL via the SwiftUI `@Environment(\.openURL)`
// action — no AppKit / `NSWorkspace`, honouring the App target's
// SwiftUI-only constraint.
//
// The "is this worth showing?" decision lives in the domain
// (`LinkPreview.isRenderable`), not here — the view stays passive and
// simply reflects a value that already passed that gate. Styling matches
// the surrounding timeline card theme (ILColor / ILFont / ILMetric).

import SwiftUI
import InterlinedDomain

struct LinkPreviewCardView: View {

    let preview: LinkPreview

    @Environment(\.openURL) private var openURL

    var body: some View {
        Button {
            openURL(preview.url)
        } label: {
            cardBody
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Opens the link in your browser")
        .accessibilityAddTraits(.isLink)
    }

    private var cardBody: some View {
        HStack(alignment: .top, spacing: 10) {
            if let imageURL = preview.imageURL {
                thumbnail(imageURL)
            }
            VStack(alignment: .leading, spacing: 3) {
                if let title = trimmedTitle {
                    Text(title)
                        .font(.ilBodyMedium())
                        .foregroundStyle(ILColor.text)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(preview.displayHost)
                    .font(.ilMono(10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(ILColor.surface2, in: RoundedRectangle(cornerRadius: ILMetric.radiusLg))
        .overlay(
            RoundedRectangle(cornerRadius: ILMetric.radiusLg)
                .strokeBorder(ILColor.primary.opacity(0.15), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: ILMetric.radiusLg))
    }

    private func thumbnail(_ url: URL) -> some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            case .failure:
                placeholderGlyph
            case .empty:
                // Loading — keep the slot sized so the layout doesn't jump.
                Color.clear
            @unknown default:
                placeholderGlyph
            }
        }
        .frame(width: 56, height: 56)
        .clipShape(RoundedRectangle(cornerRadius: ILMetric.radiusMd))
        .accessibilityHidden(true)
    }

    private var placeholderGlyph: some View {
        Image(systemName: "link")
            .foregroundStyle(.secondary)
    }

    /// The title with surrounding whitespace removed, or `nil` when the server
    /// sent no title or a whitespace-only one — so the card renders host-only
    /// rather than an empty title line.
    private var trimmedTitle: String? {
        guard let title = preview.title?.trimmingCharacters(in: .whitespacesAndNewlines),
              !title.isEmpty else { return nil }
        return title
    }

    private var accessibilityLabel: String {
        if let title = trimmedTitle {
            return "Link preview: \(title), \(preview.displayHost)"
        }
        return "Link: \(preview.displayHost)"
    }
}
