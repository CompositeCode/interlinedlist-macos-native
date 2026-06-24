import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// MARK: - ImageFormat

/// Format an image is encoded in. Closed set the prep pipeline can produce.
public enum ImageFormat: String, Sendable, Equatable, CaseIterable {
    case png
    case jpeg
    case heic

    /// UTI string used by `CGImageDestination` for this format.
    public var uti: String {
        switch self {
        case .png:  return UTType.png.identifier
        case .jpeg: return UTType.jpeg.identifier
        case .heic: return UTType.heic.identifier
        }
    }

    /// MIME type used by the multipart uploader. Kept here so the App layer
    /// doesn't have to translate the enum twice.
    public var mimeType: String {
        switch self {
        case .png:  return "image/png"
        case .jpeg: return "image/jpeg"
        case .heic: return "image/heic"
        }
    }
}

// MARK: - PreparedImage

/// The output of `ImagePrep.prepare`. The bytes are guaranteed to be within
/// `ImagePrep.maxBytes` and dimensions within `ImagePrep.maxLongestEdgePixels`
/// when the call returns successfully.
public struct PreparedImage: Sendable, Equatable {
    public let data: Data
    public let format: ImageFormat
    public let byteCount: Int
    public let dimensions: CGSize
    public let wasResized: Bool
    public let wasLossyCompressed: Bool
    /// The final JPEG quality used, if the lossy step ran. `nil` when the
    /// final encoding was lossless (PNG / HEIC pass-through or re-encode).
    public let finalQuality: Double?

    public init(
        data: Data,
        format: ImageFormat,
        byteCount: Int,
        dimensions: CGSize,
        wasResized: Bool,
        wasLossyCompressed: Bool,
        finalQuality: Double?
    ) {
        self.data = data
        self.format = format
        self.byteCount = byteCount
        self.dimensions = dimensions
        self.wasResized = wasResized
        self.wasLossyCompressed = wasLossyCompressed
        self.finalQuality = finalQuality
    }
}

// MARK: - ImagePrepError

/// Errors surfaced from `ImagePrep.prepare`.
public enum ImagePrepError: Error, Sendable, Equatable {

    /// The raw bytes didn't parse as any image format `ImageIO` understands.
    case undecodable

    /// Could not determine the source image's pixel dimensions — defensive,
    /// indicates a malformed source even if `CGImageSource` accepted it.
    case missingDimensions

    /// `CGImageDestination` failed to encode the result in every format the
    /// pipeline tried. Distinct from `tooLargeAfterAllAttempts`: this is an
    /// encoder failure, not a size budget failure.
    case encodingFailed

    /// Every quality-stepdown attempt still exceeded `maxBytes`. Rare with
    /// reasonably-sized starting images.
    case tooLargeAfterAllAttempts
}

// MARK: - ImagePrep

/// Pre-upload image preparation: enforce the InterlinedList image limits
/// (≤ 1.4 MB, longest edge ≤ 1200 px), preferring lossless recompression
/// over JPEG quality stepdown.
///
/// This lives in `InterlinedDomain` because it is request-preparation logic
/// (the kit just forwards bytes to `Documents.uploadImage`). It uses only
/// `CoreGraphics` / `ImageIO` — never AppKit — so it stays usable from
/// background actors and from non-UI contexts.
public enum ImagePrep {

    // MARK: - Public limits

    /// Maximum bytes accepted by the API. Public so callers can render a
    /// preview limit indicator; settable via future overload (today static).
    public static let maxBytes: Int = 1_468_006

    /// Maximum pixels on the longest edge before the resize step runs.
    public static let maxLongestEdgePixels: CGFloat = 1200

    /// Quality stepdown ladder for the JPEG fallback leg. Tried in order
    /// until one fits under `maxBytes`.
    public static let qualityLadder: [Double] = [0.9, 0.8, 0.7, 0.6, 0.5]

    // MARK: - prepare

    /// Pre-process raw image bytes for upload.
    ///
    /// Pipeline (each step skipped when the previous output already fits):
    /// 1. Decode + measure dimensions.
    /// 2. If dimensions exceed `maxLongestEdgePixels`, downscale.
    /// 3. If byte budget exceeded, **lossless** re-encode (try HEIC if
    ///    available, then re-encoded PNG).
    /// 4. If still over budget, **lossy** JPEG with quality stepdown
    ///    through `qualityLadder`.
    ///
    /// Throws `ImagePrepError.tooLargeAfterAllAttempts` only when the
    /// smallest viable quality still exceeds `maxBytes`.
    public static func prepare(_ raw: Data) throws -> PreparedImage {
        guard let source = CGImageSourceCreateWithData(raw as CFData, nil),
              CGImageSourceGetCount(source) > 0 else {
            throw ImagePrepError.undecodable
        }
        guard let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw ImagePrepError.undecodable
        }

