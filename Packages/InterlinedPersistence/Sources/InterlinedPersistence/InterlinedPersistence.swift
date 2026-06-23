// InterlinedPersistence
//
// SwiftData-backed caches and (later, in Wave 4) the DocumentSyncEngine
// (PLAN.md §3, §5 — timeline reads from a SwiftData cache with
// stale-while-revalidate). M1 shipped the message / timeline cache;
// Wave 4.1 (M3) adds the lists cache; the document and folder schemas
// land with M4.
//
//   Schema/  — SwiftData @Model record types
//              (MessageRecord, TimelinePageRecord, ListRecord, ListsPageRecord,
//               ListSchemaRecord, SchemaFieldRecord, ListRowRecord,
//               ListConnectionRecord, ListWatcherRecord).
//   Stores/  — SwiftDataMessageStore, SwiftDataListsStore: actor-isolated
//              conformances to the InterlinedDomain cache ports.
//   Mapping/ — internal record <-> domain value-type translation.
//
// The package's public API surface is intentionally narrow: callers wire up a
// `SwiftDataMessageStore` / `SwiftDataListsStore` and pass it to the
// corresponding domain service as a `MessageStore` / `ListsStore`.

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
