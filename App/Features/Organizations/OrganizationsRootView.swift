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

    @Environment(\.appEnvironment) private var environment

    @State private var viewModel: OrganizationsListViewModel?
    @State private var selection: UserOrganization?
    @State private var showCreateSheet: Bool = false

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
                if viewModel != nil {
                    ToolbarItem(placement: .primaryAction) {
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
            guard viewModel == nil, let environment else { return }
            // Ownership-gate: no session → no "my orgs".
            guard environment.currentUserStore.currentUserID != nil else { return }
            let vm = OrganizationsListViewModel(
                orgService: environment.orgService,
                userService: environment.userService
            )
            viewModel = vm
            await vm.load()
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
                    OrgRowView(membership: membership)
                }
            }
            .listStyle(.inset)
            .navigationDestination(for: UserOrganization.self) { membership in
                OrganizationDetailView(membership: membership)
            }
            .refreshable { await viewModel.load() }
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

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "building.2.crop.circle.fill")
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
                    if membership.organization.isPublic {
                        Text("Public")
                            .font(.ilMono(9))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Color.secondary.opacity(0.15), in: Capsule())
                    }
                }
            }
            Spacer()
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(rowAccessibilityLabel)
    }

    private var rowAccessibilityLabel: String {
        let visibility = membership.organization.isPublic ? ", public" : ""
        return "\(membership.organization.name), \(membership.role.displayName)\(visibility)"
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
