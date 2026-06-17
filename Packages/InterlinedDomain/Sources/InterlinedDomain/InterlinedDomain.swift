// InterlinedDomain
//
// Business-logic layer for InterlinedList — app-facing models and services that
// depend on InterlinedKit protocols (PLAN.md §3). UI-agnostic: this package
// must never import SwiftUI or AppKit. DTOs from InterlinedKit are mapped to
// domain models at the boundary (`Models/Mappers.swift`) and never escape this
// package.
//
//   Models/   — Message, UserSummary, CurrentUser, Visibility, TimelineScope,
//               TimelinePage, and the DTO → domain mappers.
//   Services/ — MessagesService, SessionService, EntitlementsService.
//   Caching/  — the MessageStore cache port + an in-memory implementation.
//
// The login + timeline vertical slice (M1) lives here; Lists / Social / Orgs /
// Documents services arrive in their later milestones.

import Foundation
import InterlinedKit

/// Namespace marker for the InterlinedDomain module.
public enum InterlinedDomain {
    /// The version of the kit this domain layer was built against. Surfaced so
    /// accidental local-package version skew is visible at a glance.
    public static let builtAgainstKitVersion: String = InterlinedKit.schemaVersion
}
