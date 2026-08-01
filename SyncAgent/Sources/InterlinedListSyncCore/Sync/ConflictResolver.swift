import Foundation

/// The reconciliation decision for a single document, from the 5-state matrix
/// over (localChanged × remoteChanged × localExists × remoteExists).
public enum SyncDecision: Sendable, Equatable {
    /// Remote is newer → write remote content over the local file.
    case pull
    /// Local is newer → PATCH the server with local content.
    case push
    /// Both sides changed → keep a conflict copy, then pull (remote wins).
    case conflictCopy
    /// Remote was deleted → remove the local file.
    case deleteLocal
    /// Local file was deleted → DELETE the server document.
    case deleteRemote
    /// Nothing to do.
    case noOp
}

/// Pure, table-driven conflict policy. Unit-testable in isolation — no I/O.
///
/// Policy is **remote-wins**: when both sides changed, the remote content
/// becomes canonical and the local edits are preserved as a conflict copy.
public enum ConflictResolver {

    public static func decide(
        localChanged: Bool,
        remoteChanged: Bool,
        localExists: Bool,
        remoteExists: Bool
    ) -> SyncDecision {
        switch (localExists, remoteExists) {
        case (true, true):
            switch (localChanged, remoteChanged) {
            case (true, true):   return .conflictCopy
            case (true, false):  return .push
            case (false, true):  return .pull
            case (false, false): return .noOp
            }
        case (true, false):
            // Remote absent. If the user also edited locally, preserve the work
            // by re-pushing it; otherwise honor the remote deletion.
            return localChanged ? .push : .deleteLocal
        case (false, true):
            // Local absent. If the remote changed (or is brand-new), recreate it
            // locally; otherwise the user deleted it, so delete on the server.
            return remoteChanged ? .pull : .deleteRemote
        case (false, false):
            return .noOp
        }
    }
}
