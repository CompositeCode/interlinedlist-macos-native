// CrossPostResultsSheet
//
// Sheet shown after a successful post publish when the server returns
// per-platform cross-post outcomes (NW-2). Displays a status icon,
// clickable link (ok), or error code (failed) per platform.
//
// Per Decision 0003 the view imports only InterlinedDomain.

import SwiftUI
import InterlinedDomain

struct CrossPostResultsSheet: View {

    let results: [CrossPostResult]
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Post Published")
                .font(.ilTitle(18))

            VStack(alignment: .leading, spacing: 8) {
                ForEach(results, id: \.platform) { result in
                    CrossPostRow(result: result)
                }
            }

            HStack {
                Spacer()
                Button("Done", action: onDismiss)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(minWidth: 360, minHeight: 200)
    }
}

// MARK: - CrossPostRow

private struct CrossPostRow: View {
    let result: CrossPostResult

    var body: some View {
        HStack(spacing: 10) {
            statusIcon
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(platformLabel)
                    .font(.ilBody())
                    .fontWeight(.medium)
                statusDetail
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch result.status {
        case .ok:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .pending:
            Image(systemName: "clock.fill")
                .foregroundStyle(.secondary)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(Color.accentColor)
        case .unknown:
            Image(systemName: "questionmark.circle.fill")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var statusDetail: some View {
        switch result.status {
        case .ok:
            if let url = result.externalURL {
                Link("View post", destination: url)
                    .font(.ilMono(10))
            } else {
                Text("Published")
                    .font(.ilMono(10))
                    .foregroundStyle(.secondary)
            }
        case .pending:
            Text("Pending")
                .font(.ilMono(10))
                .foregroundStyle(.secondary)
        case .failed(let reason):
            Text(humanReadableError(reason))
                .font(.ilMono(10))
                .foregroundStyle(Color.accentColor)
        case .unknown(let raw):
            Text(raw)
                .font(.ilMono(10))
                .foregroundStyle(.secondary)
        }
    }

    private var platformLabel: String {
        let platform = result.platform.capitalized
        if let id = result.providerId, !id.isEmpty {
            return "\(platform) (\(id))"
        }
        return platform
    }

    private func humanReadableError(_ reason: String?) -> String {
        guard let reason else { return "Failed" }
        switch reason {
        case "rate_limited": return "Rate limited — try again later."
        case "auth_expired": return "Auth expired — re-link your account."
        case "content_policy": return "Blocked by content policy."
        default: return reason.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
}
