// DMAttachmentStrip
//
// The pending-photo row shared by the DM thread composer and the new-message
// sheet (work-consolidation.md G22). Renders each queued local file as a
// thumbnail with a remove affordance, plus an "n of 8" counter so the
// documented cap is visible before the user hits it.
//
// SwiftUI-only (Decision 0005): `AsyncImage(url:)` over the local file URL,
// no AppKit image loading.
//
// Per decision 0003, this view consumes only `InterlinedDomain`.

import SwiftUI
import InterlinedDomain

struct DMAttachmentStrip: View {

    let attachments: [ComposerAttachment]
    let limit: Int
    let onRemove: (ComposerAttachment.ID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Photos")
                    .font(.ilMono(10))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(attachments.count) of \(limit)")
                    .font(.ilMono(10))
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("\(attachments.count) of \(limit) photos attached")
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(attachments) { attachment in
                        thumbnail(attachment)
                    }
                }
            }
        }
    }

    private func thumbnail(_ attachment: ComposerAttachment) -> some View {
        AsyncImage(url: attachment.url) { phase in
            switch phase {
            case .success(let image):
                image.resizable().aspectRatio(contentMode: .fill)
            default:
                Image(systemName: "photo")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 56, height: 56)
        .clipShape(RoundedRectangle(cornerRadius: ILMetric.radiusSm))
        .overlay(alignment: .topTrailing) {
            Button {
                onRemove(attachment.id)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.white, .black.opacity(0.6))
            }
            .buttonStyle(.plain)
            .padding(2)
            .accessibilityLabel("Remove photo")
        }
        .accessibilityLabel("Attached photo \(attachment.url.lastPathComponent)")
    }
}
