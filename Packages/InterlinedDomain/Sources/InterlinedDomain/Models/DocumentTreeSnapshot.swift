import Foundation

// MARK: - DocumentSummary

/// A document as the sidebar tree knows it (work-consolidation.md G24).
///
/// `GET /api/documents/tree` returns lighter document rows than
/// `GET /api/documents` does — `id`, `title`, `relativePath` and `isPublic`,
/// and nothing else. Modelling that as a `Document` would be a lie: every
/// consumer would see an `updatedAt` of `.distantPast` and an empty body and
/// have no way to tell "the server said empty" from "this shape doesn't carry
/// it". `DocumentSummary` is the honest projection — enough to render a row,
/// count a folder, or name a move source, and deliberately not enough to open
/// an editor.
///
/// `folderId` is *derived*, not transported: the tree nests documents under
/// their folder and omits the field, so the mapper stamps the enclosing
/// folder's id (and `nil` for `rootDocuments`).
public struct DocumentSummary: Sendable, Equatable, Hashable, Identifiable {

    public let id: String
    public let title: String
    /// The folder this document is filed in; `nil` means root (unfiled).
    public let folderId: String?
    /// The document's path within the synced folder, when the server sent one.
    public let relativePath: String?
    public let isPublic: Bool

    public init(
        id: String,
        title: String,
        folderId: String? = nil,
        relativePath: String? = nil,
        isPublic: Bool = false
    ) {
        self.id = id
        self.title = title
        self.folderId = folderId
        self.relativePath = relativePath
        self.isPublic = isPublic
    }
}

// MARK: - DocumentTreeSnapshot

/// The whole documents sidebar as one value (work-consolidation.md G24).
///
/// Domain projection of `GET /api/documents/tree`. Holds the flat folder list
/// (nesting lives in `FolderNode.parentId`, exactly as before) plus the
/// folder → documents index and the unfiled root documents.
///
/// Two invariants the wire shape forces and this type preserves:
///
/// 1. **Root documents are not a folder.** `rootDocuments` stays a distinct
///    array; "no folder" is a real destination the UI must be able to name,
///    so it is never folded into `folders`.
/// 2. **`_templates` is a real folder in the payload.** The server returns the
///    template folder inline with the user's own folders. `userFolders` and
///    `moveDestinations` filter it out; `folders` keeps it so callers that do
///    want it (the template picker) can still find it via `templatesFolderID`.
public struct DocumentTreeSnapshot: Sendable, Equatable {

    /// The name the server gives the folder that backs the template picker.
    /// Documented on `/help/documents`: *"Templates are stored in a special
    /// folder named `_templates`, created automatically the first time you
    /// open the template picker."*
    public static let templatesFolderName = "_templates"

    /// Every folder in the account, including `_templates`, in server order.
    public let folders: [FolderNode]

    /// Documents filed in each folder, keyed by folder id.
    public let documentsByFolder: [FolderNode.ID: [DocumentSummary]]

    /// Documents with no folder.
    public let rootDocuments: [DocumentSummary]

    public init(
        folders: [FolderNode] = [],
        documentsByFolder: [FolderNode.ID: [DocumentSummary]] = [:],
        rootDocuments: [DocumentSummary] = []
    ) {
        self.folders = folders
        self.documentsByFolder = documentsByFolder
        self.rootDocuments = rootDocuments
    }

    // MARK: - Derived views

    /// The folders a person should see and be offered, i.e. everything except
    /// the machine-managed `_templates` folder.
    public var userFolders: [FolderNode] {
        folders.filter { $0.name != Self.templatesFolderName }
    }

    /// The id of the `_templates` folder, when the account has one yet. `nil`
    /// before the first template-picker visit creates it.
    public var templatesFolderID: FolderNode.ID? {
        folders.first { $0.name == Self.templatesFolderName }?.id
    }

    /// The folders offered as a **Move to folder** destination: the user's own
    /// folders, never `_templates`. "No folder (root)" is represented by `nil`
    /// at the call site rather than by a synthetic entry here.
    public var moveDestinations: [FolderNode] {
        userFolders
    }

    /// The sidebar projection over `userFolders`. `_templates` is excluded so
    /// it never renders as a browsable folder.
    public var folderTree: FolderTree {
        FolderTree(folders: userFolders)
    }

