import Foundation

/// Security-scoped bookmark helpers so the sandboxed agent can keep read/write
/// access to the user-chosen sync folder across relaunches.
public enum SecurityScopedAccess {

    /// Creates an app-scoped security bookmark for a user-selected folder.
    public static func makeBookmark(for url: URL) -> Data? {
        try? url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    /// Resolves a stored bookmark back to a URL. Returns the URL and whether the
    /// bookmark is stale (should be recreated). The caller is responsible for
    /// calling `startAccessingSecurityScopedResource()`.
    public static func resolve(_ data: Data) -> (url: URL, isStale: Bool)? {
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else { return nil }
        return (url, isStale)
    }
}