        let originalSize = CGSize(width: cgImage.width, height: cgImage.height)
        guard originalSize.width > 0, originalSize.height > 0 else {
            throw ImagePrepError.missingDimensions
        }

        let sourceFormat = detectFormat(source) ?? .jpeg

        // Step 1: passthrough — small enough already, in a supported format.
        let originalIsSupported = ImageFormat.allCases.contains(sourceFormat)
        if originalIsSupported,
           raw.count <= maxBytes,
           max(originalSize.width, originalSize.height) <= maxLongestEdgePixels {
            return PreparedImage(
                data: raw,
                format: sourceFormat,
                byteCount: raw.count,
                dimensions: originalSize,
                wasResized: false,
                wasLossyCompressed: false,
                finalQuality: nil
            )
        }

        // Step 2: downscale if oversized in pixels.
        let resizedImage: CGImage
        let resizedDimensions: CGSize
        let wasResized: Bool
        if max(originalSize.width, originalSize.height) > maxLongestEdgePixels {
            guard let scaled = downscale(cgImage, longestEdge: maxLongestEdgePixels) else {
                throw ImagePrepError.encodingFailed
            }
            resizedImage = scaled
            resizedDimensions = CGSize(width: scaled.width, height: scaled.height)
            wasResized = true
        } else {
            resizedImage = cgImage
            resizedDimensions = originalSize
            wasResized = false
        }

        // Step 3a: lossless re-encode — try HEIC if available, then PNG.
        for format in [ImageFormat.heic, .png] {
            guard let encoded = encode(resizedImage, format: format, quality: nil) else {
                continue
            }
            if encoded.count <= maxBytes {
                return PreparedImage(
                    data: encoded,
                    format: format,
                    byteCount: encoded.count,
                    dimensions: resizedDimensions,
                    wasResized: wasResized,
                    wasLossyCompressed: false,
                    finalQuality: nil
                )
            }
        }

        // Step 3b: lossy JPEG with quality stepdown.
        var encodingFailures = 0
        for quality in qualityLadder {
            guard let encoded = encode(resizedImage, format: .jpeg, quality: quality) else {
                encodingFailures += 1
                continue
            }
            if encoded.count <= maxBytes {
                return PreparedImage(
                    data: encoded,
                    format: .jpeg,
                    byteCount: encoded.count,
                    dimensions: resizedDimensions,
                    wasResized: wasResized,
                    wasLossyCompressed: true,
                    finalQuality: quality
                )
            }
        }

        // Distinguish "encoder broke" from "image too big".
        if encodingFailures == qualityLadder.count {
            throw ImagePrepError.encodingFailed
        }
        throw ImagePrepError.tooLargeAfterAllAttempts
    }

    // MARK: - Internals

    /// Detect the source's container format from its image-source UTI.
    private static func detectFormat(_ source: CGImageSource) -> ImageFormat? {
        guard let utiCF = CGImageSourceGetType(source) else { return nil }
        let uti = utiCF as String
        if uti == UTType.png.identifier  { return .png }
        if uti == UTType.jpeg.identifier { return .jpeg }
        if uti == UTType.heic.identifier { return .heic }
        return nil
    }

    /// Downscale `image` so its longest edge is at most `longestEdge` pixels,
    /// preserving aspect ratio. Returns the original when it already fits.
    private static func downscale(_ image: CGImage, longestEdge: CGFloat) -> CGImage? {
        let width = CGFloat(image.width)
        let height = CGFloat(image.height)
        let longest = max(width, height)
        if longest <= longestEdge { return image }
        let scale = longestEdge / longest
        let newWidth = max(1, Int((width * scale).rounded()))
        let newHeight = max(1, Int((height * scale).rounded()))

        // Build a fresh bitmap context with the target dimensions. Use the
        // sRGB color space + 32-bit premultipliedFirst to match the broadest
        // set of source images on macOS.
        let colorSpace = image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!
        let bitmapInfo: UInt32 = CGImageAlphaInfo.premultipliedFirst.rawValue
            | CGImageByteOrderInfo.order32Little.rawValue
        guard let context = CGContext(
            data: nil,
            width: newWidth,
            height: newHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            return nil
        }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: newWidth, height: newHeight))
        return context.makeImage()
    }

    /// Encode a `CGImage` to bytes in `format`. For lossy formats (JPEG)
    /// pass `quality` in `[0,1]`. Returns `nil` on encoder failure.
    private static func encode(
        _ image: CGImage,
        format: ImageFormat,
        quality: Double?
    ) -> Data? {
        let mutableData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            mutableData,
            format.uti as CFString,
            1,
            nil
        ) else {
            return nil
        }
        var properties: [CFString: Any] = [:]
        if let quality {
            properties[kCGImageDestinationLossyCompressionQuality] = quality
        }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            return nil
        }
        return mutableData as Data
    }
}
