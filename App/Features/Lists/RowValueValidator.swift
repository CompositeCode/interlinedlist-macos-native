// RowValueValidator
//
// Applies a column's stored rules to a typed cell value **before** the network
// call (GitHub #50).
//
// The rules themselves are the server's — `required`, `min`/`max`,
// `minLength`/`maxLength`, `pattern`, and a `select`'s option set — and the
// server enforces them regardless. Checking locally buys the user an immediate,
// specific answer against the field they typed into, instead of a round-trip
// that comes back as a generic 400 with no idea which column was wrong.
//
// Two rules are deliberately **not** checked here:
//
//  - **`pattern`.** It is a server-side regular expression. Compiling it with
//    `NSRegularExpression` and rejecting a non-match would let this client
//    refuse a value the server accepts, whenever the two engines disagree on
//    syntax. A round-trip is the correct cost for the one rule we cannot
//    faithfully reproduce.
//  - **Anything about a column this build does not model.** An unrecognised
//    rule is left to the server rather than guessed at.
//
// Per Decision 0003 this type consumes only `InterlinedDomain`.

import Foundation
import InterlinedDomain

enum RowValueValidator {

    /// Why a value was refused, phrased for the field it belongs to.
    struct Failure: Equatable {
        /// The column key the failure belongs to, so the form can mark the row
        /// that caused it rather than the whole sheet.
        let key: String
        let message: String
    }

    /// Validates every cell of a row against `schema`.
    ///
    /// Returns every failure, not just the first: a form that reports one
    /// problem at a time makes the user submit repeatedly to discover the rest.
    static func failures(
        forRow fields: [String: ListCellValue],
        schema: ListSchema
    ) -> [Failure] {
        schema.orderedFields.compactMap { field in
            failure(for: fields[field.key] ?? .null, field: field)
                .map { Failure(key: field.key, message: $0) }
        }
    }

    /// Validates one cell. `nil` means it passes.
    static func failure(for value: ListCellValue, field: SchemaField) -> String? {
        let label = field.label.isEmpty ? field.key : field.label

        if isEmpty(value) {
            // Required is the only rule an absent value can break — a min
            // length on a field the user left blank is not a violation, it is
            // an empty optional field.
            return field.isRequired == true ? "\(label) is required." : nil
        }

        if let options = field.enumValues, !options.isEmpty,
           let chosen = textValue(value), !options.contains(chosen) {
            return "\(label) must be one of: \(options.joined(separator: ", "))."
        }

        if field.type.acceptsRangeRules, let number = numericValue(value) {
            if let min = field.validation?.min, number < min {
                return "\(label) must be at least \(trimmedNumber(min))."
            }
            if let max = field.validation?.max, number > max {
                return "\(label) must be at most \(trimmedNumber(max))."
            }
        }

        if field.type.acceptsLengthRules, let text = textValue(value) {
            if let minLength = field.validation?.minLength, text.count < minLength {
                return "\(label) must be at least \(minLength) characters."
            }
            if let maxLength = field.validation?.maxLength, text.count > maxLength {
                return "\(label) must be at most \(maxLength) characters."
            }
        }

        // `pattern` is intentionally not evaluated — see the file header.
        return nil
    }

    // MARK: - Helpers

    /// Whether a cell holds nothing. A whitespace-only string counts: the user
    /// meant to leave it blank, and treating it as a value would let a required
    /// field pass with a space in it.
    private static func isEmpty(_ value: ListCellValue) -> Bool {
        switch value {
        case .null: return true
        case .string(let text): return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .array(let items): return items.isEmpty
        case .object(let map): return map.isEmpty
        case .bool, .int, .double: return false
        }
    }

    /// The cell's text, for the rules that are about characters. Only a real
    /// string counts — coercing a number or a boolean into text here would
    /// apply a length rule to something that is not text.
    private static func textValue(_ value: ListCellValue) -> String? {
        if case .string(let text) = value { return text }
        return nil
    }

    /// A number from whichever numeric shape the cell holds. A `number` column
    /// whose value arrived as a string is still checked, because that is what a
    /// text field produces before a save coerces it.
    private static func numericValue(_ value: ListCellValue) -> Double? {
        switch value {
        case .int(let v): return Double(v)
        case .double(let v): return v
        case .string(let v): return Double(v.trimmingCharacters(in: .whitespaces))
        case .bool, .null, .array, .object: return nil
        }
    }

    /// Renders a bound without a spurious ".0" on a whole number.
    private static func trimmedNumber(_ value: Double) -> String {
        value == value.rounded() && abs(value) < 1e15 ? String(Int(value)) : String(value)
    }
}
