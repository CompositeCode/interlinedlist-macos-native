// AccountStatusBanner
//
// The home-timeline banner that explains a limited account (GitHub #42).
//
// `/help/account`: "When your account is new or locked, a banner at the top of
// your home page explains the current status and, where relevant, links you to
// verify your email or to contact support."
//
// The banner renders nothing for an `active` account, and nothing for an
// unrecognised status — an unknown value must never scare a user with a
// warning the client cannot explain. `banned` never reaches here either: a
// banned account cannot sign in, so it is a sign-in failure path.
//
// Decision 0003: consumes `InterlinedDomain` only.

import SwiftUI
import InterlinedDomain

struct AccountStatusBanner: View {

    let status: AccountStatus
    let isEmailVerified: Bool

    @Environment(\.openURL) private var openURL

    var body: some View {
        if status.warrantsBanner {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: iconName)
                    .foregroundStyle(tint)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.callout.weight(.semibold))
                    Text(explanation)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                if let action {
                    Button(action.title) {
                        openURL(action.destination.url())
                    }
                    .buttonStyle(.link)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(tint.opacity(0.10))
            .overlay(alignment: .bottom) { Divider() }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(title). \(explanation)")
        }
    }

    // MARK: - Copy

    private var title: String {
        switch status {
        case .new: return "Your account is new"
        case .restricted: return "Your account is temporarily read-only"
        case .suspended: return "Your account is suspended"
        case .active, .banned, .unknown: return ""
        }
    }

    private var explanation: String {
        switch status {
        case .new:
            // Posting works but is rate-limited, so the copy must not imply the
            // user cannot post at all.
            return isEmailVerified
                ? "Posting is limited while your account is reviewed. Direct messages, media, "
                    + "cross-posting, scheduling, and creating lists, documents, and organizations "
                    + "unlock once it is active."
                : "Posting is limited while your account is new. Verifying your email is the "
                    + "fastest way to unlock direct messages, media, cross-posting, scheduling, "
                    + "and creating lists, documents, and organizations."
        case .restricted:
            return "You can read and browse as usual. Posting, replying, reacting, following, "
                + "messaging, and creating content are paused while your account is reviewed."
        case .suspended:
            return "You can read and browse as usual. If you think this is a mistake, you can appeal."
        case .active, .banned, .unknown:
            return ""
        }
    }

    /// The next step, mirroring the web: verify email for a new account,
    /// contact support for a locked one.
    private var action: (title: String, destination: AccountWebDestination)? {
        switch status {
        case .new:
            // Nothing useful to offer once the email is already verified — the
            // remaining wait is the platform's own review.
            return isEmailVerified ? nil : ("Verify email", .settings)
        case .restricted, .suspended:
            return ("Contact support", .support)
        case .active, .banned, .unknown:
            return nil
        }
    }

    private var iconName: String {
        switch status {
        case .new: return "clock.badge.checkmark"
        case .restricted, .suspended: return "exclamationmark.triangle.fill"
        case .active, .banned, .unknown: return "info.circle"
        }
    }

    private var tint: Color {
        switch status {
        case .new: return .accentColor
        case .restricted, .suspended: return .orange
        case .active, .banned, .unknown: return .secondary
        }
    }
}