    /// The documents in `folderID`, or the root documents when `nil`.
    /// Empty for a folder the snapshot doesn't know or one with no documents —
    /// the two are indistinguishable here by design, since an unknown folder
    /// has nothing to show either way.
    public func documents(in folderID: FolderNode.ID?) -> [DocumentSummary] {
        guard let folderID else { return rootDocuments }
        return documentsByFolder[folderID] ?? []
    }

    /// How many documents are filed directly in `folderID` (or at root when
    /// `nil`). Direct children only — a parent folder does not count the
    /// documents inside its sub-folders.
    public func documentCount(in folderID: FolderNode.ID?) -> Int {
        documents(in: folderID).count
    }

    /// Every document in the snapshot, root documents first then each folder's
    /// in folder order. Used to answer "which folder is this document in?"
    /// without the caller rebuilding the index.
    public var allDocuments: [DocumentSummary] {
        var all = rootDocuments
        for folder in folders {
            all.append(contentsOf: documentsByFolder[folder.id] ?? [])
        }
        return all
    }

    /// The folder holding `documentID`, or `nil` when the document is at root
    /// **or** absent from the snapshot. Callers that need to tell those apart
    /// should check `allDocuments` first.
    public func folderID(ofDocument documentID: String) -> FolderNode.ID? {
        allDocuments.first { $0.id == documentID }?.folderId
    }
}

// MARK: - PublicUserDocuments

/// A user's public documents (work-consolidation.md G24 —
/// `GET /api/users/{username}/documents`).
///
/// These rows are richer than the tree's — they carry `createdAt` /
/// `updatedAt` — so they project to full `Document` values, with an empty
/// body: the route lists documents but never ships their Markdown. Fetch the
/// document by id to read it.
public struct PublicUserDocuments: Sendable, Equatable {

    /// The username these documents belong to, echoed back for display.
    public let username: String

    /// The public documents, in server order.
    public let documents: [Document]

    /// Public folders, when the account exposes any. Empty on every account
    /// reachable read-only during the G24 probe, so treat a non-empty value as
    /// unverified-but-tolerated rather than as a load-bearing contract.
    public let folders: [FolderNode]

    public init(
        username: String,
        documents: [Document] = [],
        folders: [FolderNode] = []
    ) {
        self.username = username
        self.documents = documents
        self.folders = folders
    }

    /// True when the user has published nothing — the profile column's empty
    /// state, distinct from a failed load.
    public var isEmpty: Bool {
        documents.isEmpty && folders.isEmpty
    }
}

// MARK: - DocumentInvite

/// A resolved document email invite (work-consolidation.md G24 —
/// `GET /api/documents/invite/{token}`).
///
/// The landing state, and only the landing state. **Accepting is not
/// modelled** and cannot be: `POST /api/documents/invite/{token}` is
/// session-cookie-authenticated in the live spec, so a Bearer sync-token
/// client has no way to claim. `acceptURL(base:)` builds the web address the
/// Mac hands to the browser instead.
public struct DocumentInvite: Sendable, Equatable {

    /// The opaque invite token this was resolved from.
    public let token: String

    /// The role the invite grants (`watcher` / `collaborator` / `manager`).
    public let role: String

    /// The document's title, for display. `nil` when the server withheld it.
    public let resourceTitle: String?

    /// No user is signed in on the *web* session → the landing page prompts
    /// sign-in before the invite can be claimed.
    public let needsAuth: Bool

    /// The signed-in web user's verified email matches the invited address, so
    /// the accept step will succeed once they take it in the browser.
    public let canClaim: Bool

    /// Someone is signed in on the web under a different address; they must
    /// switch accounts before accepting.
    public let wrongAccount: Bool

    /// The invite was already claimed. It still resolves so the landing page
    /// can link the claimer into the document.
    public let accepted: Bool

    public init(
        token: String,
        role: String,
        resourceTitle: String? = nil,
        needsAuth: Bool = false,
        canClaim: Bool = false,
        wrongAccount: Bool = false,
        accepted: Bool = false
    ) {
        self.token = token
        self.role = role
        self.resourceTitle = resourceTitle
        self.needsAuth = needsAuth
        self.canClaim = canClaim
        self.wrongAccount = wrongAccount
        self.accepted = accepted
    }

    /// The web address that completes the invite. Accepting is browser-only
    /// (session cookie), so this is the Mac's hand-off, not a fallback.
    public func acceptURL(base: URL) -> URL {
        base
            .appendingPathComponent("documents")
            .appendingPathComponent("invite")
            .appendingPathComponent(token)
    }
}
