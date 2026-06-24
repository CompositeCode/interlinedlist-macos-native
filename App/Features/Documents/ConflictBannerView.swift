// ConflictBannerView
//
// Inline banner the M4 Documents editor surfaces when the
// `DocumentSyncEngine` reports a conflict (server changed the document
// while the user had local edits in flight). Pure SwiftUI.
//
// Per the Wave 5.3 design call: "Server changed this document. Your
// local copy was saved as '<preservedAs title> (local copy)'." with
// two buttons: "Open the local copy" (selects it in the sidebar) and
// "Dismiss."

import SwiftUI
import InterlinedDomain

struct ConflictBannerView: View {

    let pending: ConflictBannerViewModel.Pending
    let onOpenLocalCopy: (Document.ID) -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
                .font(.system(size: 18))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text("Server changed this document.")
                    .font(.headline)
                Text("Your local copy was saved as “\(pending.preservedTitle) (local copy)”.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            HStack(spacing: 8) {
                Button("Open the local copy") {
                    onOpenLocalCopy(pending.preservedId)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Button("Dismiss") {
                    onDismiss()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.yellow.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.yellow.opacity(0.4), lineWidth: 1)
        )
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .accessibilityElement(children: .contain)
    }
}
