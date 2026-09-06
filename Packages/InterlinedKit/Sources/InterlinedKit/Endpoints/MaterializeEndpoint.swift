import Foundation

/// Request builder for **"Create from…" / materialize** (work-consolidation.md
/// G16) — turn messages, lists, list rows, a document, or a highlighted
/// selection into a new list, a new document, or both.
///
/// Verified live 2026-09-05 against the `.env` test account:
/// - `target` accepts exactly `list`, `doc`, `both`; anything else → `400 "Invalid target"`.
/// - `target: .list` / `.both` require a list title → `400 "A list title is required"`.
/// - A well-formed `source` with unknown ids → `404 "One or more messages are
///   unavailable"` / `"Document is unavailable"`, which confirms the ref shape
///   parses and that nothing is created on the failure path.
///
/// ⚠️ **KNOWN UNRESOLVED — the `listConfig.fields` descriptor.** Every shape
/// tried (`{key}`, `{key,type}`, `{key,label,type}`, `{name,type}`, bare
/// strings) is rejected with the same `400 "Invalid list schema: Field at index
/// 0 must have a 'key' property (string)"` — including payloads that plainly
/// carry a string `key`. The message therefore does not describe the check that
/// is failing, and no client-side guess has satisfied it. Until it is resolved
/// (capture the web app's own successful request, or a backend answer), only the
/// `.doc` target should be considered usable; `.list` and `.both` will fail.
public enum Materialize {

    /// `POST /api/materialize` — create a list and/or a document from a source.
    public static func create(_ body: MaterializeRequest) -> Request<MaterializeResponse> {
        Request(method: .post, path: "/api/materialize", body: .json(body), auth: .bearer)
    }
}
