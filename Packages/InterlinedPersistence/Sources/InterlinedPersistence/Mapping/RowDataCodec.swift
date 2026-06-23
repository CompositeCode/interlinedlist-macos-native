import Foundation
import InterlinedDomain

/// Package-private JSON codec for the dynamic-schema row data
/// (`[String: ListCellValue]`).
///
/// The domain layer's `ListCellValue` is intentionally not `Codable` — the
/// only place row JSON crosses a boundary today is the InterlinedKit wire
/// (where `ListJSONValue` handles round-tripping). Persisting rows in
/// SwiftData needs its own JSON-blob serialization, but the persistence
/// package depends only on `InterlinedDomain`. Rather than reach across to
/// the kit, this codec re-encodes the domain value through a local Codable
/// proxy that mirrors `ListJSONValue` byte-for-byte.
///
/// Storing the JSON shape (rather than a Swift-specific binary format)
/// keeps the on-disk representation portable across future schema
/// migrations and matches what production already serializes on the wire.
enum RowDataCodec {

    static func encode(_ fields: [String: ListCellValue]) throws -> Data {
        let wire = fields.mapValues(WireJSONValue.init(from:))
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(wire)
    }

    static func decode(_ data: Data) throws -> [String: ListCellValue] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let wire = try decoder.decode([String: WireJSONValue].self, from: data)
        return wire.mapValues(ListCellValue.init(from:))
    }
}

// MARK: - WireJSONValue (package-internal)

/// Persistence-local mirror of `InterlinedKit.ListJSONValue`. Kept separate
/// so this package does not need to depend on `InterlinedKit` just for the
/// JSON shape. Lossless round-trip with `ListCellValue`.
private enum WireJSONValue: Codable, Sendable, Equatable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([WireJSONValue])
    case object([String: WireJSONValue])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null; return }
        if let v = try? container.decode(Bool.self) { self = .bool(v); return }
        if let v = try? container.decode(Int.self) { self = .int(v); return }
        if let v = try? container.decode(Double.self) { self = .double(v); return }
        if let v = try? container.decode(String.self) { self = .string(v); return }
        if let v = try? container.decode([WireJSONValue].self) { self = .array(v); return }
        if let v = try? container.decode([String: WireJSONValue].self) { self = .object(v); return }
        throw DecodingError.dataCorruptedError(
            in: container,
            debugDescription: "Unsupported JSON value in cached row data"
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let v): try container.encode(v)
        case .int(let v): try container.encode(v)
        case .double(let v): try container.encode(v)
        case .string(let v): try container.encode(v)
        case .array(let v): try container.encode(v)
        case .object(let v): try container.encode(v)
        }
    }

    /// Project a domain `ListCellValue` into the local wire shape.
    init(from value: ListCellValue) {
        switch value {
        case .null: self = .null
        case .bool(let v): self = .bool(v)
        case .int(let v): self = .int(v)
        case .double(let v): self = .double(v)
        case .string(let v): self = .string(v)
        case .array(let items): self = .array(items.map(WireJSONValue.init(from:)))
        case .object(let dict): self = .object(dict.mapValues(WireJSONValue.init(from:)))
        }
    }
}

extension ListCellValue {
    /// Inverse projection — package-private so the codec can hydrate the
    /// domain value without exposing the wire enum.
    fileprivate init(from value: WireJSONValue) {
        switch value {
        case .null: self = .null
        case .bool(let v): self = .bool(v)
        case .int(let v): self = .int(v)
        case .double(let v): self = .double(v)
        case .string(let v): self = .string(v)
        case .array(let items): self = .array(items.map(ListCellValue.init(from:)))
        case .object(let dict): self = .object(dict.mapValues(ListCellValue.init(from:)))
        }
    }
}
