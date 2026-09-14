// MoveToFolderMenu
//
// The **Move to folder** affordance from `/help/documents`: *"Open the
// document, use the Move to folder option (or the document settings menu),
// and choose a destination; select No folder (root) to remove it from all
// folders."* (work-consolidation.md G24.)
//
// One view, two call sites — the document list's per-row context menu and the
// editor's settings menu — so the destination list, the `_templates`
// exclusion, and the "already here" disabling can't drift between them.
//
// Destinations come from `FolderTreeViewModel`, which is already the single
// source for the folder tree; this view adds no fetch of its own. `_templates`
// is absent because `moveDestinations` filters it: it is the server-managed
// folder behind the template picker, and filing an ordinary document there
// would make it show up as a template.
//
// Pure SwiftUI; no AppKit. Decision 0003: consumes only `InterlinedDomain`.

import SwiftUI
import InterlinedDomain

struct MoveToFolderMenu: View {

    /// Source of the destination folders. Not fetched here — the sidebar has
    /// already loaded the tree.
    let folderTree: FolderTreeViewModel

    /// The folder the document is in right now, so that destination can be
    /// shown as the current one and disabled rather than silently no-op'ing.
    let currentFolderID: FolderNode.ID?

    /// Invoked with the chosen destination. `nil` means "No folder (root)".
    let onMove: (FolderNode.ID?) -> Void

    var body: some View {
        Menu {
            Button {
                onMove(nil)
            } label: {
                Label("No folder (root)", systemImage: "tray")
            }
            .disabled(currentFolderID == nil)

            let destinations = folderTree.moveDestinations
            if !destinations.isEmpty {
                Divider()
                ForEach(destinations) { folder in
                    Button {
                        onMove(folder.id)
                    } label: {
                        Label(folder.name, systemImage: "folder")
                    }
                    // Moving a document into the folder it already lives in
                    // would cost a round-trip to change nothing.
                    .disabled(folder.id == currentFolderID)
                }
            }
        } label: {
            Label("Move to Folder", systemImage: "folder.badge.gearshape")
        }
        .help("File this document in a different folder, or move it out to the root")
    }
}
