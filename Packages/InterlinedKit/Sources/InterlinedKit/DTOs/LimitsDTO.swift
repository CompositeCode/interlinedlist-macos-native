import Foundation

/// `GET /api/limits` response — machine-readable upload + message limits
/// (work-consolidation.md G14). Shape verified live 2026-07-31:
///
/// ```json
/// { "media": { "image": { "maxBytes": 1468006, "maxPixels": 1200,
///                         "acceptedFormats": ["jpeg","png","gif","webp"] },
///              "video": { "maxBytes": 3145728, "acceptedFormats": ["mp4","mov"] } },
///   "message": { "maxContentLength": 5000 } }
/// ```
///
/// Every field is modelled optional so a server that adds, renames, or drops a
/// sub-object still decodes without throwing; the domain mapper
/// (`ContentLimits.init(from:)`) fills any gap from `ContentLimits.default`.
public struct LimitsDTO: Decodable, Sendable, Equatable {
    public let media: MediaLimitsDTO?
    public let message: MessageLimitsDTO?

    public init(media: MediaLimitsDTO? = nil, message: MessageLimitsDTO? = nil) {
        self.media = media
        self.message = message
    }

    public struct MediaLimitsDTO: Decodable, Sendable, Equatable {
        public let image: ImageLimitsDTO?
        public let video: VideoLimitsDTO?

        public init(image: ImageLimitsDTO? = nil, video: VideoLimitsDTO? = nil) {
            self.image = image
            self.video = video
        }
    }

    public struct ImageLimitsDTO: Decodable, Sendable, Equatable {
        public let maxBytes: Int?
        public let maxPixels: Int?
        public let acceptedFormats: [String]?

        public init(maxBytes: Int? = nil, maxPixels: Int? = nil, acceptedFormats: [String]? = nil) {
            self.maxBytes = maxBytes
            self.maxPixels = maxPixels
            self.acceptedFormats = acceptedFormats
        }
    }

    public struct VideoLimitsDTO: Decodable, Sendable, Equatable {
        public let maxBytes: Int?
        public let acceptedFormats: [String]?

        public init(maxBytes: Int? = nil, acceptedFormats: [String]? = nil) {
            self.maxBytes = maxBytes
            self.acceptedFormats = acceptedFormats
        }
    }

    public struct MessageLimitsDTO: Decodable, Sendable, Equatable {
        public let maxContentLength: Int?

        public init(maxContentLength: Int? = nil) {
            self.maxContentLength = maxContentLength
        }
    }
}
