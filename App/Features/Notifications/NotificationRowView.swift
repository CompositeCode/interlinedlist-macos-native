// NotificationRowView
//
// Renders one notification row in the M5 tray (PLAN.md §1
// "Notifications", §6 M5). Pure presentation: the kind-specific copy
// and SF Symbol come from `NotificationRowCopy`, the inline approve /
// reject affordances for `followRequest` rows render a
// `FollowRequestRow` over the same `FollowRequestRowViewModel` used
// by the dedicated Requests panel.
//
// Per decision 0003, this view consumes only `InterlinedDomain`.

import SwiftUI
import InterlinedDomain

struct NotificationRowView: View {

    let notification: InterlinedDomain.Notification

    /// Optional inline action handlers — present only on the tray
    /// view when the row is a `.followRequest` and the App layer
    /// passed a row view model. Other kinds render their action via
    /// the row tap (deep-link routing) and don't need extra
    /// affordances.
    let requestRowViewModel: FollowRequestRowViewModel?

    init(
        notification: InterlinedDomain.Notification,
        requestRowViewModel: FollowRequestRowViewModel? = nil
    ) {
        self.notification = notification
        self.requestRowViewModel = requestRowViewModel
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            unreadIndicator
            Image(systemName: NotificationRowCopy.symbol(for: notification.kind))
                .font(.title3)
                .foregroundStyle(.accent)
                .frame(width: 24)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(NotificationRowCopy.copy(
                    for: notification.kind,
                    actor: notification.actor,
                    title: notification.title,
                    body: notification.body
                ))
                .font(.ilBody())
                .fontWeight(notification.isRead ? .regular : .semibold)
                .fixedSize(horizontal: false, vertical: true)

                if let body = notification.body, notification.title != nil, !body.isEmpty {
                    // When the server sent both a title and a body,
                    // the title above is the prominent line; render
                    // the body as the supporting detail.
                    Text(body)
                        .font(.ilBody(14))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let createdAt = notification.createdAt {
                    Text(createdAt, format: .relative(presentation: .named))
                        .font(.ilMono(10))
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            if let requestRowViewModel,
               case .followRequest = notification.kind {
                inlineRequestActions(viewModel: requestRowViewModel)
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .contain)
    }

    // MARK: - Subviews

    @ViewBuilder
    private var unreadIndicator: some View {
        Circle()
            .fill(notification.isRead ? Color.clear : Color.accentColor)
            .frame(width: 8, height: 8)
            .padding(.top, 6)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private func inlineRequestActions(viewModel: FollowRequestRowViewModel) -> some View {
        switch viewModel.outcome {
        case .undecided:
            HStack(spacing: 6) {
                Button("Reject") {
                    Task { await viewModel.reject() }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(viewModel.isMutating)

                Button("Approve") {
                    Task { await viewModel.approve() }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(viewModel.isMutating)
            }
        case .approved:
            Label("Approved", systemImage: "checkmark.circle.fill")
                .font(.ilMono(10))
                .foregroundStyle(ILColor.primary)
        case .rejected:
            Label("Rejected", systemImage: "xmark.circle.fill")
                .font(.ilMono(10))
                .foregroundStyle(.secondary)
        }
    }
}
