import XCTest
import InterlinedKit
@testable import InterlinedDomain

/// BDD-named coverage for the M5 notification mappers (PLAN.md §1
/// "Notifications", §6 M5, §7 testing). The mapper layer hides the kit DTO
/// from the App layer per decision 0003 — these tests pin every typed
/// `NotificationKind` case, the `.other` forward-compat fallback, and every
/// `NotificationTarget` projection.
final class NotificationMappersTests: XCTestCase {

    // MARK: - NotificationKind raw-value round-trip

    func test_givenEveryTypedKind_whenRoundTripping_thenRawValueMatches() {
        // Given the closed set we map today.
        let typedPairs: [(NotificationKind, String)] = [
            (.dig, "dig"),
            (.reply, "reply"),
            (.mention, "mention"),
            (.followRequest, "follow_request"),
            (.followAccepted, "follow_accepted"),
            (.listShared, "list_shared"),
            (.listRowAdded, "list_row_added"),
            (.orgInvite, "org_invite")
        ]

        // When / Then — every pair round-trips both directions.
        for (kind, raw) in typedPairs {
            XCTAssertEqual(kind.rawValue, raw, "kind→raw broke for \(kind)")
            XCTAssertEqual(NotificationKind(rawValue: raw), kind, "raw→kind broke for \(raw)")
        }
    }

    func test_givenUnknownString_whenInitKind_thenFallsBackToOther() {
        // Given — future server adds `mastodon_repost`. The client must
        // still decode (just into `.other`).
        let kind = NotificationKind(rawValue: "mastodon_repost")

        // Then
        XCTAssertEqual(kind, .other("mastodon_repost"))
        XCTAssertEqual(kind.rawValue, "mastodon_repost")
    }

    func test_givenNilOrEmptyString_whenInitKind_thenFallsBackToOtherEmpty() {
        // Given — wire shape allows the type field to be missing or empty.
        XCTAssertEqual(NotificationKind(rawValue: nil), .other(""))
        XCTAssertEqual(NotificationKind(rawValue: ""), .other(""))
    }

    // MARK: - NotificationTarget per-kind projection

    func test_givenDigWithMessageId_whenMapping_thenTargetsMessage() {
        let dto = NotificationDTO(
            id: "n",
            type: "dig",
            metadata: ["messageId": .string("m-1")]
        )

        let target = NotificationTarget(from: dto, kind: .dig)

        XCTAssertEqual(target, .message(id: "m-1"))
    }

    func test_givenReplyWithMessageId_whenMapping_thenTargetsMessage() {
        let dto = NotificationDTO(
            id: "n",
            type: "reply",
            metadata: ["messageId": .string("m-2")]
        )
        XCTAssertEqual(NotificationTarget(from: dto, kind: .reply), .message(id: "m-2"))
    }

    func test_givenMentionWithMessageId_whenMapping_thenTargetsMessage() {
        let dto = NotificationDTO(
            id: "n",
            type: "mention",
            metadata: ["messageId": .string("m-3")]
        )
        XCTAssertEqual(NotificationTarget(from: dto, kind: .mention), .message(id: "m-3"))
    }

    func test_givenListSharedWithListId_whenMapping_thenTargetsList() {
        let dto = NotificationDTO(
            id: "n",
            type: "list_shared",
            metadata: ["listId": .string("l-1")]
        )
        XCTAssertEqual(NotificationTarget(from: dto, kind: .listShared), .list(id: "l-1"))
    }

    func test_givenListRowAddedWithListId_whenMapping_thenTargetsList() {
        let dto = NotificationDTO(
            id: "n",
            type: "list_row_added",
            metadata: ["listId": .string("l-2")]
        )
        XCTAssertEqual(NotificationTarget(from: dto, kind: .listRowAdded), .list(id: "l-2"))
    }

    func test_givenFollowRequestWithActorId_whenMapping_thenTargetsUser() {
        let dto = NotificationDTO(
            id: "n",
            type: "follow_request",
            metadata: ["actorId": .string("u-7")]
        )
        XCTAssertEqual(NotificationTarget(from: dto, kind: .followRequest), .user(id: "u-7"))
    }

    func test_givenFollowAcceptedWithActorId_whenMapping_thenTargetsUser() {
        let dto = NotificationDTO(
            id: "n",
            type: "follow_accepted",
            metadata: ["actorId": .string("u-8")]
        )
        XCTAssertEqual(NotificationTarget(from: dto, kind: .followAccepted), .user(id: "u-8"))
    }

    func test_givenOrgInviteWithOrgId_whenMapping_thenTargetsOrganization() {
        let dto = NotificationDTO(
            id: "n",
            type: "org_invite",
            metadata: ["organizationId": .string("org-1")]
        )
        XCTAssertEqual(NotificationTarget(from: dto, kind: .orgInvite), .organization(id: "org-1"))
    }

