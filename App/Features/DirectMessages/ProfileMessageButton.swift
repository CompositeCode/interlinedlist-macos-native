// ProfileMessageButton
//
// The additive "Message" affordance embedded in `ProfileHeaderView` (the-
// gaps.md G1). Self-contained and self-gating: it owns a
// `ProfileMessageButtonViewModel`, checks recipient eligibility on
// appear, and renders *nothing* unless the profiled user is an eligible
// recipient (a mutual follower who hasn't blocked the current user). This
// keeps the header pure presentation — it simply drops the button in and
// lets the button decide whether to show.
//
// Tapping the button posts `.directMessagesShow` (route the sidebar to
// Messages) and `.directMessagesOpenThread` (select this conversation),
// reusing the same cross-scene notification channel the other features
// use so the header needs no navigation wiring.
//
// Per decision 0003, this view consumes only `InterlinedDomain`.

import SwiftUI
import InterlinedDomain

struct ProfileMessageButton: View {

    let username: String

    @Environment(\.appEnvironment) private var environment

    @State private var viewModel: ProfileMessageButtonViewModel?

    var body: some View {
        Group {
            if let viewModel, viewModel.shouldShow {
                Button {
                    NotificationCenter.default.post(name: .directMessagesShow, object: nil)
                    NotificationCenter.default.post(name: .directMessagesOpenThread, object: username)
                } label: {
                    Label("Message", systemImage: "bubble.left")
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Message @\(username)")
            }
        }
        .task(id: username) {
            guard let environment else { return }
            let vm = ProfileMessageButtonViewModel(
                username: username,
                service: environment.directMessages,
                currentUsername: { [weak environment] in
                    environment?.currentUserStore.currentUsername
                }
            )
            viewModel = vm
            await vm.check()
        }
    }
}
