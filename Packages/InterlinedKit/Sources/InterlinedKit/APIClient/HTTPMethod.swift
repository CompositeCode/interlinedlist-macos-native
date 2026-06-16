import Foundation

/// HTTP verbs used by the InterlinedList API.
///
/// Modelled as an enum so request construction is type-safe at the call site
/// and impossible-method bugs are caught by the compiler.
public enum HTTPMethod: String, Sendable, Equatable {
    case get    = "GET"
    case post   = "POST"
    case put    = "PUT"
    case patch  = "PATCH"
    case delete = "DELETE"
}
