// NotificationKindVocabularyTests
//
// The notification `type` vocabulary (GitHub #95).
//
// The client matched **bare** tokens (`"dig"`, `"mention"`) while the server
// sends **prefixed** ones (`"message_dig"`, `"message_mention"`), so every one of
// the 37 notifications on the recon account fell to `.other`: rows rendered as a
// generic bell, and the deep-link router's per-kind branches never fired.
//
// Every payload below is captured from `GET /api/notifications?scope=all` on
// 2026-09-15 — one row per type the account actually holds. That is the point:
// the defect exists because the old fixtures used the tokens the client expected
// rather than the ones the server sends.

import XCTest
@testable import InterlinedDomain
@testable import InterlinedKit

final class NotificationKindVocabularyTests: XCTestCase {

    private func decode(_ json: String) throws -> NotificationDTO {
        try JSONCoders.makeDecoder().decode(NotificationDTO.self, from: Data(json.utf8))
    }

    private let digJSON = """
    {
      "id": "8fa5aec3-3530-437f-92e7-2eca9237e6a5",
      "title": "I Dig! on your message",
      "body": "…",
      "actionUrl": "/message/dd9ec178-6324-42f7-a964-8c6a36e55a9f/thread",
      "type": "message_dig",
      "metadata": {
        "type": "message_dig",
        "eventAt": "2026-08-24T19:15:55.922Z",
        "actorUserId": "c65092fa-a967-4385-92e6-ef4bc9239a3c",
        "sourceMessageId": "dd9ec178-6324-42f7-a964-8c6a36e55a9f"
      },
      "createdAt": "2026-08-24T19:15:56.651Z",
      "readAt": null,
      "routePath": "/message/dd9ec178-6324-42f7-a964-8c6a36e55a9f/thread",
      "target": { "messageId": "dd9ec178-6324-42f7-a964-8c6a36e55a9f", "listId": null, "orgId": null }
    }
    """

    private let reconnectJSON = """
    {
      "id": "d2a2459b-92cc-4ad4-b3b6-956bc6de09f7",
      "title": "Reconnect Bluesky",
      "body": "Your Bluesky connection needs to be reconnected to keep cross-posting.",
      "actionUrl": "/integrations",
      "type": "integration_reconnect",
      "metadata": null,
      "createdAt": "2026-09-14T04:00:21.557Z",
      "readAt": null,
      "routePath": "/integrations",
      "target": { "messageId": null, "listId": null, "orgId": null }
    }
    """

    // MARK: - Happy path: every live type maps to a typed case

    func test_givenEveryTypeTheAccountHolds_whenMapping_thenNoneFallsToOther() {
        // The five types across all 37 notifications on the recon account.
        let live = [
            "message_dig", "message_push_commentary", "message_push_plain",
            "message_mention", "integration_reconnect"
        ]
        for token in live {
            let kind = NotificationKind(rawValue: token)
            if case .other = kind {
                XCTFail("\(token) still falls to .other")
            }
        }
    }

    func test_givenThePrefixedTokens_whenMapping_thenTheyResolveToTheRightCases() {
        XCTAssertEqual(NotificationKind(rawValue: "message_dig"), .dig)
        XCTAssertEqual(NotificationKind(rawValue: "message_mention"), .mention)
        XCTAssertEqual(NotificationKind(rawValue: "message_push_plain"), .push(hasCommentary: false))
        XCTAssertEqual(NotificationKind(rawValue: "message_push_commentary"), .push(hasCommentary: true))
        XCTAssertEqual(NotificationKind(rawValue: "integration_reconnect"), .integrationReconnect)
    }

    func test_givenTheBareTokens_whenMapping_thenTheyStillResolve() {
        // Accepting both spellings is deliberate. This defect is itself the
        // evidence that the vocabulary is not fixed; matching only the
        // newly-observed form would repeat the mistake in the other direction.
        XCTAssertEqual(NotificationKind(rawValue: "dig"), .dig)
        XCTAssertEqual(NotificationKind(rawValue: "mention"), .mention)
        XCTAssertEqual(NotificationKind(rawValue: "reply"), .reply)
    }

