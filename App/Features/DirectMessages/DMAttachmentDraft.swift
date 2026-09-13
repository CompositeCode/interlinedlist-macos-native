// DMAttachmentDraft
//
// The photo-attachment half of a DM composer (work-consolidation.md G22),
// factored out so `DMThreadViewModel` and `NewMessageViewModel` share one
// implementation of the picking rules and one upload loop instead of two
// drifting copies.
//
// What the help docs specify, and what this enforces:
//   • "You can attach photos to a direct message, up to 8 per message."
//     → `DMLimits.maxImagesPerMessage`, refused client-side at pick time so
//       a 9th file never reaches the server.
//   • Photos only. DMs have no video route, so a picked movie is rejected
//     with an explanation rather than silently dropped.
//   • "Photos are resized automatically." → the resize happens in
//     `DirectMessagesService.uploadImage` via the shared `ImagePrep` +
//     `ContentLimits` path, not here and not with fresh constants.
//   • "You'll need a verified email address to send images." → NOT checked
//     here. The server's 403 carries the canonical wording and is surfaced
//     verbatim. TODO(#41): issue #41 builds `CapabilityGate`
//     (status → email verification → tier); when it merges, the composers
//     should consult it to explain the refusal before the user picks a
//     file. One gate, one owner — do not add a second check here.
//
// The upload loop is deliberately failure-tolerant: an upload that fails
// must not cost the user their draft. Successful uploads are kept, the
// first failure is returned for display, and the caller decides whether the
// message can still go out as text.
//
// Reuses `ComposerAttachment` (the post composer's local-file value type)
// rather than introducing a parallel one; DMs simply reject its `.video`
// kind.
//
// Per decision 0003, this consumes only `InterlinedDomain`.

import Foundation
import InterlinedDomain

// MARK: - DMAttachmentError

/// Why a picked file was refused, before anything was uploaded.
enum DMAttachmentError: Error, Equatable {
    /// One or more picked files were not images. DMs take photos only.
    case notAnImage
    /// The pick would exceed the documented per-message photo cap.
    case tooMany(limit: Int)
}

extension DMAttachmentError: LocalizedError, CustomStringConvertible {
    var errorDescription: String? { description }
    var description: String {
        switch self {
        case .notAnImage:
            return "Only photos can be attached to a direct message."
        case .tooMany(let limit):
            return "You can attach up to \(limit) photos to a direct message."
        }
    }
}

// MARK: - DMAttachmentUploadResult

/// Outcome of uploading a draft's photos.
struct DMAttachmentUploadResult: Sendable {
    /// Hosted URLs for the photos that uploaded successfully, in pick order.
    let urls: [String]
    /// The first failure encountered, if any. Surfaced to the user while the
    /// message itself may still send.
    let failure: Error?
    /// How many photos failed to upload.
    let failedCount: Int
}

// MARK: - DMAttachmentDraft

/// The pending photos on one DM composer. A value type: the owning view
/// model holds it and mutates it in place.
struct DMAttachmentDraft: Equatable, Sendable {

    /// Pending photos, in pick order. Local file URLs — bytes are read at
    /// send time, so a big pick doesn't sit in memory while composing.
    private(set) var attachments: [ComposerAttachment] = []

    /// How many more photos this message can take.
    var remainingSlots: Int {
        max(0, DMLimits.maxImagesPerMessage - attachments.count)
    }

    /// Whether the documented per-message cap is reached.
    var isFull: Bool { remainingSlots == 0 }

    var isEmpty: Bool { attachments.isEmpty }

    /// Adds picked / dropped file URLs, keeping only images and only up to
    /// the cap. Returns the reason any file was refused, or `nil` when all
    /// were accepted.
    ///
    /// Partial acceptance is deliberate: picking ten photos onto an empty
    /// draft attaches eight and explains the two that didn't fit, rather
    /// than discarding the whole pick.
    mutating func add(urls: [URL]) -> DMAttachmentError? {
        var sawNonImage = false
        var overflowed = false
        for url in urls {
            guard let attachment = ComposerAttachment(url: url),
                  attachment.kind == .image else {
                sawNonImage = true
                continue
            }
            guard !isFull else {
                overflowed = true
                continue
            }
            attachments.append(attachment)
        }
        // The cap is the more actionable message when both apply — it names a
        // number the user can act on.
        if overflowed { return .tooMany(limit: DMLimits.maxImagesPerMessage) }
        if sawNonImage { return .notAnImage }
        return nil
    }

    /// Removes one pending photo by id.
    mutating func remove(id: ComposerAttachment.ID) {
        attachments.removeAll { $0.id == id }
    }

    /// Clears the draft — called after a successful send.
    mutating func removeAll() {
        attachments.removeAll()
    }

    /// Uploads every pending photo and returns their hosted URLs.
    ///
    /// Failure-tolerant by design: a failed upload does not abort the rest
    /// and does not throw. The caller keeps the successful URLs, shows
    /// `failure`, and decides whether the message can still be sent as text
    /// — which is the behaviour the user needs, because losing a typed draft
    /// to a flaky upload is worse than sending without one photo.
    func upload(
        using service: DirectMessagesServicing,
        readData: @Sendable (URL) async throws -> Data
    ) async -> DMAttachmentUploadResult {
        var urls: [String] = []
        var failure: Error?
        var failedCount = 0
        for attachment in attachments {
            do {
                let bytes = try await readData(attachment.url)
                urls.append(try await service.uploadImage(bytes))
            } catch {
                failedCount += 1
                if failure == nil { failure = error }
            }
        }
        return DMAttachmentUploadResult(urls: urls, failure: failure, failedCount: failedCount)
    }
}
