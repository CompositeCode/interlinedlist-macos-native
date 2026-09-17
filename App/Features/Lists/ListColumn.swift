// ListColumn
//
// One rendered column of a list's row table: the row-data **key** it reads and
// the **label** it shows.
//
// These are separate on the server (`propertyKey` / `propertyName`) and were
// collapsed into a single `name` throughout the lists UI. That was harmless only
// because the client could not create a schema at all — the server rejected the
// DSL string it sent — so every schema in the wild had key == label. Fixing the
// wire shape (GitHub #85) makes the distinction load-bearing: a column labelled
// "Publication Year" over a key of `year` renders nothing if the label is used
// as the subscript.
//
// Per Decision 0003 this type consumes only `InterlinedDomain`.

import Foundation

struct ListColumn: Identifiable, Hashable, Sendable {

    /// The `ListRow.fields` key this column reads. The identity.
    let key: String

    /// The header text.
    let label: String

    var id: String { key }
}
