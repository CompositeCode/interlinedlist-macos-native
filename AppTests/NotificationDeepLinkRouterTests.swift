// NotificationDeepLinkRouterTests
//
// BDD-named tests for the `NotificationTarget.init(userInfo:)` extension
// defined in `NotificationDeepLinkRouter.swift`.
//
// Coverage matrix:
// ┌──────────────────────────────────────────────────────────────────┐
// │ Scenario                          │ Expected target              │
// ├──────────────────────────────────────────────────────────────────┤
// │ dig / reply / mention + messageId │ .message(id:)                │
// │ listShared / listRowAdded + listId│ .list(id:)                   │
// │ followRequest / accepted + userId │ .user(id:)                   │
// │ orgInvite + orgId                 │ .organization(id:)           │
// │ known kind, missing target key    │ .unknown(actionURL:)         │
// │ unknown / empty type              │ .unknown(actionURL:)         │
// │ empty userInfo dict               │ .unknown(actionURL: nil)     │
// │ actionUrl present in unknown      │ .unknown(actionURL: URL)     │
// └──────────────────────────────────────────────────────────────────┘
//
// Also covers `LocalNotificationScheduler.userInfo(for:)` round-trip:
// building the dict from a domain `Notification` and parsing it back
// must produce the original target.
//
// No network I/O; no SwiftUI rendering; no AppKit.

import XCTest
import InterlinedDomain
@testable import InterlinedList

final class NotificationDeepLinkRouterTests: XCTestCase {

    // MARK: - Helpers

    private func makeNotification(
        id: String = "n-1",
        kind: NotificationKind,
        target: NotificationTarget? = nil,
        actor: UserSummary? = UserSummary(id: "u-1", username: "alice", displayName: "Alice", avatarURL: nil)
    ) -> InterlinedDomain.Notification {
        InterlinedDomain.Notification(
            id: id,
            kind: kind,
            actor: actor,
            target: target,
            createdAt: Date(timeIntervalSince1970: 0),
            isRead: false
        )
    }

    // MARK: - Message targets (dig / reply / mention)

    func test_givenDigUserInfoWithMessageId_whenParsingTarget_thenReturnsMessageTarget() {
        let userInfo: [AnyHashable: Any] = [
            NotificationUserInfoKeys.type:            "dig",
            NotificationUserInfoKeys.targetMessageId: "msg-42"
        ]

        let target = NotificationTarget(userInfo: userInfo)

        XCTAssertEqual(target, .message(id: "msg-42"))
    }

    func test_givenReplyUserInfoWithMessageId_whenParsingTarget_thenReturnsMessageTarget() {
        let userInfo: [AnyHashable: Any] = [
            NotificationUserInfoKeys.type:            "reply",
            NotificationUserInfoKeys.targetMessageId: "msg-99"
        ]

        let target = NotificationTarget(userInfo: userInfo)

        XCTAssertEqual(target, .message(id: "msg-99"))
    }

    func test_givenMentionUserInfoWithMessageId_whenParsingTarget_thenReturnsMessageTarget() {
        let userInfo: [AnyHashable: Any] = [
            NotificationUserInfoKeys.type:            "mention",
            NotificationUserInfoKeys.targetMessageId: "msg-7"
        ]

        let target = NotificationTarget(userInfo: userInfo)

        XCTAssertEqual(target, .message(id: "msg-7"))
    }

    // MARK: - List targets (list_shared / list_row_added)

    func test_givenListSharedUserInfoWithListId_whenParsingTarget_thenReturnsListTarget() {
        let userInfo: [AnyHashable: Any] = [
            NotificationUserInfoKeys.type:         "list_shared",
            NotificationUserInfoKeys.targetListId: "list-5"
        ]

        let target = NotificationTarget(userInfo: userInfo)

        XCTAssertEqual(target, .list(id: "list-5"))
    }

    func test_givenListRowAddedUserInfoWithListId_whenParsingTarget_thenReturnsListTarget() {
        let userInfo: [AnyHashable: Any] = [
            NotificationUserInfoKeys.type:         "list_row_added",
            NotificationUserInfoKeys.targetListId: "list-8"
        ]

        let target = NotificationTarget(userInfo: userInfo)

        XCTAssertEqual(target, .list(id: "list-8"))
    }

    // MARK: - User targets (follow_request / follow_accepted)

    func test_givenFollowRequestUserInfoWithUserId_whenParsingTarget_thenReturnsUserTarget() {
        let userInfo: [AnyHashable: Any] = [
            NotificationUserInfoKeys.type:           "follow_request",
            NotificationUserInfoKeys.targetUserId:   "user-bob"
        ]

        let target = NotificationTarget(userInfo: userInfo)

        XCTAssertEqual(target, .user(id: "user-bob"))
    }

    func test_givenFollowAcceptedUserInfoWithUserId_whenParsingTarget_thenReturnsUserTarget() {
        let userInfo: [AnyHashable: Any] = [
            NotificationUserInfoKeys.type:           "follow_accepted",
            NotificationUserInfoKeys.targetUserId:   "user-carol"
        ]

        let target = NotificationTarget(userInfo: userInfo)

        XCTAssertEqual(target, .user(id: "user-carol"))
    }

    // MARK: - Organization target (org_invite)

    func test_givenOrgInviteUserInfoWithOrgId_whenParsingTarget_thenReturnsOrganizationTarget() {
        let userInfo: [AnyHashable: Any] = [
            NotificationUserInfoKeys.type:        "org_invite",
            NotificationUserInfoKeys.targetOrgId: "org-acme"
        ]

        let target = NotificationTarget(userInfo: userInfo)

        XCTAssertEqual(target, .organization(id: "org-acme"))
    }