    func test_givenOrgInviteWithLegacyOrgKey_whenMapping_thenTargetsOrganization() {
        // Some early notifications emit `orgId` rather than `organizationId`;
        // mapper accepts either.
        let dto = NotificationDTO(
            id: "n",
            type: "org_invite",
            metadata: ["orgId": .string("org-2")]
        )
        XCTAssertEqual(NotificationTarget(from: dto, kind: .orgInvite), .organization(id: "org-2"))
    }

    func test_givenOtherKind_whenMapping_thenFallsBackToUnknownWithActionURL() {
        // Forward-compat row: kind is `.other`, no typed projection — the
        // raw `actionUrl` (if any) becomes the fallback deep link.
        let dto = NotificationDTO(
            id: "n",
            actionUrl: "https://interlinedlist.com/x",
            type: "future_kind"
        )
        let target = NotificationTarget(from: dto, kind: NotificationKind(rawValue: "future_kind"))

        XCTAssertEqual(
            target,
            .unknown(actionURL: URL(string: "https://interlinedlist.com/x"))
        )
    }

    func test_givenKnownKindMissingMetadataKey_whenMapping_thenFallsBackToUnknown() {
        // Dig row missing `messageId` — the mapper must not crash, must not
        // synthesize an id, and must surface the raw actionUrl when present.
        let dto = NotificationDTO(
            id: "n",
            actionUrl: "https://interlinedlist.com/m/1",
            type: "dig",
            metadata: [:]
        )
        let target = NotificationTarget(from: dto, kind: .dig)

        XCTAssertEqual(
            target,
            .unknown(actionURL: URL(string: "https://interlinedlist.com/m/1"))
        )
    }

    func test_givenNoMetadataAndNoActionURL_whenMapping_thenFallsBackToUnknownNil() {
        // Boundary: nothing to project from.
        let dto = NotificationDTO(id: "n", type: "dig")
        XCTAssertEqual(NotificationTarget(from: dto, kind: .dig), .unknown(actionURL: nil))
    }

    // MARK: - Notification row mapper (actor + readAt + kind stitching)

    func test_givenDTOWithActorBlock_whenMappingNotification_thenStitchesActor() {
        let dto = NotificationDTO(
            id: "n-1",
            title: "Ada dug your post",
            body: nil,
            actionUrl: nil,
            type: "dig",
            metadata: [
                "messageId": .string("m-1"),
                "actorId": .string("u-1"),
                "actorUsername": .string("ada"),
                "actorDisplayName": .string("Ada Lovelace"),
                "actorAvatar": .string("https://cdn/ada.png")
            ],
            createdAt: Date(timeIntervalSince1970: 1_000_000),
            readAt: nil
        )

        let notification = Notification(from: dto)

        XCTAssertEqual(notification.id, "n-1")
        XCTAssertEqual(notification.kind, .dig)
        XCTAssertEqual(notification.target, .message(id: "m-1"))
        XCTAssertEqual(notification.actor?.id, "u-1")
        XCTAssertEqual(notification.actor?.username, "ada")
        XCTAssertEqual(notification.actor?.displayName, "Ada Lovelace")
        XCTAssertEqual(notification.actor?.avatarURL?.absoluteString, "https://cdn/ada.png")
        XCTAssertFalse(notification.isRead)
        XCTAssertEqual(notification.title, "Ada dug your post")
    }

    func test_givenDTOWithReadAt_whenMappingNotification_thenIsReadIsTrue() {
        let readAt = Date(timeIntervalSince1970: 2_000_000)
        let dto = NotificationDTO(id: "n-1", type: "dig", readAt: readAt)

        let notification = Notification(from: dto)

        XCTAssertTrue(notification.isRead)
        XCTAssertEqual(notification.readAt, readAt)
    }

    func test_givenDTOWithoutActor_whenMappingNotification_thenActorIsNil() {
        // System-originated row (`list_row_added` after a GitHub refresh).
        let dto = NotificationDTO(
            id: "n-sys",
            type: "list_row_added",
            metadata: ["listId": .string("l-1")]
        )

        let notification = Notification(from: dto)

        XCTAssertNil(notification.actor)
        XCTAssertEqual(notification.target, .list(id: "l-1"))
    }

    // MARK: - NotificationTray envelope mapper

    func test_givenTrayEnvelope_whenMapping_thenMapsEveryItem() {
        let dto = NotificationTrayDTO(
            unreadCount: 3,
            items: [
                NotificationDTO(id: "a", type: "dig"),
                NotificationDTO(id: "b", type: "reply")
            ]
        )

        let tray = NotificationTray(from: dto)

        XCTAssertEqual(tray.unreadCount, 3)
        XCTAssertEqual(tray.items.map(\.id), ["a", "b"])
        XCTAssertEqual(tray.items.map(\.kind), [.dig, .reply])
    }

    func test_givenEmptyTrayEnvelope_whenMapping_thenReturnsEmptyValue() {
        let dto = NotificationTrayDTO(unreadCount: 0, items: [])

        let tray = NotificationTray(from: dto)

        XCTAssertEqual(tray, .empty)
    }
}
