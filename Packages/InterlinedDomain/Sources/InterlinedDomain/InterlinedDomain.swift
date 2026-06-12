// InterlinedDomain
//
// Domain layer for InterlinedList — app-facing models and services that
// depend on InterlinedKit protocols. M0 placeholder; real services
// (MessagesService, ListsService, DocumentsService, SocialService,
// OrgService, NotificationsService, EntitlementsService) are built in
// later waves per PLAN.md §3 and §6.

import Foundation
import InterlinedKit

/// Namespace marker for the InterlinedDomain module.
public enum InterlinedDomain {
    /// References the underlying kit schema so the domain layer can assert
    /// it is built against a compatible InterlinedKit version.
    public static let kitSchemaVersion: String = InterlinedKit.schemaVersion
}
