// FollowButton
//
// Renders the M5 follow button against `FollowButtonViewModel`
// (PLAN.md §1 "Follow system", §6 M5). Pure presentation: the view
// reads `relationship.state` and dispatches `tap()` to the view model
// — every state transition, optimistic flip, and rollback lives in
// `FollowButtonViewModel.swift`.
//
// View states (mirror the view model):
//   - `nil` view model         → render nothing.
//   - `isSelf == true`         → render nothing (self-profile).
//   - `relationship == nil`    → render nothing (initial load in
//                                 flight; the empty space avoids a
//                                 flicker of "Follow" before we know).
//   - `.notFollowing`          → bordered prominent "Follow" button.
//   - `.pending`               → bordered greyed "Requested" button.
//   - `.following`             → bordered "Following" button, hover
//                                 swaps the label to "Unfollow".
//
// Per decision 0003 (App-layer Kit-import policy), this view imports
// only `SwiftUI` and `InterlinedDomain`.

import SwiftUI
import InterlinedDomain

struct FollowButton: View {

    @Bindable var viewModel: FollowButtonViewModel
    @State private var isHovering: Bool = false

    var body: some View {
        Group {
            if viewModel.isSelf {
                EmptyView()
            } else if let relationship = viewModel.relationship {
                button(for: relationship.state)
            } else {
                EmptyView()
            }
        }
    }

    @ViewBuilder
    private func button(for state: FollowRelationship.State) -> some View {
        switch state {
        case .notFollowing:
            Button {
                Task { await viewModel.tap() }
            } label: {
                buttonLabel(text: "Follow")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .disabled(viewModel.isMutating)
            .accessibilityLabel("Follow user")

        case .pending:
            // Tap is a no-op until the request is approved or rejected
            // server-side. The button stays visible (greyed) so the
            // user sees what their last action was.
            Button {
                Task { await viewModel.tap() }
            } label: {
                buttonLabel(text: "Requested")
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .disabled(true)
            .accessibilityLabel("Follow request pending")

        case .following:
            Button {
                Task { await viewModel.tap() }
            } label: {
                buttonLabel(text: isHovering ? "Unfollow" : "Following")
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .tint(isHovering ? .red : .accentColor)
            .disabled(viewModel.isMutating)
            .onHover { hovering in
                isHovering = hovering
            }
            .accessibilityLabel(isHovering ? "Unfollow user" : "Following user")
        }
    }

    @ViewBuilder
    private func buttonLabel(text: String) -> some View {
        HStack(spacing: 4) {
            if viewModel.isMutating {
                ProgressView()
                    .controlSize(.small)
            }
            Text(text)
        }
        .frame(minWidth: 80)
    }
}
