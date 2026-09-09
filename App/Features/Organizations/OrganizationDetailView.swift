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
    @State private var linkedInViewModel: OrgLinkedInViewModel?

    var body: some View {
        Group {
            if let detailViewModel, let membersViewModel, let linkedInViewModel {
                content(detail: detailViewModel, members: membersViewModel, linkedIn: linkedInViewModel)
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
                userService: environment.userService,
                orgId: membership.organization.id
            )
            let linkedIn = OrgLinkedInViewModel(
                orgService: environment.orgService,
                orgId: membership.organization.id,
                membershipRole: membership.role
            )
            detailViewModel = detail
            membersViewModel = members
            linkedInViewModel = linkedIn
            async let d: Void = detail.load()
            async let m: Void = members.load(reset: true)
            async let l: Void = linkedIn.load()
            _ = await (d, m, l)
        }
    }

    @ViewBuilder
    private func content(
        detail: OrganizationDetailViewModel,
        members: OrgMembersViewModel,
        linkedIn: OrgLinkedInViewModel
    ) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                OrganizationEditSection(viewModel: detail)
                Divider()
                MemberRosterSection(
                    viewModel: members,
                    linkedIn: linkedIn,
                    canManage: membership.role.canManageMembers
                )
                Divider()
                OrgLinkedInSection(viewModel: linkedIn, members: members)
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
    @Bindable var linkedIn: OrgLinkedInViewModel
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
                        canSuspend: viewModel.canSuspend(member),
                        canRemove: viewModel.canRemove(member),
                        assignedPageName: linkedIn.assignedPage(for: member.userId)?.name,
                        onChangeRole: { role in await viewModel.changeRole(of: member, to: role) },
                        onSetSuspended: { suspended in await viewModel.setSuspended(member, suspended: suspended) },
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
                TextField("@handle", text: $newMemberUserId)
                    .textFieldStyle(.roundedBorder)
                Picker("Role", selection: $newMemberRole) {
                    ForEach(OrgRole.assignableRoles, id: \.wireToken) { role in
                        Text(role.displayName).tag(role)
                    }
                }
                .labelsHidden()
                .frame(width: 120)
                Button(viewModel.foundUser == nil ? "Search" : "Add") {
                    Task {
                        if viewModel.foundUser == nil {
                            await viewModel.lookupUser(handle: newMemberUserId)
                        } else if let user = viewModel.foundUser {
                            if await viewModel.addMember(userId: user.id, role: newMemberRole) == nil {
                                newMemberUserId = ""
                            }
                        }
                    }
                }
                .buttonStyle(.bordered)
                .disabled(newMemberUserId.trimmingCharacters(in: .whitespaces).isEmpty
                          || viewModel.isLookingUp
                          || viewModel.pendingOperations.contains(viewModel.foundUser?.id ?? ""))
            }
            if viewModel.isLookingUp {
                ProgressView()
                    .controlSize(.small)
            }
            if let found = viewModel.foundUser {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .imageScale(.small)
                    Text(found.displayName ?? found.username)
                        .font(.ilMono(10))
                    Text("(@\(found.username))")
                        .font(.ilMono(10))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.top, 8)
    }
}

// MARK: - MemberRow

private struct MemberRow: View {

    let member: OrgMember
    let canManage: Bool
    let isPending: Bool
    /// False when the last-owner rule forbids suspending this member.
    let canSuspend: Bool
    /// False when the last-owner rule forbids removing this member.
    let canRemove: Bool
    /// The org LinkedIn company page assigned to this member, if any. Shown
    /// on the row because an assignment changes where the member's ordinary
    /// LinkedIn cross-posts land.
    let assignedPageName: String?
    let onChangeRole: (OrgRole) async -> Void
    let onSetSuspended: (Bool) async -> Void
    let onRemove: () async -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "person.crop.circle.fill")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 28, height: 28)
                .foregroundStyle(ILColor.primary.opacity(member.isSuspended ? 0.25 : 0.6))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    // The roster now carries real identity, so show the name
                    // rather than the raw user id.
                    Text(member.displayLabel)
                        .font(.ilBody())
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(member.isSuspended ? .secondary : .primary)
                    if member.isSuspended {
                        Text("Suspended")
                            .font(.ilMono(9))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Color.secondary.opacity(0.18), in: Capsule())
                    }
                }
                HStack(spacing: 6) {
                    Text(member.role.displayName)
                        .font(.ilMono(10))
                        .foregroundStyle(.secondary)
                    if let username = member.username {
                        Text("@\(username)")
                            .font(.ilMono(10))
                            .foregroundStyle(.secondary)
                    }
                    if let assignedPageName {
                        Text("posts as \(assignedPageName)")
                            .font(.ilMono(10))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
            if isPending {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Updating member")
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
                .accessibilityLabel("Role for \(member.displayLabel)")

                // Suspend / restore: keeps the member in the org but revokes
                // access (`/help/organizations`). Restoring is never blocked;
                // suspending the last owner is.
                Button {
                    Task { await onSetSuspended(!member.isSuspended) }
                } label: {
                    Image(systemName: member.isSuspended ? "play.circle" : "pause.circle")
                }
                .buttonStyle(.borderless)
                .disabled(isPending || (!member.isSuspended && !canSuspend))
                .help(member.isSuspended
                      ? "Restore this member's access"
                      : (canSuspend
                         ? "Suspend this member's access"
                         : "The last owner can't be suspended"))
                .accessibilityLabel(member.isSuspended
                                    ? "Restore access for \(member.displayLabel)"
                                    : "Suspend access for \(member.displayLabel)")

                Button(role: .destructive) {
                    Task { await onRemove() }
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .disabled(isPending || !canRemove)
                .help(canRemove
                      ? "Remove from organization"
                      : "The last owner can't be removed")
                .accessibilityLabel("Remove \(member.displayLabel) from organization")
            }
        }
        .padding(.vertical, 4)
    }

    private var roleSelection: OrgRole {
        member.role
    }
}

