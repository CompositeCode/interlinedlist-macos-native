import Foundation

// MARK: - DocumentTemplate

/// A starter template that seeds a new document's title and Markdown body
/// before it is handed to the normal create flow (feature-gaps.md §1.4).
///
/// **This is a client-side feature.** The InterlinedList API exposes no
/// documents-templates endpoint (see
/// `InterlinedKit/Endpoints/DocumentsEndpoint.swift` — only sync, document
/// CRUD, image upload, and folder CRUD). A template is therefore nothing more
/// than bundled starter Markdown: the app picks one, seeds a fresh buffer, and
/// routes it through the existing `DocumentsServicing.create` path exactly like
/// a blank document. Nothing about a template survives on the server — once the
/// document is created it is an ordinary document.
///
/// If the API later grows a real templates endpoint, this type can migrate to a
/// server-backed catalog: replace `builtIn` with a `TemplatesServicing` fetch
/// and keep the same `{ name, summary, bodyMarkdown }` shape so call sites do
/// not change.
public struct DocumentTemplate: Sendable, Equatable, Hashable, Identifiable {

    /// Stable identifier used for selection and diffing. Unique within a
    /// catalog (enforced by `DocumentTemplateTests`).
    public let id: String

    /// Human-readable name shown in the picker and used as the default title
    /// of a document seeded from this template.
    public let name: String

    /// One-line description shown under the name in the picker so the user can
    /// tell templates apart without opening them.
    public let summary: String

    /// The starter Markdown seeded into the new document's `DocumentBody`.
    /// May be empty (the Blank template) — that is the canonical
    /// "new blank document" behavior.
    public let bodyMarkdown: String

    public init(id: String, name: String, summary: String, bodyMarkdown: String) {
        self.id = id
        self.name = name
        self.summary = summary
        self.bodyMarkdown = bodyMarkdown
    }

    /// The body this template seeds, as a typed `DocumentBody`. Convenience for
    /// call sites that already speak `DocumentBody` rather than raw `String`.
    public var body: DocumentBody {
        DocumentBody(markdown: bodyMarkdown)
    }
}

// MARK: - Built-in catalog

public extension DocumentTemplate {

    /// The bundled starter catalog. Static and dependency-free so App-layer
    /// view models can reference it directly — no composition-root wiring is
    /// required (there is no service to inject because there is no endpoint).
    ///
    /// The first entry (`.blank`) is the identity template: seeding from it is
    /// byte-for-byte the same as the existing "New blank document" action.
    static let builtIn: [DocumentTemplate] = [
        .blank,
        .meetingNotes,
        .dailyLog,
        .productRequirements
    ]

    /// An empty document. Equivalent to today's "New Document" action; kept in
    /// the catalog so the picker always offers a "start from scratch" option.
    static let blank = DocumentTemplate(
        id: "blank",
        name: "Blank",
        summary: "An empty document to start from scratch.",
        bodyMarkdown: ""
    )

    static let meetingNotes = DocumentTemplate(
        id: "meeting-notes",
        name: "Meeting Notes",
        summary: "Agenda, attendees, discussion, and action items.",
        bodyMarkdown: """
        # Meeting Notes

        **Date:** \n\
        **Attendees:** \n\
        **Facilitator:**

        ## Agenda

        1.
        2.
        3.

        ## Discussion

        -

        ## Decisions

        -

        ## Action Items

        - [ ] Owner — task — due date
        - [ ]

        ## Follow-up

        -
        """
    )

    static let dailyLog = DocumentTemplate(
        id: "daily-log",
        name: "Daily Log",
        summary: "A running journal for today's plans, progress, and blockers.",
        bodyMarkdown: """
        # Daily Log

        **Date:**

        ## Plan for Today

        - [ ]
        - [ ]
        - [ ]

        ## Progress

        -

        ## Blockers

        -

        ## Notes

        -

        ## Tomorrow

        -
        """
    )

    static let productRequirements = DocumentTemplate(
        id: "prd",
        name: "Product Requirements",
        summary: "A PRD skeleton: problem, goals, scope, and success metrics.",
        bodyMarkdown: """
        # Product Requirements: <Feature Name>

        **Author:** \n\
        **Status:** Draft \n\
        **Last updated:**

        ## Summary

        One paragraph describing what this is and why it matters.

        ## Problem

        What problem are we solving, and for whom?

        ## Goals

        -
        -

        ## Non-Goals

        -

        ## Requirements

        ### Functional

        -

        ### Non-Functional

        -

        ## Open Questions

        -

        ## Success Metrics

        -
        """
    )
}
