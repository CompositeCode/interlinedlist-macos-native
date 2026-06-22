// ListsPlaceholderView
//
// Superseded by `ListsBrowserView` in M1. Kept here only as a
// minimal fallback view for previews / scaffolding scenarios that do
// not have an `AppEnvironment` available. The main window dispatcher
// (`MainWindowView.SidebarDetailDispatcher`) routes the Lists case
// to `ListsBrowserView()`.

import SwiftUI

struct ListsPlaceholderView: View {
    var body: some View {
        Text("Lists")
            .font(.title)
            .foregroundStyle(.secondary)
    }
}