    // MARK: - The target resolves

    func test_givenACapturedDigRow_whenMapping_thenTheTargetIsItsMessage() throws {
        let dto = try decode(digJSON)
        let kind = NotificationKind(rawValue: dto.type)

        let target = NotificationTarget(from: dto, kind: kind)

        XCTAssertEqual(kind, .dig)
        XCTAssertEqual(target, .message(id: "dd9ec178-6324-42f7-a964-8c6a36e55a9f"))
    }

    func test_givenNoTargetObject_whenMapping_thenMetadataSourceMessageIdIsUsed() throws {
        // The fallback for a server that has not filled `target` in. Note the
        // key is `sourceMessageId` — the client used to look for `messageId`,
        // which the live payload does not carry.
        let json = digJSON.replacingOccurrences(
            of: #""target": { "messageId": "dd9ec178-6324-42f7-a964-8c6a36e55a9f", "listId": null, "orgId": null }"#,
            with: #""target": null"#
        )
        let dto = try decode(json)

        let target = NotificationTarget(from: dto, kind: NotificationKind(rawValue: dto.type))

        XCTAssertEqual(target, .message(id: "dd9ec178-6324-42f7-a964-8c6a36e55a9f"))
    }

    // MARK: - Boundary: a row with no target at all

    func test_givenARowWithNoTarget_whenMapping_thenItFallsBackToItsRoute() throws {
        let dto = try decode(reconnectJSON)
        let kind = NotificationKind(rawValue: dto.type)

        let target = NotificationTarget(from: dto, kind: kind)

        XCTAssertEqual(kind, .integrationReconnect)
        guard case .unknown(let url) = target else {
            return XCTFail("expected .unknown, got \(target)")
        }
        XCTAssertEqual(url?.absoluteString, "/integrations")
    }

    // MARK: - Invalid input

    func test_givenAGenuinelyUnknownType_whenMapping_thenOtherStillWorks() {
        // `.other` should be rare, not gone.
        let kind = NotificationKind(rawValue: "message_semaphore")
        XCTAssertEqual(kind, .other("message_semaphore"))
        XCTAssertFalse(kind.isMessageShaped, "an unknown kind claims nothing about its shape")
    }

    func test_givenAMissingType_whenMapping_thenItIsAnEmptyOther() {
        XCTAssertEqual(NotificationKind(rawValue: nil), .other(""))
        XCTAssertEqual(NotificationKind(rawValue: ""), .other(""))
    }

    // MARK: - Round trip

    func test_givenATypedKind_whenAskedForItsToken_thenItIsTheServersSpelling() {
        // Round-tripping to the token the client used to expect would be a
        // silent disagreement with the wire.
        XCTAssertEqual(NotificationKind.dig.rawValue, "message_dig")
        XCTAssertEqual(NotificationKind.push(hasCommentary: true).rawValue, "message_push_commentary")
        XCTAssertEqual(NotificationKind.push(hasCommentary: false).rawValue, "message_push_plain")
        for kind in [NotificationKind.dig, .mention, .reply, .push(hasCommentary: true),
                     .integrationReconnect, .directMessage] {
            XCTAssertEqual(NotificationKind(rawValue: kind.rawValue), kind, "\(kind)")
        }
    }

    // MARK: - Direct messages (GitHub #77)

    func test_givenTheDirectMessageEvent_whenMapping_thenItHasATypedCase() {
        // `GET /api/user/notification-preferences` lists `direct_message` in its
        // catalogue, so the server emits these — but no DM notification has been
        // observed, so the exact row token is unconfirmed and several spellings
        // are accepted.
        XCTAssertEqual(NotificationKind(rawValue: "direct_message"), .directMessage)
        XCTAssertEqual(NotificationKind(rawValue: "dm"), .directMessage)
        XCTAssertFalse(
            NotificationKind.directMessage.isMessageShaped,
            "a DM points at a conversation, not at a timeline message"
        )
    }
}
