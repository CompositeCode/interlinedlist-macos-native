import XCTest
import InterlinedDomain
@testable import InterlinedList

/// BDD-named coverage for `MessageRowActions` (GitHub #27).
///
/// The struct carries the row's whole interaction contract, so the tests pin
/// the two rules `MessageRowView` depends on: an unwired handler stays nil
/// (the row hides that affordance rather than rendering it broken), and a
/// wired handler receives the exact message it was invoked with.
@MainActor
final class MessageRowActionsTests: XCTestCase {

    private func message(id: String = "m-1") -> Message {
        MessageFixtures.message(id: id)
    }

    // MARK: - Happy path — a wired handler fires with the tapped message

    func test_givenWiredHandlers_whenInvoked_thenEachReceivesTheTappedMessage() {
        // Given every handler wired to record the message it was handed.
        var received: [String: String] = [:]
        let actions = MessageRowActions(
            onToggleDig: { received["dig"] = $0.id },
            onReply: { received["reply"] = $0.id },
            onPush: { received["push"] = $0.id },
            onRepost: { received["repost"] = $0.id },
            onEdit: { received["edit"] = $0.id },
            onDelete: { received["delete"] = $0.id },
            onBlock: { received["block"] = $0.id },
            onMute: { received["mute"] = $0.id },
            onReport: { received["report"] = $0.id },
            onCreateGitHubIssue: { received["issue"] = $0.id }
        )
        let tapped = message(id: "tapped-99")

        // When each is invoked the way the row invokes them.
        actions.onToggleDig?(tapped)
        actions.onReply?(tapped)
        actions.onPush?(tapped)
        actions.onRepost?(tapped)
        actions.onEdit?(tapped)
        actions.onDelete?(tapped)
        actions.onBlock?(tapped)
        actions.onMute?(tapped)
        actions.onReport?(tapped)
        actions.onCreateGitHubIssue?(tapped)

        // Then all ten fired, each with the same message — no cross-wiring.
        XCTAssertEqual(received.count, 10)
        XCTAssertTrue(received.values.allSatisfy { $0 == "tapped-99" })
    }

    // MARK: - Invalid / unwired — the row must hide the affordance

    func test_givenNoneActions_whenInspected_thenEveryHandlerIsNil() {
        // Given the read-only action set search results and previews use.
        let actions = MessageRowActions.none

        // When / Then — every handler is absent, so `MessageRowView` renders
        // no button and no context-menu item for any of them.
        XCTAssertNil(actions.onToggleDig)
        XCTAssertNil(actions.onReply)
        XCTAssertNil(actions.onPush)
        XCTAssertNil(actions.onRepost)
        XCTAssertNil(actions.onEdit)
        XCTAssertNil(actions.onDelete)
        XCTAssertNil(actions.onBlock)
        XCTAssertNil(actions.onMute)
        XCTAssertNil(actions.onReport)
        XCTAssertNil(actions.onCreateGitHubIssue)
    }

    func test_givenUnwiredHandler_whenInvoked_thenNothingHappens() {
        // Given a set with only dig wired.
        var digCount = 0
        let actions = MessageRowActions(onToggleDig: { _ in digCount += 1 })

        // When the row optionally-invokes a handler that was never wired.
        actions.onReply?(message())
        actions.onPush?(message())

        // Then it is a silent no-op — and the wired one is untouched.
        XCTAssertEqual(digCount, 0)
    }

    // MARK: - Upstream failure — a throwing host must not corrupt the set

    func test_givenPartiallyWiredActions_whenOneHandlerRuns_thenOthersStayIndependent() {
        // Given a set where only some handlers are wired (the detail view's
        // shape: dig / repost / edit / delete, no moderation).
        var pushed = false
        let actions = MessageRowActions(
            onRepost: { _ in pushed = true },
            onEdit: { _ in }
        )

        // When the wired one runs.
        actions.onRepost?(message())

        // Then it fired and the unwired ones are still absent — a partially
        // wired host never silently gains affordances it did not ask for.
        XCTAssertTrue(pushed)
        XCTAssertNil(actions.onBlock)
        XCTAssertNil(actions.onReport)
        XCTAssertNotNil(actions.onEdit)
    }

    // MARK: - Boundary — repeated invocation

    func test_givenWiredHandler_whenInvokedRepeatedly_thenFiresEachTime() {
        // Given a dig handler.
        var count = 0
        let actions = MessageRowActions(onToggleDig: { _ in count += 1 })

        // When the user taps three times.
        for _ in 0..<3 { actions.onToggleDig?(message()) }

        // Then the row does not de-bounce — de-bouncing is the view model's
        // job (`TimelineViewModel.pendingDigOperations`), not the row's.
        XCTAssertEqual(count, 3)
    }
}
