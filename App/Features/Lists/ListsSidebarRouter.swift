// ListsSidebarRouter
//
// Decides which Lists root to show in the `.lists` sidebar route:
// the M3 `OwnedListsRootView` for signed-in users, or the M1
// `ListsBrowserView` for signed-out / not-yet-resolved sessions.
//
// Ownership gating uses the `CurrentUserStore.currentUserID`
// signal directly — a `nil` user means "no signed-in account"
// (PLAN.md §6 M2 rule: nil current-user id is the "hidden" signal).

import SwiftUI

struct ListsSidebarRouter: View {

    @Environment(\.appEnvironment) private var environment

    var preloadedViewModel: OwnedListsViewModel? = nil

    var body: some View {
        Group {
            if let environment, environment.currentUserStore.currentUserID != nil {
                OwnedListsRootView(preloadedViewModel: preloadedViewModel)
            } else {
                ListsBrowserView()
            }
        }
    }
}
