// ComposerAttachment
//
// A single pending media attachment in the composer (PLAN.md §1 "Media
// attachments", §6 M6). Holds the *local* file URL the user picked /
// dropped plus a discriminator so the upload pipeline knows whether to
// call `uploadImage` or `uploadVideo`. The thumbnail strip renders the
// local URL via SwiftUI `AsyncImage(url:)` (no AppKit — Decision 0005).
//
// Bytes are read lazily at send time, not held in memory while the user
// composes, so a large video doesn't bloat the editor's footprint.
//
// Per Decision 0003 this type consumes only `InterlinedDomain` (indeed
// only `Foundation` + `UniformTypeIdentifiers`).

import Foundation
import UniformTypeIdentifiers

/// Whether a picked file is an image or a video — selects the upload path.
enum ComposerAttachmentKind: Equatable, Sendable {
    case image
    case video

    /// Classifies a file URL by its uniform type. Defaults to `.image` when
    /// the type is unknown but the extension is a common image one; otherwise
    /// `nil` so the caller can reject unsupported files.
    static func classify(url: URL) -> ComposerAttachmentKind? {
        guard let type = UTType(filenameExtension: url.pathExtension.lowercased()) else {
            return nil
        }
        if type.conforms(to: .image) { return .image }
        if type.conforms(to: .movie) || type.conforms(to: .video) { return .video }
        return nil
    }
}

/// One pending attachment: a local file URL plus its kind. `Identifiable`
/// so the SwiftUI thumbnail strip can `ForEach` over it and offer a remove
/// affordance keyed by id.
struct ComposerAttachment: Identifiable, Equatable, Sendable {
    let id: UUID
    let url: URL
    let kind: ComposerAttachmentKind

    init(id: UUID = UUID(), url: URL, kind: ComposerAttachmentKind) {
        self.id = id
        self.url = url
        self.kind = kind
    }

    /// Builds an attachment by classifying the URL. Returns `nil` for an
    /// unsupported file type so the caller surfaces a clear rejection rather
    /// than queueing bytes the server can't take.
    init?(url: URL) {
        guard let kind = ComposerAttachmentKind.classify(url: url) else { return nil }
        self.init(url: url, kind: kind)
    }

    /// The MIME content type for a video upload. Derived from the file
    /// extension; defaults to `video/mp4` when the type can't be resolved.
    var videoContentType: String {
        guard
            let type = UTType(filenameExtension: url.pathExtension.lowercased()),
            let mime = type.preferredMIMEType
        else {
            return "video/mp4"
        }
        return mime
    }
}
