// DMAvatarView
//
// Small circular avatar used across the Direct Messages surfaces (the-
// gaps.md G1) — conversation rows, the thread header, and the recipient
// picker. Mirrors the `AsyncImage` + SF-Symbol fallback pattern used by
// `BlockedAndMutedView` / `ProfileHeaderView` so DM avatars look identical
// to their home surfaces. Pure presentation.
//
// Per decision 0003, this view consumes only `InterlinedDomain`.

import SwiftUI
import InterlinedDomain

struct DMAvatarView: View {
    let user: UserSummary?
    var size: CGFloat = 32

    var body: some View {
        AsyncImage(url: user?.avatarURL) { phase in
            switch phase {
            case .success(let image):
                image.resizable().aspectRatio(contentMode: .fill)
            default:
                Image(systemName: "person.crop.circle.fill")
                    .resizable()
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }
}
