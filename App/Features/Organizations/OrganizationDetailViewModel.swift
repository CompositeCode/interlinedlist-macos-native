// OrganizationDetailViewModel
//
// Drives the org detail pane: shows the org's fields and lets the user
// edit name / description / public flag (PLAN.md §1 "Organizations",
// §6 M6 — `OrgService.update`). The member roster is a separate concern
// owned by `OrgMembersViewModel`, surfaced alongside this view model in
// the detail view.
//
// Reads through `OrgServicing` only — no direct API access — so unit
// tests substitute a stub. `@Observable` so SwiftUI re-renders on every
// state change.
//
// Per decision 0003, the view model consumes only `InterlinedDomain`.

import Foundation
import Observation
import InterlinedDomain

@MainActor
@Observable
final class OrganizationDetailViewModel {

    // MARK: - Dependencies

    private let orgs: OrgServicing
    private let orgId: String

    // MARK: - Observable state

    /// The loaded org. `nil` until the first successful load.
    private(set) var organization: Organization?

    private(set) var isLoading: Bool = false
    private(set) var loadError: Error?

    /// True while an edit round-trip is in flight, so the form disables
    /// its save button.
    private(set) var isSaving: Bool = false
    private(set) var saveError: Error?

    // MARK: - Init

    /// - Parameters:
    ///   - orgService: the org surface (a stub in tests).
    ///   - orgId: the org to load and edit.
    ///   - initial: an optional already-known `Organization` (e.g. the row
    ///     the user tapped) so the detail paints instantly before the
    ///     authoritative reload lands.
    init(orgService: OrgServicing, orgId: String, initial: Organization? = nil) {
        self.orgs = orgService
        self.orgId = orgId
        self.organization = initial
    }

    // MARK: - Intents

    /// Loads (or reloads) the org's authoritative fields.
    func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            organization = try await orgs.organization(id: orgId)
            loadError = nil
        } catch {
            loadError = error
        }
    }

    /// Saves edited org fields. Validates the name client-side: a blank
    /// name is rejected before any service call. On success, replaces the
    /// rendered org with the server's authoritative return value.
    ///
    /// - Returns: `true` on success, `false` on validation failure or a
    ///   failed round-trip (inspect `saveError`).
    @discardableResult
    func save(name: String, description: String, isPublic: Bool) async -> Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            saveError = OrganizationDetailError.emptyName
            return false
        }
        guard !isSaving else { return false }
        isSaving = true
        defer { isSaving = false }

        let trimmedDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let updated = try await orgs.update(
                id: orgId,
                name: trimmedName,
                description: trimmedDescription,
                isPublic: isPublic
            )
            organization = updated
            saveError = nil
            return true
        } catch {
            saveError = error
            return false
        }
    }
}

// MARK: - OrganizationDetailError

/// Client-side validation failures surfaced before any network call.
enum OrganizationDetailError: LocalizedError, Equatable {
    case emptyName

    var errorDescription: String? {
        switch self {
        case .emptyName:
            return "An organization needs a name."
        }
    }
}
