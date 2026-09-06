import Foundation

/// A losslessly round-trippable JSON value for app-settings payloads.
///
/// Named distinctly rather than `AppSettingsValue` because InterlinedKit already has
/// an internal `AppSettingsValue` (pagination-envelope probing) and a `ListJSONValue`
/// (list row cells); this follows that same per-domain precedent instead of
/// widening a shared type.
///
/// Added for the app-settings surface (work-consolidation.md G17), where the
/// server stores an **opaque, app-defined settings blob**: the platform does not
/// know or validate our schema, it just persists what we PUT and returns it
/// unchanged. Modelling that as a concrete struct would silently drop any key
/// this client version does not know about — including keys written by a *newer*
/// build of the app on another machine, which is exactly the data synced
/// settings must not lose.
///
/// `AppSettingsValue` therefore preserves the whole payload verbatim. The domain layer
/// projects the keys it understands out of it and writes them back into the
/// same container, leaving unknown keys untouched.
public enum AppSettingsValue: Codable, Sendable, Equatable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([AppSettingsValue])
    case object([String: AppSettingsValue])

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null; return }
        if let v = try? c.decode(Bool.self) { self = .bool(v); return }
        if let v = try? c.decode(Double.self) { self = .number(v); return }
        if let v = try? c.decode(String.self) { self = .string(v); return }
        if let v = try? c.decode([AppSettingsValue].self) { self = .array(v); return }
        if let v = try? c.decode([String: AppSettingsValue].self) { self = .object(v); return }
        throw DecodingError.dataCorruptedError(in: c, debugDescription: "Unrecognised JSON value")
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null:            try c.encodeNil()
        case .bool(let v):     try c.encode(v)
        case .number(let v):   try c.encode(v)
        case .string(let v):   try c.encode(v)
        case .array(let v):    try c.encode(v)
        case .object(let v):   try c.encode(v)
        }
    }

    // MARK: - Typed accessors
    //
    // Convenience readers so the domain layer can pull known keys out of an
    // opaque blob without pattern-matching at every call site. Each returns nil
    // when the value is absent or of a different type — never traps.

    public var boolValue: Bool? { if case .bool(let v) = self { return v }; return nil }
    public var stringValue: String? { if case .string(let v) = self { return v }; return nil }
    public var intValue: Int? { if case .number(let v) = self { return Int(v) }; return nil }
    public var doubleValue: Double? { if case .number(let v) = self { return v }; return nil }
    public var objectValue: [String: AppSettingsValue]? { if case .object(let v) = self { return v }; return nil }
    public var arrayValue: [AppSettingsValue]? { if case .array(let v) = self { return v }; return nil }

    /// Subscript into an object value. Returns nil for non-objects.
    public subscript(key: String) -> AppSettingsValue? {
        guard case .object(let dict) = self else { return nil }
        return dict[key]
    }
}
