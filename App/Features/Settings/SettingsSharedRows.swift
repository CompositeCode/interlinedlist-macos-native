// SettingsSharedRows
//
// Two small presentational helpers shared by the Settings-cluster panes
// (work-consolidation.md G17-G20) so each pane renders "unavailable" and
// "something failed" the same way.
//
// SwiftUI-only; no domain or kit types beyond `Error`.

import SwiftUI

/// Shown when a pane's backing service is not configured in this build.
struct SettingsUnavailableView: View {
    let title: String
    let message: String

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: "gearshape.badge.xmark")
        } description: {
            Text(message)
        }
    }
}

/// A compact inline error row. Uses the friendly message when the error carries
/// one, falling back to the localized description.
struct SettingsErrorRow: View {
    let error: Error

    var body: some View {
        Label(error.localizedDescription, systemImage: "exclamationmark.triangle")
            .foregroundStyle(.red)
            .font(.callout)
            .accessibilityLabel("Error: \(error.localizedDescription)")
    }
}
