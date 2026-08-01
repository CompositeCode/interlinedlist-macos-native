import Foundation
import os

/// One `.md` file discovered on disk during a scan.
public struct ScannedDocument: Sendable, Equatable {
    public let url: URL
    /// Server id read from the sync xattr; `nil` means untracked (a new local doc).
    public let documentID: String?
    public let title: String
    public let body: String
    public let modifiedAt: Date
    public let contentHash: String
    /// Folder path relative to the sync root (`""` for a root-level file).
    public let folderRelativePath: String

    public var isTracked: Bool { documentID != nil }
}

/// Maps InterlinedList documents to a mirrored tree of Markdown files and back.
///
/// Correlation is by extended attribute (``SyncConfiguration/documentIDAttribute``)
/// so a file keeps its identity across renames and moves inside the folder.
/// Folders are mirrored as directories; filenames are the sanitized document
/// title plus `.md`, disambiguated with a short id suffix on collision.
public struct DocumentMapper: Sendable {

    public enum MapperError: Error, Sendable, Equatable {
        case notUTF8(String)
    }

    public let rootURL: URL
    private var fm: FileManager { .default }
    private let logger = Logger(subsystem: SyncConfiguration.logSubsystem, category: "DocumentMapper")

    public init(rootURL: URL) {
        self.rootURL = rootURL
    }

    // MARK: - Scan

