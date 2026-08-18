import Foundation
import CoreGraphics
import InterlinedKit

/// Server-authoritative upload + message limits (work-consolidation.md G14) —
/// the domain projection of `LimitsDTO`. Drives the composer's message-length
/// validation and, for display, the media size / pixel ceilings.
///
/// `default` mirrors the values the live API returned on 2026-07-31 and the
/// constants baked into `ImagePrep`, so the app validates sensibly *before* the
/// live limits have been fetched — and if the fetch ever fails.
public struct ContentLimits: Sendable, Equatable {
    public let imageMaxBytes: Int
    public let imageMaxPixels: Int
    public let imageAcceptedFormats: [String]
    public let videoMaxBytes: Int
    public let videoAcceptedFormats: [String]
    public let messageMaxContentLength: Int

    public init(
        imageMaxBytes: Int,
        imageMaxPixels: Int,
        imageAcceptedFormats: [String],
        videoMaxBytes: Int,
        videoAcceptedFormats: [String],
        messageMaxContentLength: Int
    ) {
        self.imageMaxBytes = imageMaxBytes
        self.imageMaxPixels = imageMaxPixels
        self.imageAcceptedFormats = imageAcceptedFormats
        self.videoMaxBytes = videoMaxBytes
        self.videoAcceptedFormats = videoAcceptedFormats
        self.messageMaxContentLength = messageMaxContentLength
    }

    /// The built-in defaults — verified live 2026-07-31 and kept in step with
    /// the `ImagePrep` constants (image ≤ 1.4 MB / 1200 px; video ≤ 3 MB;
    /// message ≤ 5000 chars). `acceptedFormats` deliberately excludes `heic`:
    /// the live server did not list it.
    public static let `default` = ContentLimits(
        imageMaxBytes: 1_468_006,
        imageMaxPixels: 1200,
        imageAcceptedFormats: ["jpeg", "png", "gif", "webp"],
        videoMaxBytes: 3_145_728,
        videoAcceptedFormats: ["mp4", "mov"],
        messageMaxContentLength: 5000
    )
}

public extension ContentLimits {

    /// The image size ceilings projected into the `ImagePrep` pipeline's own
    /// limit type (work-consolidation.md G14 tail) — so the pre-upload prep is
    /// driven by the live `GET /api/limits` values instead of `ImagePrep`'s
    /// hard-coded constants.
    var imagePrepLimits: ImagePrep.Limits {
        ImagePrep.Limits(
            maxBytes: imageMaxBytes,
            maxLongestEdgePixels: CGFloat(imageMaxPixels)
        )
    }

    /// Maps a decoded `LimitsDTO`, falling back to `default` for any field the
    /// server omits so a partial payload never yields a zero (and therefore
    /// unusable) limit.
    init(from dto: LimitsDTO) {
        let fallback = ContentLimits.default
        self.init(
            imageMaxBytes: dto.media?.image?.maxBytes ?? fallback.imageMaxBytes,
            imageMaxPixels: dto.media?.image?.maxPixels ?? fallback.imageMaxPixels,
            imageAcceptedFormats: dto.media?.image?.acceptedFormats ?? fallback.imageAcceptedFormats,
            videoMaxBytes: dto.media?.video?.maxBytes ?? fallback.videoMaxBytes,
            videoAcceptedFormats: dto.media?.video?.acceptedFormats ?? fallback.videoAcceptedFormats,
            messageMaxContentLength: dto.message?.maxContentLength ?? fallback.messageMaxContentLength
        )
    }
}
