import XCTest
import InterlinedKit
@testable import InterlinedDomain

/// BDD-named coverage for `ContentLimitsService` + the `ContentLimits` mapper
/// (work-consolidation.md G14).
final class ContentLimitsServiceTests: XCTestCase {

    func test_givenFullBody_whenFetching_thenMapsEveryField() async {
        let api = StubAPIClient()
        await api.enqueue(json: #"""
        { "media": { "image": { "maxBytes": 1468006, "maxPixels": 1200,
                                "acceptedFormats": ["jpeg","png","gif","webp"] },
                     "video": { "maxBytes": 3145728, "acceptedFormats": ["mp4","mov"] } },
          "message": { "maxContentLength": 5000 } }
        """#)
        let service = ContentLimitsService(api: api)

        let limits = await service.limits()

        XCTAssertEqual(limits.imageMaxBytes, 1_468_006)
        XCTAssertEqual(limits.imageMaxPixels, 1200)
        XCTAssertEqual(limits.imageAcceptedFormats, ["jpeg", "png", "gif", "webp"])
        XCTAssertEqual(limits.videoMaxBytes, 3_145_728)
        XCTAssertEqual(limits.videoAcceptedFormats, ["mp4", "mov"])
        XCTAssertEqual(limits.messageMaxContentLength, 5000)
        let recorded = await api.recorded
        XCTAssertEqual(recorded.first?.path, "/api/limits")
    }

    func test_givenPartialBody_whenFetching_thenMissingFieldsUseDefaults() async {
        let api = StubAPIClient()
        await api.enqueue(json: #"{ "message": { "maxContentLength": 4000 } }"#)
        let service = ContentLimitsService(api: api)

        let limits = await service.limits()

        // The one present field reflects the server…
        XCTAssertEqual(limits.messageMaxContentLength, 4000)
        // …and the omitted media limits fall back to the defaults.
        XCTAssertEqual(limits.imageMaxBytes, ContentLimits.default.imageMaxBytes)
        XCTAssertEqual(limits.videoMaxBytes, ContentLimits.default.videoMaxBytes)
    }

    func test_givenServerFailure_whenFetching_thenReturnsDefaultWithoutThrowing() async {
        let api = StubAPIClient()
        await api.enqueue(failure: .httpStatus(code: 500, serverMessage: "boom"))
        let service = ContentLimitsService(api: api)

        let limits = await service.limits()

        XCTAssertEqual(limits, ContentLimits.default)
    }

    func test_givenAllNilDTO_whenMapping_thenEqualsDefault() {
        let limits = ContentLimits(from: LimitsDTO())
        XCTAssertEqual(limits, ContentLimits.default)
    }
}
