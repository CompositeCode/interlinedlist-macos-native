// OrganizationDetailView
//
// The org detail pane (PLAN.md §1 "Organizations", §6 M6): org fields with
// an inline edit form (`OrganizationDetailViewModel`) plus a paginated
// member roster with a role editor, add-member, and remove-member
// (`OrgMembersViewModel`). Both view models read services from
// `AppEnvironment`; the view itself owns no business logic.
//
// Per decision 0003 the view consumes only `InterlinedDomain`.

import SwiftUI
import InterlinedDomain

struct OrganizationDetailView: View {

    let membership: UserOrganization

    @Environment(\.appEnvironment) private var environment

    @State private var detailViewModel: OrganizationDetailViewModel?
    @State private var membersViewModel: OrgMembersViewModel?

    var body: some View {
        Group {
            if let detailViewModel, let membersViewModel {
                content(detail: detailViewModel, members: membersViewModel)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle(membership.organization.name)
        .task {
            guard detailViewModel == nil, let environment else { return }
            let detail = OrganizationDetailViewModel(
                orgService: environment.orgService,
                orgId: membership.organization.id,
                initial: membership.organization
            )
            let members = OrgMembersViewModel(
                orgService: environment.orgService,
                orgId: membership.organization.id
            )
            detailViewModel = detail
            membersViewModel = members
            async let d: Void = detail.load()
            async let m: Void = members.load(reset: true)
            _ = await (d, m)
        }
    }

    @ViewBuilder
    private func content(
        detail: OrganizationDetailViewModel,
        members: OrgMembersViewModel
    ) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                OrganizationEditSection(viewModel: detail)
                Divider()
                MemberRosterSection(viewModel: members, canManage: membership.role.canManageMembers)
            }
            .padding(20)
        }
    }
}

// MARK: - OrganizationEditSection

private struct OrganizationEditSection: View {

    @Bindable var viewModel: OrganizationDetailViewModel

    @State private var name: String = ""
    @State private var description: String = ""
    @State private var isPublic: Bool = false
    @State private var didSeed: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Details")
                .font(.ilSubtitle())

            Form {
                TextField("Name", text: $name)
                TextField("Description", text: $description, axis: .vertical)
                    .lineLimit(2...4)
                Toggle("Public", isOn: $isPublic)
            }
            .formStyle(.grouped)
            .frame(maxHeight: 180)

            if let error = viewModel.saveError {
                Text(error.localizedDescription)
                    .font(.ilMono(10))
                    .foregroundStyle(Color.accentColor)
            }

            HStack {
                Spacer()
                Button("Save Changes") {
                    Task { _ = await viewModel.save(name: name, description: description, isPublic: isPublic) }
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isSaving || name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .onChange(of: viewModel.organization?.id) { _, _ in seedIfNeeded() }
        .onAppear { seedIfNeeded() }
    }

    private func seedIfNeeded() {
        guard !didSeed, let org = viewModel.organization else { return }
        name = org.name
        description = org.description ?? ""
        isPublic = org.isPublic
        didSeed = true
    }
}

// MARK: - MemberRosterSection

private struct MemberRosterSection: View {

    @Bindable var viewModel: OrgMembersViewModel
    let canManage: Bool

    @State private var newMemberUserId: String = ""
    @State private var newMemberRole: OrgRole = .member

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Members")
                .font(.ilSubtitle())

            if let error = viewModel.actionError {
                Text(error.localizedDescription)
                    .font(.ilMono(10))
                    .foregroundStyle(Color.accentColor)
            }

            if let error = viewModel.loadError, viewModel.members.isEmpty {
                OrgErrorState(error: error, retry: { await viewModel.load(reset: true) })
                    .frame(height: 160)
            } else if viewModel.members.isEmpty, !viewModel.isLoading {
                Text("No members yet.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(viewModel.members) { member in
                    MemberRow(
                        member: member,
                        canManage: canManage,
                        isPending: viewModel.pendingOperations.contains(member.userId),
                        onChangeRole: { role in await viewModel.changeRole(of: member, to: role) },
                        onRemove: { await viewModel.removeMember(member) }
                    )
                    .onAppear {
                        if member.userId == viewModel.members.last?.userId, viewModel.hasMore {
                            Task { await viewModel.load(reset: false) }
                        }
                    }
                    Divider()
                }
            }

            if canManage {
                addMemberRow
            }
        }
    }

    private var addMemberRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Add a member")
                .font(.ilSubtitle())
                .fontWeight(.medium)
            HStack {
                TextField("User id", text: $newMemberUserId)
                    .textFieldStyle(.roundedBorder)
                Picker("Role", selection: $newMemberRole) {
                    ForEach(OrgRole.assignableRoles, id: \.wireToken) { role in
                        Text(role.displayName).tag(role)
                    }
                }
                .labelsHidden()
                .frame(width: 120)
                Button("Add") {
                    Task {
                        if await viewModel.addMember(userId: newMemberUserId, role: newMemberRole) == nil {
                            newMemberUserId = ""
                        }
                    }
                }
                .buttonStyle(.bordered)
                .disabled(newMemberUserId.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            Text("Adding is by user id for now — there is no handle lookup yet.")
                .font(.ilMono(9))
                .foregroundStyle(.secondary)
        }
        .padding(.top, 8)
    }
}

// MARK: - MemberRow

private struct MemberRow: View {

    let member: OrgMember
    let canManage: Bool
    let isPending: Bool
    let onChangeRole: (OrgRole) async -> Void
    let onRemove: () async -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "person.crop.circle.fill")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 28, height: 28)
                .foregroundStyle(ILColor.primary.opacity(0.6))
            VStack(alignment: .leading, spacing: 2) {
                Text(member.userId)
                    .font(.ilBody())
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(member.role.displayName)
                    .font(.ilMono(10))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if isPending {
                ProgressView().controlSize(.small)
            }
            if canManage {
                Picker("Role", selection: Binding(
                    get: { roleSelection },
                    set: { newRole in Task { await onChangeRole(newRole) } }
                )) {
                    ForEach(OrgRole.assignableRoles, id: \.wireToken) { role in
                        Text(role.displayName).tag(role)
                    }
                    // Preserve an unrecognized server role as a selectable tag
                    // so the picker shows the current value rather than blank.
                    if case .other = member.role {
                        Text(member.role.displayName).tag(member.role)
                    }
                }
                .labelsHidden()
                .frame(width: 110)
                .disabled(isPending)

                Button(role: .destructive) {
                    Task { await onRemove() }
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .disabled(isPending)
            }
        }
        .padding(.vertical, 4)
    }

    private var roleSelection: OrgRole {
        member.role
    }
}

// MARK: - OrgRole management gate

extension OrgRole {
    /// Whether a member with this role can manage other members (add /
    /// remove / change roles). Owners and admins can; members and unknown
    /// roles cannot (least-privilege for `.other`).
    var canManageMembers: Bool {
        switch self {
        case .owner, .admin: return true
        case .member, .other: return false
        }
    }
}

// MARK: - Shared state stand-ins

struct OrgEmptyState: View {
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "building.2")
                .font(.ilDisplay(36))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.ilSubtitle())
            Text(message)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct OrgErrorState: View {
    let error: Error
    let retry: () async -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.ilDisplay(36))
                .foregroundStyle(Color.accentColor)
            Text("Couldn't load")
                .font(.ilSubtitle())
            Text(error.localizedDescription)
                .font(.ilSubtitle())
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("Try again") {
                Task { await retry() }
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
