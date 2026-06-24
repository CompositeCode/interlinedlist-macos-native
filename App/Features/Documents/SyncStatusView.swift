// SyncStatusView
//
// Toolbar status indicator + manual "Sync Now" button for the M4
// Documents feature (PLAN.md §6 M4). Pure SwiftUI — no AppKit.
//
// Renders the `SyncStatusViewModel.state` as either:
//   - Idle          — neutral cloud glyph
//   - Syncing       — spinning `ProgressView`
//   - Last synced N — relative date in the system locale
//   - Failed        — exclamation glyph with the error string as a
//                     tooltip / accessibility label

import SwiftUI

struct SyncStatusView: View {

    let viewModel: SyncStatusViewModel

    var body: some View {
        HStack(spacing: 6) {
            statusGlyph
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .help(helpText)
    }

    @ViewBuilder
    private var statusGlyph: some View {
        switch viewModel.state {
        case .idle:
            Image(systemName: "cloud")
                .foregroundStyle(.secondary)
        case .syncing:
            ProgressView()
                .controlSize(.small)
        case .lastSynced:
            Image(systemName: "checkmark.circle")
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.red)
        }
    }

    private var label: String {
        switch viewModel.state {
        case .idle:
            return "Not synced yet"
        case .syncing:
            return "Syncing…"
        case .lastSynced(let date):
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .short
            return "Synced \(formatter.localizedString(for: date, relativeTo: Date()))"
        case .failed:
            return "Sync failed"
        }
    }

    private var accessibilityLabel: String {
        switch viewModel.state {
        case .failed(let message): return "Sync failed: \(message)"
        default: return label
        }
    }

    private var helpText: String {
        switch viewModel.state {
        case .failed(let message): return message
        default: return label
        }
    }
}
