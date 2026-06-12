// SettingsPlaceholderView
//
// M0 placeholder for the native Settings scene. Real settings (Account,
// Identities, Posting defaults, Subscription) ship in M6/M7 per PLAN.md §5.

import SwiftUI

struct SettingsPlaceholderView: View {
    var body: some View {
        Form {
            Section("Account") {
                Text("Account settings will appear here.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 480, minHeight: 320)
    }
}

#Preview {
    SettingsPlaceholderView()
}
