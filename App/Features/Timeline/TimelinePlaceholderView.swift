// TimelinePlaceholderView
//
// Superseded by `TimelineRootView` in M1. Kept here only as a
// minimal fallback view for previews / scaffolding scenarios that do
// not have an `AppEnvironment` available. The main window dispatcher
// (`MainWindowView.SidebarDetailDispatcher`) routes the Timeline
// case to `TimelineRootView()`.

import SwiftUI

struct TimelinePlaceholderView: View {
    var body: some View {
        Text("Timeline")
            .font(.title)
            .foregroundStyle(.secondary)
    }
}
