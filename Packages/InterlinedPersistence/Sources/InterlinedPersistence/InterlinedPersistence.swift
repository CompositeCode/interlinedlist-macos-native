// InterlinedPersistence
//
// SwiftData-backed caches and (later, in Wave 4) the DocumentSyncEngine
// (PLAN.md §3, §5 — timeline reads from a SwiftData cache with
// stale-while-revalidate). M1 ships only the message / timeline cache; the
// document, list, and folder schemas land with their respective milestones
// (M3 lists, M4 documents) rather than being half-implemented here.
//
//   Schema/  — SwiftData @Model record types (MessageRecord, TimelinePageRecord).
//   Stores/  — SwiftDataMessageStore: actor-isolated conformance to the
//              InterlinedDomain.MessageStore port.
//   Mapping/ — internal record <-> domain value-type translation.
//
// The package's public API surface is intentionally narrow: callers wire up a
// `SwiftDataMessageStore` and pass it to `MessagesService` as a `MessageStore`.

import Foundation
import InterlinedDomain

/// Namespace marker for InterlinedPersistence — used so callers have a
/// stable, discoverable type even when they only import the store from the
/// module's submodules.
public enum InterlinedPersistence {
    /// The kit/domain version this persistence layer was built against. Surfaced
    /// so accidental local-package version skew shows up at a glance — same
    /// pattern as `InterlinedDomain.builtAgainstKitVersion`.
    public static let builtAgainstDomainVersion: String = InterlinedDomain.builtAgainstKitVersion
}
