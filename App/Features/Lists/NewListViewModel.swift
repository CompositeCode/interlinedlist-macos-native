// NewListViewModel
//
// Drives the "New List" sheet (PLAN.md §6 M3 — list CRUD). Owns the
// editable title / description / parent / visibility / optional
// GitHub-source fields and the submission flow. Calls
// `ListsServicing.create` on submit, then publishes a `ListsEvent`
// so any open `OwnedListsRootView` prepends the new list without
// a refetch.
//
// The GitHub-source fields are surfaced as plain text fields on this
// sheet; the kit DTO does not yet round-trip per-source detail
// (`/API-backend-prompts-to-build.md` item 2.3), so for v1 we surface
// the fields in the UI but do not send them along — the create call
// uses the schema and parent ID. The fields stay on the sheet so the
// user signals intent; the wire round-trip lands when the kit
// publishes the source DTO fields.

import Foundation
import Observation
import InterlinedDomain

@MainActor
@Observable
final class NewListViewModel {

    private let lists: ListsServicing
    private let eventBus: ListsEventBus

    /// Title text field.
    var title: String = ""
    /// Optional description text field.
    var descriptionText: String = ""
    /// Optional schema DSL — surfaced as a raw string here for
    /// convenience. The proper schema editor lives behind "Edit Schema"
    /// on the list once it exists; on create we accept whatever the
    /// user typed (or nothing) so the list can be brand-new without a
    /// schema.
    var schemaDSL: String = ""
    /// Optional parent list for nested lists. `nil` means top-level.
    var parentID: String?
    /// Visibility. Defaults to private for owned lists (the M3 brief
    /// "Public / Private" picker).
    var visibility: Visibility = .private
    /// Optional GitHub repository (`"owner/repo"`). Plain text for v1;
    /// see file-level note above.
    var gitHubRepository: String = ""
    /// Optional GitHub path within the repo.
    var gitHubPath: String = ""
    /// Optional GitHub branch (default `"main"` on the wire when the
    /// kit DTO grows the field).
    var gitHubBranch: String = ""

    /// True while a `create` round-trip is in flight.
    private(set) var isSubmitting: Bool = false
    /// The last submission error. Cleared on the next submit.
    private(set) var error: Error?
    /// Set to `true` after a successful create; the view observes
    /// this to dismiss the sheet.
    private(set) var didFinish: Bool = false
    /// The created list, available after `didFinish == true`. Used by
    /// the view to advance the selection to the new list.
    private(set) var createdList: OwnedList?

    /// Available parent candidates (e.g. the user's other lists). The
    /// caller seeds this from `OwnedListsViewModel.lists_loaded` so the
    /// sheet's parent picker is consistent with the sidebar.
    var parentCandidates: [OwnedList] = []

    /// Whether the form is submittable. A non-empty title is required;
    /// everything else is optional.
    var isPublishable: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    init(
        lists: ListsServicing,
        eventBus: ListsEventBus,
        parentCandidates: [OwnedList] = []
    ) {
        self.lists = lists
        self.eventBus = eventBus
        self.parentCandidates = parentCandidates
    }

    /// Submits the create. Validates `isPublishable` first; bails out
    /// silently if invalid (defence in depth — the view's submit
    /// button is disabled in that case).
    func submit() async {
        guard isPublishable, !isSubmitting else { return }
        isSubmitting = true
        error = nil
        defer { isSubmitting = false }

        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDescription = descriptionText.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSchema = schemaDSL.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let created = try await lists.create(
                title: trimmedTitle,
                description: trimmedDescription.isEmpty ? nil : trimmedDescription,
                schema: trimmedSchema.isEmpty ? nil : trimmedSchema,
                parentId: parentID,
                isPublic: visibility == .public
            )
            createdList = created
            eventBus.post(.listCreated(created))
            didFinish = true
        } catch {
            self.error = error
        }
    }
}