    // MARK: - Boundary: missing target key for known kind

    func test_givenDigUserInfoWithoutMessageId_whenParsingTarget_thenReturnsUnknownWithNilURL() {
        let userInfo: [AnyHashable: Any] = [
            NotificationUserInfoKeys.type: "dig"
            // targetMessageId deliberately omitted
        ]

        let target = NotificationTarget(userInfo: userInfo)

        XCTAssertEqual(target, .unknown(actionURL: nil))
    }

    func test_givenOrgInviteUserInfoWithoutOrgId_whenParsingTarget_thenReturnsUnknownWithNilURL() {
        let userInfo: [AnyHashable: Any] = [
            NotificationUserInfoKeys.type: "org_invite"
            // targetOrgId deliberately omitted
        ]

        let target = NotificationTarget(userInfo: userInfo)

        XCTAssertEqual(target, .unknown(actionURL: nil))
    }

    // MARK: - Unknown / forward-compat type

    func test_givenUnknownTypeUserInfo_whenParsingTarget_thenReturnsUnknownWithNilURL() {
        let userInfo: [AnyHashable: Any] = [
            NotificationUserInfoKeys.type: "future_event_type"
        ]

        let target = NotificationTarget(userInfo: userInfo)

        XCTAssertEqual(target, .unknown(actionURL: nil))
    }

    // MARK: - Empty / boundary

    func test_givenEmptyUserInfo_whenParsingTarget_thenReturnsUnknownWithNilURL() {
        let userInfo: [AnyHashable: Any] = [:]

        let target = NotificationTarget(userInfo: userInfo)

        XCTAssertEqual(target, .unknown(actionURL: nil))
    }

    func test_givenUserInfoWithActionUrl_whenParsingUnknownTarget_thenReturnsUnknownWithURL() {
        let url = URL(string: "https://interlinedlist.com/activity/123")!
        let userInfo: [AnyHashable: Any] = [
            NotificationUserInfoKeys.type:      "some_future_type",
            NotificationUserInfoKeys.actionUrl: url.absoluteString
        ]

        let target = NotificationTarget(userInfo: userInfo)

        XCTAssertEqual(target, .unknown(actionURL: url))
    }

    // MARK: - Round-trip: LocalNotificationScheduler.userInfo → parse back

    func test_givenMessageNotification_whenBuildingAndParsingUserInfo_thenRoundTripPreservesTarget() {
        let original = makeNotification(
            kind: .dig,
            target: .message(id: "msg-rt-1")
        )

        let built   = LocalNotificationScheduler.userInfo(for: original)
        let parsed  = NotificationTarget(userInfo: built)

        XCTAssertEqual(parsed, .message(id: "msg-rt-1"))
    }

    func test_givenListNotification_whenBuildingAndParsingUserInfo_thenRoundTripPreservesTarget() {
        let original = makeNotification(
            kind: .listShared,
            target: .list(id: "list-rt-2")
        )

        let built  = LocalNotificationScheduler.userInfo(for: original)
        let parsed = NotificationTarget(userInfo: built)

        XCTAssertEqual(parsed, .list(id: "list-rt-2"))
    }

    func test_givenUserNotification_whenBuildingAndParsingUserInfo_thenRoundTripPreservesTarget() {
        let original = makeNotification(
            kind: .followRequest,
            target: .user(id: "user-rt-3")
        )

        let built  = LocalNotificationScheduler.userInfo(for: original)
        let parsed = NotificationTarget(userInfo: built)

        XCTAssertEqual(parsed, .user(id: "user-rt-3"))
    }

    func test_givenOrgNotification_whenBuildingAndParsingUserInfo_thenRoundTripPreservesTarget() {
        let original = makeNotification(
            kind: .orgInvite,
            target: .organization(id: "org-rt-4")
        )

        let built  = LocalNotificationScheduler.userInfo(for: original)
        let parsed = NotificationTarget(userInfo: built)

        XCTAssertEqual(parsed, .organization(id: "org-rt-4"))
    }

    func test_givenNilTargetNotification_whenBuildingAndParsingUserInfo_thenRoundTripReturnsUnknown() {
        let original = makeNotification(kind: .other("custom"), target: nil)

        let built  = LocalNotificationScheduler.userInfo(for: original)
        let parsed = NotificationTarget(userInfo: built)

        XCTAssertEqual(parsed, .unknown(actionURL: nil))
    }

    // MARK: - userInfo content correctness

    func test_givenNotificationWithActor_whenBuildingUserInfo_thenActorUsernameIsEmbedded() {
        let note = makeNotification(
            id: "n-actor",
            kind: .dig,
            target: .message(id: "msg-1"),
            actor: UserSummary(id: "u-1", username: "alice", displayName: "Alice", avatarURL: nil)
        )

        let dict = LocalNotificationScheduler.userInfo(for: note)

        XCTAssertEqual(dict[NotificationUserInfoKeys.actorUsername], "alice")
    }

    func test_givenNotification_whenBuildingUserInfo_thenNotificationIdAndTypeArePresent() {
        let note = makeNotification(id: "n-check", kind: .reply, target: .message(id: "m-1"))

        let dict = LocalNotificationScheduler.userInfo(for: note)

        XCTAssertEqual(dict[NotificationUserInfoKeys.notificationId], "n-check")
        XCTAssertEqual(dict[NotificationUserInfoKeys.type], "reply")
    }
}