    /// Recursively enumerates `.md` files under the root, skipping dotfiles and
    /// conflict copies. Returns tracked (with xattr id) and untracked files.
    public func scan() throws -> [ScannedDocument] {
        guard let enumerator = fm.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var results: [ScannedDocument] = []
        for case let fileURL as URL in enumerator {
            guard fileURL.pathExtension.lowercased() == "md" else { continue }
            guard !isConflictCopy(fileURL) else { continue }
            let isRegular = (try? fileURL.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile ?? false
            guard isRegular else { continue }

            let body: String
            do {
                body = try String(contentsOf: fileURL, encoding: .utf8)
            } catch {
                logger.error("Skipping unreadable file \(fileURL.lastPathComponent, privacy: .public)")
                continue
            }
            let modifiedAt = (try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate ?? Date(timeIntervalSince1970: 0)

            results.append(
                ScannedDocument(
                    url: fileURL,
                    documentID: documentID(at: fileURL),
                    title: fileURL.deletingPathExtension().lastPathComponent,
                    body: body,
                    modifiedAt: modifiedAt,
                    contentHash: ContentHash.sha256(body),
                    folderRelativePath: folderRelativePath(of: fileURL)
                )
            )
        }
        return results
    }

    // MARK: - Placement

    /// Writes `content` for document `id` (titled `title`) into the mirrored
    /// folder path, updating `currentURL` in place (renaming/moving as needed).
    /// Returns the final on-disk URL.
    @discardableResult
    public func place(
        id: String,
        title: String,
        content: String,
        folderRelativePath: String,
        currentURL: URL?
    ) throws -> URL {
        let folderURL = try ensureFolder(relativePath: folderRelativePath)
        let desired = disambiguatedURL(
            in: folderURL,
            baseName: sanitizeFilename(title),
            id: id
        )

        if let currentURL, currentURL != desired {
            // Title/folder changed → move the existing file first.
            try? fm.removeItem(at: desired) // desired is guaranteed free-or-same-id by disambiguation
            if fm.fileExists(atPath: currentURL.path) {
                try fm.moveItem(at: currentURL, to: desired)
            }
        }

        try writeAtomically(content: content, to: desired)
        setDocumentID(id, at: desired)
        return desired
    }

    /// Writes a brand-new local file's server id onto it after creation.
    public func adopt(id: String, at url: URL) {
        setDocumentID(id, at: url)
    }

    public func removeFile(at url: URL) {
        try? fm.removeItem(at: url)
    }

    /// Preserves the current local body as `<base>.conflict-<yyyyMMdd-HHmmss>.md`
    /// next to the original, then returns the conflict-copy URL.
    @discardableResult
    public func writeConflictCopy(of originalURL: URL, body: String, at date: Date) throws -> URL {
        let base = originalURL.deletingPathExtension().lastPathComponent
        let dir = originalURL.deletingLastPathComponent()
        let stamp = Self.conflictTimestamp(date)
        var copyURL = dir.appendingPathComponent("\(base).\(SyncConfiguration.conflictInfix)\(stamp).md")
        var counter = 1
        while fm.fileExists(atPath: copyURL.path) {
            copyURL = dir.appendingPathComponent("\(base).\(SyncConfiguration.conflictInfix)\(stamp)-\(counter).md")
            counter += 1
        }
        try writeAtomically(content: body, to: copyURL)
        return copyURL
    }

    // MARK: - Folder helpers

    /// Ensures the mirrored directory for `relativePath` exists; returns its URL.
    @discardableResult
    public func ensureFolder(relativePath: String) throws -> URL {
        let folderURL = relativePath.isEmpty
            ? rootURL
            : rootURL.appendingPathComponent(relativePath, isDirectory: true)
        if !fm.fileExists(atPath: folderURL.path) {
            try fm.createDirectory(at: folderURL, withIntermediateDirectories: true)
        }
        return folderURL
    }

    /// Full path of `fileURL` relative to the root, including the filename
    /// (e.g. `Projects/Alpha/Note.md`). Used as a fallback correlation key when
    /// an atomic save strips the xattr id.
    public func relativeFilePath(of fileURL: URL) -> String {
        let folder = folderRelativePath(of: fileURL)
        let name = fileURL.lastPathComponent
        return folder.isEmpty ? name : "\(folder)/\(name)"
    }

    /// Folder path of `fileURL` relative to the root (`""` at root level).
    public func folderRelativePath(of fileURL: URL) -> String {
        let dir = fileURL.deletingLastPathComponent().standardizedFileURL
        let root = rootURL.standardizedFileURL
        guard dir.path.hasPrefix(root.path) else { return "" }
        let suffix = String(dir.path.dropFirst(root.path.count))
        return suffix.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    // MARK: - xattr

    public func documentID(at url: URL) -> String? {
        readXattr(SyncConfiguration.documentIDAttribute, at: url)
    }

    public func setDocumentID(_ id: String, at url: URL) {
        writeXattr(SyncConfiguration.documentIDAttribute, value: id, at: url)
    }

    // MARK: - Naming

    /// Replaces path-hostile characters and trims to a safe filename base.
    public func sanitizeFilename(_ title: String) -> String {
        let illegal = CharacterSet(charactersIn: "/\\:?%*|\"<>")
        var cleaned = title
            .components(separatedBy: illegal)
            .joined(separator: "-")
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // Avoid leading dots (hidden files) and empty names.
        while cleaned.hasPrefix(".") { cleaned.removeFirst() }
        if cleaned.isEmpty { cleaned = "Untitled" }
        if cleaned.count > 180 { cleaned = String(cleaned.prefix(180)) }
        return cleaned
    }

    func isConflictCopy(_ url: URL) -> Bool {
        url.deletingPathExtension().lastPathComponent.contains(".\(SyncConfiguration.conflictInfix)")
    }

    static func conflictTimestamp(_ date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        return String(
            format: "%04d%02d%02d-%02d%02d%02d",
            c.year ?? 0, c.month ?? 0, c.day ?? 0, c.hour ?? 0, c.minute ?? 0, c.second ?? 0
        )
    }

    // MARK: - Private

    /// Picks a filename that doesn't collide with a *different* document's file.
    private func disambiguatedURL(in folderURL: URL, baseName: String, id: String) -> URL {
        let candidate = folderURL.appendingPathComponent("\(baseName).md")
        if !fm.fileExists(atPath: candidate.path) || documentID(at: candidate) == id {
            return candidate
        }
        // Collision with a different id → append a short id suffix.
        let shortID = String(id.replacingOccurrences(of: "/", with: "").suffix(6))
        return folderURL.appendingPathComponent("\(baseName) (\(shortID)).md")
    }

    private func writeAtomically(content: String, to url: URL) throws {
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    private func readXattr(_ name: String, at url: URL) -> String? {
        url.withUnsafeFileSystemRepresentation { pathPtr -> String? in
            guard let pathPtr else { return nil }
            let length = getxattr(pathPtr, name, nil, 0, 0, 0)
            guard length > 0 else { return nil }
            var data = Data(count: length)
            let read = data.withUnsafeMutableBytes {
                getxattr(pathPtr, name, $0.baseAddress, length, 0, 0)
            }
            guard read > 0 else { return nil }
            return String(data: data.prefix(read), encoding: .utf8)
        }
    }

    private func writeXattr(_ name: String, value: String, at url: URL) {
        let bytes = Data(value.utf8)
        _ = url.withUnsafeFileSystemRepresentation { pathPtr -> Int32 in
            guard let pathPtr else { return -1 }
            return bytes.withUnsafeBytes {
                setxattr(pathPtr, name, $0.baseAddress, bytes.count, 0, 0)
            }
        }
    }
}
