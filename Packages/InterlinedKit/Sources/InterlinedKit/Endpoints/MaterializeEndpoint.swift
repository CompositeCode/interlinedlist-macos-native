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
/// The `listConfig.fields` descriptor uses `propertyKey` / `propertyName` /
/// `propertyType` / `sourceKey` — **not** the `key`/`label`/`type` shape the rest
/// of the schema API uses, and not what the route's own error message implies.
/// See `MaterializeField`; it was captured from the web app's real request after
/// every guessed shape was rejected.
public enum Materialize {

    /// `POST /api/materialize` — create a list and/or a document from a source.
    public static func create(_ body: MaterializeRequest) -> Request<MaterializeResponse> {
        Request(method: .post, path: "/api/materialize", body: .json(body), auth: .bearer)
    }
}