// MARK: - OrgLinkedInSection

/// The organization's shared LinkedIn credential, its company pages, and the
/// per-member page assignments (work-consolidation.md G25).
///
/// Visible to everyone (a member should be able to see that the org has a
/// shared credential and which page they post as), but only owners and admins
/// get the connect / sync / assign / disconnect controls.
private struct OrgLinkedInSection: View {

    @Bindable var viewModel: OrgLinkedInViewModel
    @Bindable var members: OrgMembersViewModel

    @Environment(\.openURL) private var openURL

    @State private var showDisconnectConfirmation: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("LinkedIn company pages")
                .font(.ilSubtitle())

            Text("Members assigned a company page cross-post to that page using the organization's shared LinkedIn connection. Members without an assignment post as themselves.")
                .font(.ilMono(10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if viewModel.isLoading, viewModel.status == nil {
                ProgressView().controlSize(.small)
            } else if let error = viewModel.loadError, viewModel.status == nil {
                OrgErrorState(error: error, retry: { await viewModel.load() })
                    .frame(height: 160)
            } else {
                statusRow
                if let error = viewModel.actionError {
                    Text(error.localizedDescription)
                        .font(.ilMono(10))
                        .foregroundStyle(Color.accentColor)
                }
                if viewModel.syncFailedWithStalePages {
                    // Upstream-failure rule: keep the page list usable and say
                    // it might be out of date rather than emptying it.
                    Text("Couldn't refresh the page list — showing the pages from the last successful sync.")
                        .font(.ilMono(10))
                        .foregroundStyle(.secondary)
                }
                if viewModel.isConnected {
                    pageList
                    if viewModel.canManage {
                        assignmentEditor
                    }
                }
            }
        }
        .confirmationDialog(
            "Disconnect the organization's LinkedIn?",
            isPresented: $showDisconnectConfirmation,
            titleVisibility: .visible
        ) {
            Button("Disconnect", role: .destructive) {
                Task { await viewModel.disconnect() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            // The consequence lands on other people, so name the count.
            Text(viewModel.assignedMemberCount == 0
                 ? "The shared connection is removed and this organization's company pages become unavailable for cross-posting."
                 : "\(viewModel.assignedMemberCount) assigned \(viewModel.assignedMemberCount == 1 ? "member" : "members") will fall back to posting on their personal LinkedIn. Page assignments are cleared and can't be restored without reconnecting.")
        }
    }

    private var statusRow: some View {
        HStack(spacing: 8) {
            Image(systemName: viewModel.isConnected ? "checkmark.seal.fill" : "xmark.seal")
                .foregroundStyle(viewModel.isConnected ? Color.green : Color.secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.isConnected ? "Connected" : "Not connected")
                    .font(.ilBody())
                if let expiry = viewModel.status?.expiresAt {
                    Text("Credential expires \(expiry.formatted(date: .abbreviated, time: .omitted))")
                        .font(.ilMono(10))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if viewModel.isWorking {
                ProgressView().controlSize(.small)
            }
            if viewModel.canManage {
                if viewModel.isConnected {
                    Button("Sync pages") {
                        Task { await viewModel.syncPages() }
                    }
                    .buttonStyle(.bordered)
                    .disabled(viewModel.isWorking)

                    Button("Disconnect…", role: .destructive) {
                        showDisconnectConfirmation = true
                    }
                    .buttonStyle(.bordered)
                    .disabled(viewModel.isWorking)
                } else {
                    // Connecting is a browser OAuth redirect, not an API call.
                    Button("Connect LinkedIn") { openAuthorize() }
                        .buttonStyle(.borderedProminent)
                        .disabled(viewModel.isWorking)
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var pageList: some View {
        if viewModel.pages.isEmpty {
            Text("No company pages yet. Sync to pull the pages this connection administers.")
                .font(.ilMono(10))
                .foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(viewModel.pages) { page in
                    HStack(spacing: 6) {
                        Image(systemName: "building.2")
                            .imageScale(.small)
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                        Text(page.name)
                            .font(.ilMono(10))
                        if let synced = page.lastSyncedAt {
                            Text("synced \(synced.formatted(date: .abbreviated, time: .omitted))")
                                .font(.ilMono(10))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private var assignmentEditor: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Page assignments")
                .font(.ilSubtitle())
                .fontWeight(.medium)
            if members.members.isEmpty {
                Text("Load the member roster to assign pages.")
                    .font(.ilMono(10))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(members.members) { member in
                    HStack {
                        Text(member.displayLabel)
                            .font(.ilMono(10))
                            .lineLimit(1)
                        Spacer()
                        Picker("Page", selection: Binding(
                            get: { viewModel.assignedPage(for: member.userId)?.id ?? "" },
                            set: { pageId in
                                Task {
                                    await viewModel.assign(
                                        userId: member.userId,
                                        // "" is the no-assignment sentinel; the
                                        // wire wants a null page reference.
                                        pageId: pageId.isEmpty ? nil : pageId
                                    )
                                }
                            }
                        )) {
                            Text("Personal LinkedIn").tag("")
                            ForEach(viewModel.pages) { page in
                                Text(page.name).tag(page.id)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 200)
                        .disabled(viewModel.isWorking)
                        .accessibilityLabel("LinkedIn page for \(member.displayLabel)")
                    }
                }
            }
        }
        .padding(.top, 4)
    }

    private func openAuthorize() {
        guard let url = viewModel.authorizeURL else { return }
        openURL(url)
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
