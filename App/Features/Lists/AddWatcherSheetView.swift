// AddWatcherSheetView
//
// Sheet for granting someone access to a list (work-consolidation.md G23,
// issue #48). Searches candidates through `GET /api/lists/{id}/watchers/users`
// — the route built for this, which auto-excludes people who already have
// access — and grants the chosen person access through the real
// `POST /api/lists/{id}/watchers`.
//
// Granting access to a named user is subscriber-gated server-side, so a free
// owner's 403 arrives as `ListsError.subscriberRequired` and is rendered as an
// upsell rather than an error banner (same treatment as Share Links and
// Invite by Email).
//
// Per Decision 0003 the view imports only InterlinedDomain.

import SwiftUI
import InterlinedDomain

struct AddWatcherSheetView: View {

    @Bindable var viewModel: WatchersViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var searchText: String = ""
    @State private var selectedRole: WatcherRole = .viewer

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Share This List")
                .font(.ilTitle(18))
                .padding(.top, 4)

            searchField

            if viewModel.showSubscriberUpsell {
                subscriberUpsell
            }

            rolePicker

            candidateList

            if let error = viewModel.error {
                Text(error.localizedDescription)
                    .font(.ilMono(10))
                    .foregroundStyle(Color.accentColor)
            }

            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(minWidth: 420, minHeight: 380)
        .task {
            // Open on the unfiltered first page so the sheet is useful before
            // the user types anything.
            if !viewModel.hasSearchedOnce {
                await viewModel.searchCandidates(query: "")
            }
        }
    }

    // MARK: - Sections

    private var searchField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Find someone")
                .font(.ilMono(10))
                .foregroundStyle(.secondary)
            HStack {
                TextField("Name or username", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        Task { await viewModel.searchCandidates(query: searchText) }
                    }
                Button("Search") {
                    Task { await viewModel.searchCandidates(query: searchText) }
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.isSearching)
            }
            if viewModel.isSearching {
                ProgressView()
                    .controlSize(.small)
            }
        }
    }

    private var rolePicker: some View {
        HStack {
            Text("Access")
                .font(.ilMono(10))
                .foregroundStyle(.secondary)
            Picker("Access", selection: $selectedRole) {
                ForEach(WatcherRole.allCases, id: \.self) { role in
                    Text(role.label).tag(role)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 140)
            Spacer()
        }
    }

    @ViewBuilder
    private var candidateList: some View {
        if viewModel.candidates.isEmpty {
            Text(viewModel.hasSearchedOnce
                 ? "Nobody left to add — everyone matching already has access."
                 : "Search for someone to give access to.")
                .font(.ilMono(11))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            List(viewModel.candidates) { candidate in
                candidateRow(candidate)
            }
            .frame(maxHeight: .infinity)
        }
    }

    private func candidateRow(_ candidate: CollaboratorCandidate) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "person.crop.circle")
                .font(.ilBody())
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(candidate.displayLabel)
                    .font(.ilBody())
                    .fontWeight(.medium)
                if let username = candidate.username, !username.isEmpty {
                    Text("@\(username)")
                        .font(.ilMono(10))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button("Add") {
                Task { await viewModel.addWatcher(candidate: candidate, role: selectedRole) }
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.pendingOperations.contains(candidate.id))
            .accessibilityLabel("Give \(candidate.displayLabel) \(selectedRole.label) access")
        }
        .padding(.vertical, 2)
    }

    private var subscriberUpsell: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "star.circle.fill")
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Sharing a list with someone is a subscriber feature")
                    .font(.ilBody().weight(.semibold))
                Text("Your subscription does not cover granting access. Removing access always works.")
                    .font(.ilMono(10))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Dismiss") { viewModel.dismissSubscriberUpsell() }
                .buttonStyle(.bordered)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.08))
    }
}
