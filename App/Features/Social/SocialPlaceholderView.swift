// SocialPlaceholderView
//
// Superseded by `ProfileRootView` in M1. Kept here only as a
// minimal fallback view for previews / scaffolding scenarios that do
// not have an `AppEnvironment` available. The main window dispatcher
// (`MainWindowView.SidebarDetailDispatcher`) routes the Profile case
// to `ProfileRootView()`.

import SwiftUI

struct SocialPlaceholderView: View {
    var body: some View {
        Text("Social")
            .font(.title)
            .foregroundStyle(.secondary)
    }
}
