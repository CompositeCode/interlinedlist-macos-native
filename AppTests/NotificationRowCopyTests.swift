// NotificationRowCopyTests
//
// BDD-named tests for the pure presenter that derives the row's copy
// string + SF Symbol from `(NotificationKind, actor, title, body)`.
// Every kind gets a copy assertion; the `.other` case has its own
// pinned-string assertion to guard against a regression in the
// forward-compat fallback.

import XCTest
import InterlinedDomain
@testable import InterlinedList

@MainActor
final class NotificationRowCopyTests: XCTestCase {

    private func actor(_ username: String = "alice") -> UserSummary {
        UserSummary(id: "u-\(username)", username: username, displayName: username.capitalized, avatarURL: nil)
    }

    // MARK: - Each kind's copy

    func test_givenDigKind_whenRendering_thenCopyMentionsHandleAndPost() {
        let copy = NotificationRowCopy.copy(for: .dig, actor: actor(), title: nil, body: nil)
        XCTAssertEqual(copy, "@alice dug your post")
    }

    func test_givenReplyKind_whenRendering_thenCopyMentionsReply() {
        let copy = NotificationRowCopy.copy(for: .reply, actor: actor("bob"), title: nil, body: nil)
        XCTAssertEqual(copy, "@bob replied to your post")
    }

    func test_givenMentionKind_whenRendering_thenCopyMentionsTheMention() {
        let copy = NotificationRowCopy.copy(for: .mention, actor: actor(), title: nil, body: nil)
        XCTAssertEqual(copy, "@alice mentioned you")
    }

    func test_givenFollowRequestKind_whenRendering_thenCopyMentionsWantsToFollow() {
        let copy = NotificationRowCopy.copy(for: .followRequest, actor: actor(), title: nil, body: nil)
        XCTAssertEqual(copy, "@alice wants to follow you")
    }

    func test_givenFollowAcceptedKind_whenRendering_thenCopyMentionsAccepted() {
        let copy = NotificationRowCopy.copy(for: .followAccepted, actor: actor(), title: nil, body: nil)
        XCTAssertEqual(copy, "@alice accepted your follow request")
    }

    func test_givenListSharedKind_whenRendering_thenCopyMentionsList() {
        let copy = NotificationRowCopy.copy(for: .listShared, actor: actor(), title: nil, body: nil)
        XCTAssertEqual(copy, "@alice shared a list with you")
    }

    func test_givenListRowAddedKind_whenRendering_thenCopyMentionsRow() {
        let copy = NotificationRowCopy.copy(for: .listRowAdded, actor: actor(), title: nil, body: nil)
        XCTAssertEqual(copy, "@alice added a row to a list")
    }

    func test_givenOrgInviteKind_whenRendering_thenCopyMentionsOrg() {
        let copy = NotificationRowCopy.copy(for: .orgInvite, actor: actor(), title: nil, body: nil)
        XCTAssertEqual(copy, "@alice invited you to an organization")
    }

    // MARK: - .other forward-compat

    func test_givenOtherKindWithRawString_whenRendering_thenCopyContainsRawValue() {
        let copy = NotificationRowCopy.copy(
            for: .other("future_event"),
            actor: actor(),
            title: nil,
            body: nil
        )
        XCTAssertEqual(copy, "@alice: future_event")
    }

    func test_givenOtherKindWithBody_whenRendering_thenCopyPrefersBody() {
        let copy = NotificationRowCopy.copy(
            for: .other("future_event"),
            actor: actor(),
            title: nil,
            body: "Something happened"
        )
        XCTAssertEqual(copy, "Something happened")
    }

    // MARK: - Title / actor fallbacks (boundary)

    func test_givenServerSuppliedTitle_whenRendering_thenCopyPrefersTitleOverDerived() {
        let copy = NotificationRowCopy.copy(
            for: .dig,
            actor: actor(),
            title: "Custom server title",
            body: nil
        )
        XCTAssertEqual(copy, "Custom server title")
    }

    func test_givenMissingActor_whenRendering_thenCopyFallsBackToSomeone() {
        let copy = NotificationRowCopy.copy(for: .listRowAdded, actor: nil, title: nil, body: nil)
        XCTAssertEqual(copy, "Someone added a row to a list")
    }

    // MARK: - Symbol mapping (pin every kind)

    func test_givenEveryKind_whenAskingForSymbol_thenAValidSFSymbolNameReturns() {
        let cases: [(NotificationKind, String)] = [
            (.dig, "hand.thumbsup.fill"),
            (.reply, "bubble.left.fill"),
            (.mention, "at"),
            (.followRequest, "person.crop.circle.badge.questionmark"),
            (.followAccepted, "person.crop.circle.badge.checkmark"),
            (.listShared, "list.bullet.rectangle"),
            (.listRowAdded, "plus.rectangle.on.rectangle"),
            (.orgInvite, "building.2.crop.circle"),
            (.other("anything"), "bell")
        ]
        for (kind, expected) in cases {
            XCTAssertEqual(NotificationRowCopy.symbol(for: kind), expected, "Symbol for \(kind)")
        }
    }
}
