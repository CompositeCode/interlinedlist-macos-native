// InterlinedPersistence
//
// SwiftData schemas, cache policies, and the DocumentSyncEngine live here
// once Wave 4 lands (PLAN.md §6 M4). For M0 this is a placeholder namespace
// that proves the package builds and links against InterlinedDomain.

import Foundation
import InterlinedDomain

/// Namespace marker for InterlinedPersistence.
public enum InterlinedPersistence {
    /// References the domain layer's kit version so all three packages
    /// agree on the schema baseline during M0.
    public static let domainKitSchemaVersion: String = InterlinedDomain.kitSchemaVersion
}
