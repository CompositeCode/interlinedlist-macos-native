import Foundation
@testable import InterlinedDomain

/// JSON response fixtures matching the live API envelopes the services consume.
/// Kept as raw strings (rather than encoded DTOs) so the tests exercise the
/// exact decode path production uses, including the paginated envelope split.
enum Fixtures {

    /// A fixed, valid ISO 8601 timestamp the kit decoder accepts.
    static let createdAtISO = "2026-06-16T12:00:00Z"

    /// A single message object body (the inner JSON of one `MessageDTO`).
    static func messageObject(
        id: String,
        content: String = "hello",
        username: String = "ada",
        displayName: String? = "Ada Lovelace",
        publiclyVisible: Bool = true,
        tags: [String]? = ["swift"],
        digCount: Int = 3,
        dugByMe: Bool = false,
        pushCount: Int = 1,
        parentId: String? = nil,
        scheduledAt: String? = nil,
        pushedMessageId: String? = nil
    ) -> String {
        let displayNameJSON = displayName.map { "\"\($0)\"" } ?? "null"
        let tagsJSON = tags.map { "[" + $0.map { "\"\($0)\"" }.joined(separator: ",") + "]" } ?? "null"
        let parentJSON = parentId.map { "\"\($0)\"" } ?? "null"
        let scheduledJSON = scheduledAt.map { "\"\($0)\"" } ?? "null"
        let pushedIdJSON = pushedMessageId.map { "\"\($0)\"" } ?? "null"
        return """
        {
          "id": "\(id)",
          "content": "\(content)",
          "publiclyVisible": \(publiclyVisible),
          "userId": "user-\(username)",
          "parentId": \(parentJSON),
          "scheduledAt": \(scheduledJSON),
          "tags": \(tagsJSON),
          "createdAt": "\(createdAtISO)",
          "updatedAt": "\(createdAtISO)",
          "digCount": \(digCount),
          "pushCount": \(pushCount),
          "pushedMessageId": \(pushedIdJSON),
          "user": {
            "id": "user-\(username)",
            "username": "\(username)",
            "displayName": \(displayNameJSON),
            "avatar": "https://cdn.interlinedlist.com/\(username).png"
          },
          "dugByMe": \(dugByMe)
        }
        """
    }

    /// The standard `{ "messages": [...], "pagination": {...} }` envelope.
    static func paginatedMessages(
        ids: [String],
        total: Int? = nil,
        limit: Int = 20,
        offset: Int = 0,
        hasMore: Bool = false
    ) -> String {
        let objects = ids.map { messageObject(id: $0) }.joined(separator: ",")
        let totalValue = total ?? ids.count
        return """
        {
          "messages": [\(objects)],
          "pagination": {
            "total": \(totalValue),
            "limit": \(limit),
            "offset": \(offset),
            "hasMore": \(hasMore)
          }
        }
        """
    }

    /// The non-standard replies envelope: `{ "replies": [...], "total": Int }`.
    static func repliesEnvelope(ids: [String]) -> String {
        let objects = ids.map { messageObject(id: $0) }.joined(separator: ",")
        return """
        { "replies": [\(objects)], "total": \(ids.count) }
        """
    }

    /// The `GET /api/user` envelope: `{ "user": { ... } }`.
    static func userEnvelope(
        id: String = "user-ada",
        username: String = "ada",
        email: String = "ada@example.com",
        customerStatus: String = "subscriber",
        emailVerified: Bool = true
    ) -> String {
        """
        {
          "user": {
            "id": "\(id)",
            "email": "\(email)",
            "username": "\(username)",
            "displayName": "Ada Lovelace",
            "avatar": "https://cdn.interlinedlist.com/\(username).png",
            "emailVerified": \(emailVerified),
            "customerStatus": "\(customerStatus)",
            "createdAt": "\(createdAtISO)",
            "isPrivateAccount": false
          }
        }
        """
    }
}
