import Foundation
import CryptoKit

/// Stable content hashing used to detect local edits independent of filesystem
/// modification timestamps (which are unreliable across editors and copies).
public enum ContentHash {
    /// SHA-256 hex digest of the UTF-8 bytes of `string`.
    public static func sha256(_ string: String) -> String {
        let digest = SHA256.hash(data: Data(string.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
