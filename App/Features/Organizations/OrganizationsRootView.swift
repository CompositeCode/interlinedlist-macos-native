// OrganizationsRootView
//
// The Organizations sidebar destination (PLAN.md §1 "Organizations",
// §5 sidebar, §6 M6). A master list of the signed-in user's
// organizations with a create-org affordance, navigating to a detail
// pane (`OrganizationDetailView`) that shows org fields, edit, and the
// member roster.
//
// The view is a thin shell over `OrganizationsListViewModel`: it observes
// state and dispatches intents, leaving loading / error / write logic in
// the view model so unit tests cover the behavior without touching SwiftUI.
//
// When no session has resolved yet (current user id is nil per the M2
// ownership-gating rule) the view renders an explanatory empty state —
// "my organizations" for an unknown user is meaningless.
//
// Per decision 0003 the view consumes only `InterlinedDomain`.

import SwiftUI
import InterlinedDomain

struct OrganizationsRootView: View {

    /// Pre-warmed view model supplied by `MainWindowView` via the launch
    /// coordinator. When non-nil the view skips creation and its cache-first
    /// initial load; a re-appearance still honors the freshness TTL.
    var preloadedViewModel: OrganizationsListViewModel? = nil

    @Environment(\.appEnvironment) private var environment

    @State private var viewModel: OrganizationsListViewModel?
    @State private var selection: UserOrganization?
    @State private var showCreateSheet: Bool = false
    @State private var showJoinSheet: Bool = false
    /// The membership awaiting a Leave confirmation, if any.
    @State private var pendingLeave: UserOrganization?
    /// The membership awaiting a Delete confirmation, if any. Delete is not
    /// reversible, so it gets its own confirmation that names the org.
    @State private var pendingDelete: UserOrganization?

