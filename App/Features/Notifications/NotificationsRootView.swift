// NotificationsRootView
//
// M5 notifications tray (PLAN.md §1 "Notifications", §6 M5). The view
// is a thin shell over `NotificationsListViewModel`: it observes
// state, dispatches user intents, and leaves loading / error / write
// logic in the view model so unit tests cover the behavior without
// touching SwiftUI.
//
// The tray is **also** where the lazy UNUserNotifications permission
// request happens (PLAN.md §5, user-confirmed design call): we ask
// only on the first visit to this view, never at app launch. The
// `NotificationsPermissionCoordinator` records its "have we asked"
// flag in `UserDefaults` so re-launches don't re-prompt.
//
// Per decision 0003 the view consumes only `InterlinedDomain`.

import SwiftUI
import InterlinedDomain

struct NotificationsRootView: View {

    @Environment(\.appEnvironment) private var environment

    @State private var viewModel: NotificationsListViewModel?

    /// Permission coordinator for the lazy first-visit UN request.
    /// `@State` so the same instance survives view rebuilds.
    @State private var permissionCoordinator: NotificationsPermissionCoordinator?

    /// Map of pending request-row view models keyed by notification id
    /// so each `.followRequest` row in the tray keeps its own
    /// optimistic state across re-renders.
    @State private var requestRowViewModels: [String: FollowRequestRowViewModel] = [:]

    var body: some View {
        NavigationStack {
            Group {
                if let viewModel {
                    bodyContent(viewModel: viewModel)
                } else {
                    unconfiguredState
                }
            }
            .navigationTitle("Notifications")
            .toolbar {
                if let viewModel {
                    ToolbarItemGroup(placement: .primaryAction) {
                        Button {
                            Task { await viewModel.markAllRead() }
                        } label: {
                            Label("Mark All as Read", systemImage: "checkmark.circle")
                        }
                        .disabled(viewModel.unreadCount == 0)

                        Button {
                            Task { await viewModel.load() }
                        } label: {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }
                    }
                }
            }
        }
        .task {
            await bootstrap()
        }
        .onReceive(NotificationCenter.default.publisher(for: .notificationsMarkAllRead)) { _ in
            guard let viewModel else { return }
            Task { await viewModel.markAllRead() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .notificationsRefresh)) { _ in
            guard let viewModel else { return }
            Task { await viewModel.load() }
        }
    }

    // MARK: - Bootstrap

    private func bootstrap() async {
        guard let environment else { return }
        if viewModel == nil {
            let vm = NotificationsListViewModel(
                service: environment.notificationsService,
                notificationsEventBus: environment.notificationsEventBus
            )
            viewModel = vm
            await vm.load()
        }
        // Lazy UN permission request — first visit only. The
        // coordinator's `UserDefaults` flag ensures we ask exactly
        // once per machine; subsequent visits are no-ops.
        if permissionCoordinator == nil {
            let coordinator = NotificationsPermissionCoordinator()
            permissionCoordinator = coordinator
            _ = await coordinator.requestIfNeeded()
        }
    }

    // MARK: - Body sections

    @ViewBuilder
    private func bodyContent(viewModel: NotificationsListViewModel) -> some View {
        if viewModel.items.isEmpty, !viewModel.hasLoadedOnce {
            loadingState
        } else if let error = viewModel.error, viewModel.items.isEmpty {
            errorState(error: error, viewModel: viewModel)
        } else if viewModel.items.isEmpty {
            emptyState
        } else {
            list(viewModel: viewModel)
        }
    }

    @ViewBuilder
    private func list(viewModel: NotificationsListViewModel) -> some View {
        List {
            ForEach(viewModel.items) { notification in
                NotificationRowView(
                    notification: notification,
                    requestRowViewModel: requestRowViewModelIfNeeded(for: notification)
                )
                .onTapGesture {
                    if !notification.isRead {
                        Task { await viewModel.markRead(id: notification.id) }
                    }
                }
                .contextMenu {
                    if !notification.isRead {
                        Button("Mark as read") {
                            Task { await viewModel.markRead(id: notification.id) }
                        }
                    }
                }
            }
        }
        .listStyle(.inset)
        .refreshable {
            await viewModel.load()
        }
    }

    private func requestRowViewModelIfNeeded(
        for notification: InterlinedDomain.Notification
    ) -> FollowRequestRowViewModel? {
        guard case .followRequest = notification.kind,
              let actor = notification.actor,
              let environment else {
            return nil
        }
        if let existing = requestRowViewModels[notification.id] {
            return existing
        }
        let request = FollowRequest(
            id: notification.id,
            user: actor,
            createdAt: notification.createdAt
        )
        let vm = FollowRequestRowViewModel(
            request: request,
            social: environment.social,
            notificationsEventBus: environment.notificationsEventBus
        )
        requestRowViewModels[notification.id] = vm
        return vm
    }

    // MARK: - States

    private var loadingState: some View {
        VStack(spacing: 8) {
            ProgressView()
            Text("Loading notifications…")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "bell.slash")
                .font(.ilDisplay(36))
                .foregroundStyle(.secondary)
            Text("You're all caught up")
                .font(.ilSubtitle())
            Text("New activity from people you follow and lists you watch will show up here.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func errorState(
        error: Error,
        viewModel: NotificationsListViewModel
    ) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.ilDisplay(36))
                .foregroundStyle(Color.accentColor)
            Text("Couldn't load notifications")
                .font(.ilSubtitle())
            Text(error.localizedDescription)
                .font(.ilSubtitle())
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("Try again") {
                Task { await viewModel.load() }
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var unconfiguredState: some View {
        VStack(spacing: 8) {
            Image(systemName: "wrench.adjustable")
                .font(.ilDisplay(36))
                .foregroundStyle(.secondary)
            Text("Notifications unavailable")
                .font(.ilSubtitle())
            Text("AppEnvironment is not injected into the view tree.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
