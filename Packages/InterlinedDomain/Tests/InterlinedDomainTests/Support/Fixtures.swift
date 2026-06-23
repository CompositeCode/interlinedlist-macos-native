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

    // MARK: - Lists fixtures

    /// A single `ListDTO` object body (the inner JSON of one list).
    static func listObject(
        id: String,
        title: String = "Books",
        description: String? = "Things I have read",
        isPublic: Bool? = true,
        schema: String? = "Title:text, Year:number",
        parentId: String? = nil
    ) -> String {
        let descJSON = description.map { "\"\($0)\"" } ?? "null"
        let schemaJSON = schema.map { "\"\($0)\"" } ?? "null"
        let parentJSON = parentId.map { "\"\($0)\"" } ?? "null"
        let isPublicJSON = isPublic.map { $0 ? "true" : "false" } ?? "null"
        return """
        {
          "id": "\(id)",
          "title": "\(title)",
          "description": \(descJSON),
          "isPublic": \(isPublicJSON),
          "schema": \(schemaJSON),
          "parentId": \(parentJSON),
          "createdAt": "\(createdAtISO)",
          "updatedAt": "\(createdAtISO)"
        }
        """
    }

    /// The `{ "data": [...], "pagination": {...} }` envelope used by the
    /// public-list browse and the row endpoint.
    static func paginatedLists(
        ids: [String],
        total: Int? = nil,
        limit: Int = 20,
        offset: Int = 0,
        hasMore: Bool = false
    ) -> String {
        let objects = ids.map { listObject(id: $0) }.joined(separator: ",")
        let totalValue = total ?? ids.count
        return """
        {
          "data": [\(objects)],
          "pagination": {
            "total": \(totalValue),
            "limit": \(limit),
            "offset": \(offset),
            "hasMore": \(hasMore)
          }
        }
        """
    }

    /// A single `ListRowDTO` object body with two columns matching the schema
    /// fixture.
    static func listRowObject(
        id: String,
        listId: String = "list-1",
        title: String = "Dune",
        year: Int = 1965
    ) -> String {
        """
        {
          "id": "\(id)",
          "listId": "\(listId)",
          "rowData": {
            "Title": "\(title)",
            "Year": \(year)
          },
          "createdAt": "\(createdAtISO)",
          "updatedAt": "\(createdAtISO)"
        }
        """
    }

    /// The paginated row envelope: `{ "data": [...], "pagination": {...} }`.
    static func paginatedRows(
        ids: [String],
        total: Int? = nil,
        limit: Int = 20,
        offset: Int = 0,
        hasMore: Bool = false
    ) -> String {
        let objects = ids.map { listRowObject(id: $0) }.joined(separator: ",")
        let totalValue = total ?? ids.count
        return """
        {
          "data": [\(objects)],
          "pagination": {
            "total": \(totalValue),
            "limit": \(limit),
            "offset": \(offset),
            "hasMore": \(hasMore)
          }
        }
        """
    }

    // MARK: - M3 lists fixtures

    /// `GET /api/lists/[id]/schema` envelope: `{ "schema": "<DSL>" }`.
    static func listSchemaEnvelope(_ dsl: String) -> String {
        """
        { "schema": "\(dsl)" }
        """
    }

    /// A single `ListWatcherDTO` object body.
    static func watcherObject(
        userId: String,
        role: String? = "editor",
        username: String? = "ada"
    ) -> String {
        let roleJSON = role.map { "\"\($0)\"" } ?? "null"
        let usernameJSON = username.map { "\"\($0)\"" } ?? "null"
        return """
        {
          "userId": "\(userId)",
          "role": \(roleJSON),
          "username": \(usernameJSON),
          "createdAt": "\(createdAtISO)"
        }
        """
    }

    /// A bare array of watcher objects (the shape `/watchers` returns).
    static func watchersArray(_ entries: [(userId: String, role: String?)]) -> String {
        let objects = entries.map { watcherObject(userId: $0.userId, role: $0.role) }
            .joined(separator: ",")
        return "[\(objects)]"
    }

    /// `GET /api/lists/[id]/watchers/me` envelope.
    static func watcherStatusEnvelope(isWatching: Bool?, role: String?) -> String {
        let watchingJSON = isWatching.map { $0 ? "true" : "false" } ?? "null"
        let roleJSON = role.map { "\"\($0)\"" } ?? "null"
        return """
        { "isWatching": \(watchingJSON), "role": \(roleJSON) }
        """
    }

    /// A single `ListConnectionDTO` object body.
    static func connectionObject(
        id: String,
        fromListId: String = "list-from",
        toListId: String = "list-to",
        label: String? = "references"
    ) -> String {
        let labelJSON = label.map { "\"\($0)\"" } ?? "null"
        return """
        {
          "id": "\(id)",
          "fromListId": "\(fromListId)",
          "toListId": "\(toListId)",
          "label": \(labelJSON),
          "createdAt": "\(createdAtISO)"
        }
        """
    }

    /// `GET /api/lists/connections` envelope.
    static func connectionsEnvelope(_ ids: [String]) -> String {
        let objects = ids.map { connectionObject(id: $0) }.joined(separator: ",")
        return """
        { "connections": [\(objects)] }
        """
    }

    // MARK: - Follow / social fixtures

    /// `GET /api/follow/[userId]/status` shape.
    static func followStatus(
        following: Bool = false,
        followedBy: Bool = false,
        pendingRequest: Bool = false
    ) -> String {
        """
        {
          "following": \(following),
          "followedBy": \(followedBy),
          "pendingRequest": \(pendingRequest)
        }
        """
    }

    /// `GET /api/follow/[userId]/counts` shape.
    static func followCounts(followerCount: Int, followingCount: Int) -> String {
        """
        { "followerCount": \(followerCount), "followingCount": \(followingCount) }
        """
    }

    /// A single `FollowUserDTO` object body.
    static func followUserObject(
        id: String,
        username: String = "ada",
        displayName: String? = "Ada Lovelace",
        avatarUrl: String? = "https://cdn.interlinedlist.com/ada.png"
    ) -> String {
        let displayJSON = displayName.map { "\"\($0)\"" } ?? "null"
        let avatarJSON = avatarUrl.map { "\"\($0)\"" } ?? "null"
        return """
        {
          "id": "\(id)",
          "username": "\(username)",
          "displayName": \(displayJSON),
          "avatarUrl": \(avatarJSON)
        }
        """
    }

    /// The bare-array shape `GET /api/follow/[userId]/followers` and `/following`
    /// return today.
    static func followUserArray(ids: [String]) -> String {
        let objects = ids.map { followUserObject(id: $0) }.joined(separator: ",")
        return "[\(objects)]"
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
