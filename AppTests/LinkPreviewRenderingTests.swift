// LinkPreviewRenderingTests
//
// App-layer tests for the timeline link-preview rendering contract
// (feature-gaps §1.5). Per the project's view-layer rule we do NOT
// render `MessageRowView` / `LinkPreviewCardView` in XCTest — SwiftUI
// rendering is verified by the build and by hand. What we CAN pin here
// is the pure decision the row delegates to: which of a message's
// `linkPreviews` are "worth showing" (`LinkPreview.isRenderable`). This
// is the exact predicate `MessageRowView.renderablePreviews` filters on,
// so these tests guard the visible behaviour without touching a view.

import XCTest
import InterlinedDomain
@testable import InterlinedList

final class LinkPreviewRenderingTests: XCTestCase {

    private let base = URL(string: "https://example.com")!

    // Happy path: a fully-resolved preview is selected for rendering.
    func test_givenMessageWithResolvedPreview_whenFilteringRenderable_thenPreviewIsIncluded() {
        // Given
        let resolved = LinkPreview(
            url: base,
            fetchStatus: "ready",
            title: "Hello",
            imageURL: URL(string: "https://cdn.example.com/i.png")
        )
        let message = MessageFixtures.message(id: "m1", linkPreviews: [resolved])

        // When
        let renderable = message.linkPreviews.filter(\.isRenderable)

        // Then
        XCTAssertEqual(renderable.map(\.url), [base])
    }

    // Invalid/degraded input: a bare-URL preview is filtered out, so the row
    // renders no card for it.
    func test_givenMessageWithBareURLPreview_whenFilteringRenderable_thenPreviewIsExcluded() {
        // Given — no title, no image, unresolved fetch status.
        let bare = LinkPreview(url: base, fetchStatus: "pending")
        let message = MessageFixtures.message(id: "m1", linkPreviews: [bare])

        // When
        let renderable = message.linkPreviews.filter(\.isRenderable)

        // Then
        XCTAssertTrue(renderable.isEmpty)
    }

    // Mixed list: only the renderable entries survive, preserving order.
    func test_givenMessageWithMixedPreviews_whenFilteringRenderable_thenOnlyRenderableSurviveInOrder() {
        // Given
        let good = LinkPreview(url: URL(string: "https://a.example.com")!, title: "A")
        let bare = LinkPreview(url: URL(string: "https://b.example.com")!)
        let alsoGood = LinkPreview(url: URL(string: "https://c.example.com")!, fetchStatus: "ok")
        let message = MessageFixtures.message(
            id: "m1",
            linkPreviews: [good, bare, alsoGood]
        )

        // When
        let renderable = message.linkPreviews.filter(\.isRenderable)

        // Then
        XCTAssertEqual(renderable.map(\.url.host), ["a.example.com", "c.example.com"])
    }

    // Empty / boundary: a message with no previews yields nothing to render.
    func test_givenMessageWithNoPreviews_whenFilteringRenderable_thenResultIsEmpty() {
        // Given / When
        let message = MessageFixtures.message(id: "m1")
        let renderable = message.linkPreviews.filter(\.isRenderable)

        // Then
        XCTAssertTrue(renderable.isEmpty)
    }
}
