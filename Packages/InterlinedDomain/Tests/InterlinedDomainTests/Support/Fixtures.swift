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

    /// A single `FollowUserDTO` object body, matching the live API shape
    /// verified 2026-06-24: `{ id, username, displayName, avatar, followId,
    /// createdAt, status }` (Wave 1 deviation 5 closed).
    static func followUserObject(
        id: String,
        username: String = "ada",
        displayName: String? = "Ada Lovelace",
        avatar: String? = "https://cdn.interlinedlist.com/ada.png",
        followId: String? = nil,
        status: String? = "approved"
    ) -> String {
        let displayJSON = displayName.map { "\"\($0)\"" } ?? "null"
        let avatarJSON = avatar.map { "\"\($0)\"" } ?? "null"
        let followIdJSON = followId.map { "\"\($0)\"" } ?? "null"
        let statusJSON = status.map { "\"\($0)\"" } ?? "null"
        return """
        {
          "id": "\(id)",
          "username": "\(username)",
          "displayName": \(displayJSON),
          "avatar": \(avatarJSON),
          "followId": \(followIdJSON),
          "status": \(statusJSON)
        }
        """
    }

    /// The wrapped `{ followers: [...], pagination: {...} }` envelope.
    static func followersEnvelope(
        ids: [String],
        collectionKey: String = "followers"
    ) -> String {
        let objects = ids.map { followUserObject(id: $0) }.joined(separator: ",")
        let total = ids.count
        return """
        {
          "\(collectionKey)": [\(objects)],
          "pagination": {"total":\(total),"limit":50,"offset":0,"hasMore":false}
        }
        """
    }

    /// Convenience for the `/following` endpoint (same shape, different key).
    static func followingEnvelope(ids: [String]) -> String {
        followersEnvelope(ids: ids, collectionKey: "following")
    }

    /// `GET /api/follow/[userId]/mutual` envelope — counts only.
    static func mutualCountsEnvelope(
        mutualFollowers: Int,
        mutualFollowing: Int
    ) -> String {
        """
        { "mutualFollowers": \(mutualFollowers), "mutualFollowing": \(mutualFollowing) }
        """
    }

    /// `POST /api/follow/[userId]` / approve / reject / remove confirmation.
    static func followActionResponse(success: Bool = true, message: String? = nil) -> String {
        let messageJSON = message.map { "\"\($0)\"" } ?? "null"
        return """
        { "success": \(success), "message": \(messageJSON) }
        """
    }

    /// `GET /api/follow/requests` envelope — bare `{ requests: [...] }`, no
    /// pagination wrapper (verified live 2026-06-24).
    static func followRequestsEnvelope(
        ids: [String],
        followIdPrefix: String = "f-"
    ) -> String {
        let objects = ids.map { id in
            followUserObject(id: id, followId: "\(followIdPrefix)\(id)", status: "pending")
        }.joined(separator: ",")
        return """
        { "requests": [\(objects)] }
        """
    }

    // MARK: - Notifications (M5) fixtures

    /// One `NotificationDTO` object body. `metadata` is supplied as raw JSON
    /// so per-kind shape variations can be exercised directly.
    static func notificationObject(
        id: String,
        type: String? = "dig",
        title: String? = "Someone dug your post",
        body: String? = nil,
        actionUrl: String? = nil,
        metadataJSON: String = "{}",
        createdAt: String? = createdAtISO,
        readAt: String? = nil
    ) -> String {
        let typeJSON = type.map { "\"\($0)\"" } ?? "null"
        let titleJSON = title.map { "\"\($0)\"" } ?? "null"
        let bodyJSON = body.map { "\"\($0)\"" } ?? "null"
        let actionJSON = actionUrl.map { "\"\($0)\"" } ?? "null"
        let createdJSON = createdAt.map { "\"\($0)\"" } ?? "null"
        let readJSON = readAt.map { "\"\($0)\"" } ?? "null"
        return """
        {
          "id": "\(id)",
          "type": \(typeJSON),
          "title": \(titleJSON),
          "body": \(bodyJSON),
          "actionUrl": \(actionJSON),
          "metadata": \(metadataJSON),
          "createdAt": \(createdJSON),
          "readAt": \(readJSON)
        }
        """
    }

    /// `GET /api/notifications?scope=tray` envelope:
    /// `{ unreadCount, items: [...] }`.
    static func notificationTrayEnvelope(
        unreadCount: Int,
        items: [String]
    ) -> String {
        """
        {
          "unreadCount": \(unreadCount),
          "items": [\(items.joined(separator: ","))]
        }
        """
    }

    /// `PATCH /api/notifications/[id]/read` envelope: `{ ok: true }`.
    static let notificationReadResponse: String = #"{ "ok": true }"#

    /// `POST /api/notifications/mark-all-read` envelope:
    /// `{ ok: true, updated: Int }`.
    static func notificationMarkAllReadResponse(updated: Int) -> String {
        """
        { "ok": true, "updated": \(updated) }
        """
    }

    // MARK: - Documents (M4) fixtures

    /// A single `DocumentDTO` object body.
    static func documentObject(
        id: String,
        title: String = "Welcome",
        content: String? = "# Hello",
        folderId: String? = nil,
        isPublic: Bool? = false,
        updatedAt: String? = createdAtISO,
        deleted: Bool? = nil
    ) -> String {
        let contentJSON = content.map { "\"\($0)\"" } ?? "null"
        let folderJSON = folderId.map { "\"\($0)\"" } ?? "null"
        let publicJSON = isPublic.map { $0 ? "true" : "false" } ?? "null"
        let updatedJSON = updatedAt.map { "\"\($0)\"" } ?? "null"
        let deletedJSON = deleted.map { $0 ? "true" : "false" } ?? "null"
        return """
        {
          "id": "\(id)",
          "title": "\(title)",
          "content": \(contentJSON),
          "folderId": \(folderJSON),
          "isPublic": \(publicJSON),
          "createdAt": "\(createdAtISO)",
          "updatedAt": \(updatedJSON),
          "deleted": \(deletedJSON)
        }
        """
    }

    /// `{ "data": [...], "pagination": {...} }` envelope for documents.
    static func paginatedDocuments(
        ids: [String],
        total: Int? = nil,
        limit: Int = 20,
        offset: Int = 0,
        hasMore: Bool = false
    ) -> String {
        let objects = ids.map { documentObject(id: $0) }.joined(separator: ",")
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

    /// A single `DocumentFolderDTO` object body.
    static func folderObject(
        id: String,
        name: String = "Inbox",
        parentId: String? = nil,
        deleted: Bool? = nil
    ) -> String {
        let parentJSON = parentId.map { "\"\($0)\"" } ?? "null"
        let deletedJSON = deleted.map { $0 ? "true" : "false" } ?? "null"
        return """
        {
          "id": "\(id)",
          "name": "\(name)",
          "parentId": \(parentJSON),
          "createdAt": "\(createdAtISO)",
          "updatedAt": "\(createdAtISO)",
          "deleted": \(deletedJSON)
        }
        """
    }

    /// `{ "data": [...], "pagination": {...} }` envelope for folders.
    static func paginatedFolders(
        ids: [String],
        total: Int? = nil,
        limit: Int = 20,
        offset: Int = 0,
        hasMore: Bool = false
    ) -> String {
        let objects = ids.map { folderObject(id: $0) }.joined(separator: ",")
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

    /// `GET /api/documents/sync` envelope.
    static func documentSyncResponse(
        syncedAt: String? = createdAtISO,
        documents: [String] = [],
        folders: [String] = []
    ) -> String {
        let syncedJSON = syncedAt.map { "\"\($0)\"" } ?? "null"
        return """
        {
          "syncedAt": \(syncedJSON),
          "folders": [\(folders.joined(separator: ","))],
          "documents": [\(documents.joined(separator: ","))]
        }
        """
    }

    /// `POST /api/documents/[id]/images/upload` response envelope.
    static func documentImageUploadResponse(url: String) -> String {
        """
        { "url": "\(url)" }
        """
    }

    /// Generic `MessageResponse` envelope returned by endpoints that
    /// confirm an operation with a human-readable message string (e.g.
    /// `POST /api/user/change-email/request` and
    /// `POST /api/user/delete`).
    static func messageResponse(message: String = "ok") -> String {
        """
        { "message": "\(message)" }
        """
    }

    // MARK: - Organizations (M6) fixtures

    /// A single `OrganizationDTO` object body.
    static func organizationObject(
        id: String,
        name: String = "Acme",
        description: String? = "We make things",
        isPublic: Bool? = true,
        includeTimestamps: Bool = true
    ) -> String {
        let descJSON = description.map { "\"\($0)\"" } ?? "null"
        let isPublicJSON = isPublic.map { $0 ? "true" : "false" } ?? "null"
        let timestamps = includeTimestamps
            ? ",\n  \"createdAt\": \"\(createdAtISO)\",\n  \"updatedAt\": \"\(createdAtISO)\""
            : ""
        return """
        {
          "id": "\(id)",
          "name": "\(name)",
          "description": \(descJSON),
          "isPublic": \(isPublicJSON)\(timestamps)
        }
        """
    }

    /// The `{ "data": [...], "pagination": {...} }` envelope for orgs.
    static func paginatedOrganizations(
        ids: [String],
        total: Int? = nil,
        limit: Int = 20,
        offset: Int = 0,
        hasMore: Bool = false
    ) -> String {
        let objects = ids.map { organizationObject(id: $0) }.joined(separator: ",")
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

    /// A single `OrganizationMemberDTO` listing row (keyed by userId, no
    /// membership-record id).
    static func orgMemberObject(
        userId: String,
        role: String = "member",
        active: Bool? = true
    ) -> String {
        let activeJSON = active.map { $0 ? "true" : "false" } ?? "null"
        return """
        {
          "userId": "\(userId)",
          "role": "\(role)",
          "active": \(activeJSON),
          "createdAt": "\(createdAtISO)"
        }
        """
    }

    /// The `{ "data": [...], "pagination": {...} }` envelope for members.
    static func paginatedOrgMembers(
        userIds: [String],
        role: String = "member",
        total: Int? = nil,
        limit: Int = 20,
        offset: Int = 0,
        hasMore: Bool = false
    ) -> String {
        let objects = userIds.map { orgMemberObject(userId: $0, role: role) }.joined(separator: ",")
        let totalValue = total ?? userIds.count
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

    /// The `POST` / `PUT` member-mutation envelope:
    /// `{ "message": "…", "membership": { … } }`.
    static func orgMembershipResponse(
        membershipId: String,
        userId: String,
        organizationId: String,
        role: String,
        active: Bool? = true,
        message: String? = "ok"
    ) -> String {
        let messageJSON = message.map { "\"\($0)\"" } ?? "null"
        let activeJSON = active.map { $0 ? "true" : "false" } ?? "null"
        return """
        {
          "message": \(messageJSON),
          "membership": {
            "id": "\(membershipId)",
            "userId": "\(userId)",
            "organizationId": "\(organizationId)",
            "role": "\(role)",
            "active": \(activeJSON),
            "createdAt": "\(createdAtISO)"
          }
        }
        """
    }

    /// A single `OrganizationUserDTO` (user-with-role) object body.
    static func orgUserObject(
        id: String,
        username: String? = "ada",
        displayName: String? = "Ada Lovelace",
        avatarUrl: String? = "https://cdn.interlinedlist.com/ada.png",
        role: String? = "member"
    ) -> String {
        let usernameJSON = username.map { "\"\($0)\"" } ?? "null"
        let displayJSON = displayName.map { "\"\($0)\"" } ?? "null"
        let avatarJSON = avatarUrl.map { "\"\($0)\"" } ?? "null"
        let roleJSON = role.map { "\"\($0)\"" } ?? "null"
        return """
        {
          "id": "\(id)",
          "username": \(usernameJSON),
          "displayName": \(displayJSON),
          "avatarUrl": \(avatarJSON),
          "role": \(roleJSON)
        }
        """
    }

    /// A bare array of `OrganizationUserDTO` objects (the shape
    /// `GET /api/organizations/[id]/users` returns).
    static func orgUsersArray(_ entries: [(id: String, role: String?)]) -> String {
        let objects = entries.map { orgUserObject(id: $0.id, role: $0.role) }.joined(separator: ",")
        return "[\(objects)]"
    }

    // MARK: - User identities + organizations (M6) fixtures

    /// A single `LinkedIdentityDTO` object body.
    static func linkedIdentityObject(
        id: String,
        provider: String = "github",
        providerUsername: String? = "ada",
        profileUrl: String? = "https://github.com/ada",
        avatarUrl: String? = "https://cdn/ada.png",
        connectedAt: String? = createdAtISO,
        lastVerifiedAt: String? = createdAtISO
    ) -> String {
        let usernameJSON = providerUsername.map { "\"\($0)\"" } ?? "null"
        let profileJSON = profileUrl.map { "\"\($0)\"" } ?? "null"
        let avatarJSON = avatarUrl.map { "\"\($0)\"" } ?? "null"
        let connectedJSON = connectedAt.map { "\"\($0)\"" } ?? "null"
        let verifiedJSON = lastVerifiedAt.map { "\"\($0)\"" } ?? "null"
        return """
        {
          "id": "\(id)",
          "provider": "\(provider)",
          "providerUsername": \(usernameJSON),
          "profileUrl": \(profileJSON),
          "avatarUrl": \(avatarJSON),
          "connectedAt": \(connectedJSON),
          "lastVerifiedAt": \(verifiedJSON)
        }
        """
    }

    /// `GET /api/user/identities` envelope: `{ "identities": [...] }`.
    static func identitiesEnvelope(_ objects: [String]) -> String {
        """
        { "identities": [\(objects.joined(separator: ","))] }
        """
    }

    /// A single `UserOrganizationDTO` (membership-view) object body.
    static func userOrganizationObject(
        id: String,
        name: String = "Acme",
        role: String = "member",
        isPublic: Bool? = true,
        joinedAt: String? = createdAtISO
    ) -> String {
        let isPublicJSON = isPublic.map { $0 ? "true" : "false" } ?? "null"
        let joinedJSON = joinedAt.map { "\"\($0)\"" } ?? "null"
        return """
        {
          "id": "\(id)",
          "name": "\(name)",
          "isPublic": \(isPublicJSON),
          "role": "\(role)",
          "joinedAt": \(joinedJSON),
          "createdAt": "\(createdAtISO)",
          "updatedAt": "\(createdAtISO)"
        }
        """
    }

    /// `GET /api/user/organizations` envelope: `{ "organizations": [...] }`.
    static func userOrganizationsEnvelope(_ objects: [String]) -> String {
        """
        { "organizations": [\(objects.joined(separator: ","))] }
        """
    }

    // MARK: - Messages M6 fixtures

    /// `GET /api/messages/scheduled` envelope: `{ "messages": [...] }` (no
    /// pagination block).
    static func scheduledMessagesEnvelope(ids: [String]) -> String {
        let objects = ids.map {
            messageObject(id: $0, scheduledAt: "2026-07-01T09:00:00Z")
        }.joined(separator: ",")
        return """
        { "messages": [\(objects)] }
        """
    }

    /// `POST /api/messages/images|videos/upload` envelope: `{ "url": "string" }`.
    static func mediaUploadResponse(url: String) -> String {
        """
        { "url": "\(url)" }
        """
    }

    /// A small valid PNG (1x1) the image-prep pipeline can decode, base64.
    /// Used by the media-upload happy path so `ImagePrep.prepare` succeeds.
    static var tinyPNGData: Data {
        // 1x1 transparent PNG.
        let base64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg=="
        return Data(base64Encoded: base64)!
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