    var body: some View {
        NavigationStack {
            Group {
                if let viewModel {
                    body(viewModel: viewModel)
                } else {
                    unconfiguredState
                }
            }
            .navigationTitle("Organizations")
            .toolbar {
                if let viewModel {
                    ToolbarItemGroup(placement: .primaryAction) {
                        // Stale-while-revalidate: a subtle spinner while a
                        // background refresh runs over cached memberships
                        // already on screen.
                        if viewModel.isRefreshing {
                            ProgressView()
                                .controlSize(.small)
                                .help("Refreshing organizations…")
                        }
                        Button {
                            showJoinSheet = true
                        } label: {
                            Label("Browse Organizations", systemImage: "magnifyingglass")
                        }
                        .help("Find a public organization to join")
                        Button {
                            showCreateSheet = true
                        } label: {
                            Label("New Organization", systemImage: "plus")
                        }
                    }
                }
            }
        }
        .task {
            guard let environment else { return }
            if viewModel == nil {
                if let preloaded = preloadedViewModel {
                    // Pre-warmed by the launch coordinator — its cache-first
                    // load is already in flight / done; don't refetch here.
                    viewModel = preloaded
                    return
                }
                // Ownership-gate: no session → no "my orgs".
                guard environment.currentUserStore.currentUserID != nil else { return }
                let vm = OrganizationsListViewModel(
                    orgService: environment.orgService,
                    userService: environment.userService,
                    // Leaving an org is removing yourself from its members,
                    // so the list needs to know who "yourself" is.
                    currentUserId: environment.currentUserStore.currentUserID
                )
                viewModel = vm
                await vm.load()
            } else if let vm = viewModel, vm.shouldRefresh {
                // Re-appearance past the freshness TTL — revalidate; within
                // the TTL we trust the cache and skip the network.
                await vm.load()
            }
        }
        .sheet(isPresented: $showJoinSheet) {
            if let viewModel {
                BrowseOrganizationsSheet(listViewModel: viewModel)
            }
        }
        .sheet(isPresented: $showCreateSheet) {
            if let viewModel, let environment {
                CreateOrganizationSheet(listViewModel: viewModel) { created in
                    // Navigate straight to the new org.
                    selection = UserOrganization(
                        organization: created,
                        role: .owner,
                        joinedAt: created.createdAt
                    )
                }
                .environment(\.appEnvironment, environment)
            }
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private func body(viewModel: OrganizationsListViewModel) -> some View {
        if let error = viewModel.loadError, viewModel.memberships.isEmpty {
            OrgErrorState(error: error, retry: { await viewModel.load() })
        } else if viewModel.memberships.isEmpty, !viewModel.isLoading {
            OrgEmptyState(
                title: "No organizations yet",
                message: "Create an organization to manage members and shared lists.",
                actionTitle: "Create Organization",
                action: { showCreateSheet = true }
            )
        } else {
            List(viewModel.memberships, selection: $selection) { membership in
                NavigationLink(value: membership) {
                    OrgRowView(
                        membership: membership,
                        isPending: viewModel.pendingOperations.contains(membership.organization.id)
                    )
                }
                .contextMenu {
                    // Ownership-gated actions are hidden, not disabled, when
                    // they don't apply (PLAN.md §6 M2 rule).
                    if viewModel.canLeave(membership) {
                        Button("Leave \(membership.organization.name)") {
                            pendingLeave = membership
                        }
                    }
                    if viewModel.canDelete(membership) {
                        Button("Delete \(membership.organization.name)…", role: .destructive) {
                            pendingDelete = membership
                        }
                    }
                }
            }
            .listStyle(.inset)
            .navigationDestination(for: UserOrganization.self) { membership in
                OrganizationDetailView(membership: membership)
            }
            .refreshable { await viewModel.load() }
            .overlay(alignment: .bottom) {
                if let error = viewModel.actionError {
                    Text(error.localizedDescription)
                        .font(.ilMono(10))
                        .foregroundStyle(Color.accentColor)
                        .padding(8)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
                        .padding(8)
                        .accessibilityLabel("Organization action failed: \(error.localizedDescription)")
                }
            }
            .confirmationDialog(
                "Leave \(pendingLeave?.organization.name ?? "this organization")?",
                isPresented: Binding(
                    get: { pendingLeave != nil },
                    set: { if !$0 { pendingLeave = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Leave", role: .destructive) {
                    if let membership = pendingLeave {
                        pendingLeave = nil
                        Task { await viewModel.leave(membership) }
                    }
                }
                Button("Cancel", role: .cancel) { pendingLeave = nil }
            } message: {
                Text("You'll lose access to this organization's shared content. You can rejoin later if it's public.")
            }
            .confirmationDialog(
                "Delete \(pendingDelete?.organization.name ?? "this organization")?",
                isPresented: Binding(
                    get: { pendingDelete != nil },
                    set: { if !$0 { pendingDelete = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Delete Organization", role: .destructive) {
                    if let membership = pendingDelete {
                        pendingDelete = nil
                        Task { await viewModel.delete(membership) }
                    }
                }
                Button("Cancel", role: .cancel) { pendingDelete = nil }
            } message: {
                // Name the org and say plainly that it cannot be undone.
                Text("This permanently deletes \(pendingDelete?.organization.name ?? "the organization") and removes every member. This can't be undone.")
            }
        }
    }

    private var unconfiguredState: some View {
        VStack(spacing: 8) {
            Image(systemName: "building.2")
                .font(.ilDisplay(36))
                .foregroundStyle(.secondary)
            Text("Sign in to see your organizations")
                .font(.ilSubtitle())
            Text("Organizations you belong to appear here once you're signed in.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - OrgRowView

private struct OrgRowView: View {
    let membership: UserOrganization
    var isPending: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: membership.organization.isSystem
                  ? "globe"
                  : "building.2.crop.circle.fill")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 28, height: 28)
                .foregroundStyle(ILColor.primary.opacity(0.7))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(membership.organization.name)
                    .font(.ilBody())
                    .fontWeight(.medium)
                HStack(spacing: 6) {
                    Text(membership.role.displayName)
                        .font(.ilMono(10))
                        .foregroundStyle(.secondary)
                    if let count = membership.organization.memberCount {
                        Text(count == 1 ? "1 member" : "\(count) members")
                            .font(.ilMono(10))
                            .foregroundStyle(.secondary)
                    }
                    if let joined = membership.joinedAt {
                        Text("joined \(joined.formatted(date: .abbreviated, time: .omitted))")
                            .font(.ilMono(10))
                            .foregroundStyle(.secondary)
                    }
                    if membership.organization.isPublic {
                        Text("Public")
                            .font(.ilMono(9))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Color.secondary.opacity(0.15), in: Capsule())
                    }
                    if membership.organization.isSystem {
                        // Explains up front why this row has no Leave action.
                        Text("System")
                            .font(.ilMono(9))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Color.secondary.opacity(0.15), in: Capsule())
                    }
                }
            }
            Spacer()
            if isPending {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Updating organization")
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(rowAccessibilityLabel)
    }

    private var rowAccessibilityLabel: String {
        var parts = [membership.organization.name, membership.role.displayName]
        if let count = membership.organization.memberCount {
            parts.append(count == 1 ? "1 member" : "\(count) members")
        }
        if let joined = membership.joinedAt {
            parts.append("joined \(joined.formatted(date: .abbreviated, time: .omitted))")
        }
        if membership.organization.isPublic { parts.append("public") }
        if membership.organization.isSystem { parts.append("system organization, can't be left") }
        return parts.joined(separator: ", ")
    }
}

// MARK: - BrowseOrganizationsSheet

/// Find and join a public organization.
///
/// Joining is free for every account — only *creating* an org is
/// subscriber-gated — so nothing here is entitlement-gated.
private struct BrowseOrganizationsSheet: View {

    @Bindable var listViewModel: OrganizationsListViewModel

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Browse Organizations")
                .font(.ilSubtitle())
                .padding([.top, .horizontal], 20)

            Group {
                if listViewModel.isBrowsing, listViewModel.browsableOrganizations.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = listViewModel.browseError,
                          listViewModel.browsableOrganizations.isEmpty {
                    OrgErrorState(error: error, retry: { await listViewModel.browse() })
                } else if listViewModel.browsableOrganizations.isEmpty {
                    Text("You already belong to every public organization.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(listViewModel.browsableOrganizations) { org in
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(org.name)
                                    .font(.ilBody())
                                if let description = org.description, !description.isEmpty {
                                    Text(description)
                                        .font(.ilMono(10))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                            }
                            Spacer()
                            if listViewModel.pendingOperations.contains(org.id) {
                                ProgressView().controlSize(.small)
                            } else {
                                Button("Join") {
                                    Task { await listViewModel.join(organizationId: org.id) }
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .listStyle(.inset)
                }
            }
            .frame(height: 320)

            if let error = listViewModel.actionError {
                Text(error.localizedDescription)
                    .font(.ilMono(10))
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 20)
            }

            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
            }
            .padding(20)
        }
        .frame(width: 460)
        .task { await listViewModel.browse() }
    }
}

// MARK: - CreateOrganizationSheet

private struct CreateOrganizationSheet: View {

    @Bindable var listViewModel: OrganizationsListViewModel
    let onCreated: (Organization) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var description: String = ""
    @State private var isPublic: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("New Organization")
                .font(.ilSubtitle())
                .padding([.top, .horizontal], 20)

            Form {
                TextField("Name", text: $name)
                TextField("Description", text: $description, axis: .vertical)
                    .lineLimit(2...4)
                Toggle("Public", isOn: $isPublic)
            }
            .formStyle(.grouped)

            if let error = listViewModel.createError {
                Text(error.localizedDescription)
                    .font(.ilMono(10))
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 20)
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Create") {
                    Task {
                        if let created = await listViewModel.create(
                            name: name,
                            description: description,
                            isPublic: isPublic
                        ) {
                            onCreated(created)
                            dismiss()
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(listViewModel.isCreating || name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(20)
        }
        .frame(width: 420)
    }
}
