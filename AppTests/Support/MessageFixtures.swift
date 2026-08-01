// MessageFixtures
//
// Compact factory helpers for `Message` and `CurrentUser` domain
// values used by the App-layer view-model tests. The values are
// deliberately minimal — only the fields the tested behaviour reads.
// Constants make the assertions terse and readable.

import Foundation
import InterlinedDomain

enum MessageFixtures {

    static func author(
        id: String = "user-ada",
        username: String = "ada",
        displayName: String = "Ada Lovelace"
    ) -> UserSummary {
        UserSummary(id: id, username: username, displayName: displayName, avatarURL: nil)
    }

    /// A minimally-populated `Message` value for happy-path tests.
    static func message(
        id: String,
        author: UserSummary = author(),
        text: String = "hello",
        tags: [String] = [],
        visibility: Visibility = .public,
        digCount: Int = 0,
        didDig: Bool = false,
        repostCount: Int = 0,
        replyCount: Int? = nil,
        parentID: String? = nil,
        repost: Repost? = nil,
        linkPreviews: [LinkPreview] = []
    ) -> Message {
        Message(
            id: id,
            author: author,
            text: text,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            tags: tags,
            visibility: visibility,
            digCount: digCount,
            didDig: didDig,
            repostCount: repostCount,
            replyCount: replyCount,
            parentID: parentID,
            repost: repost,
            scheduledAt: nil,
            linkPreviews: linkPreviews
        )
    }

    static func currentUser(
        id: String = "user-ada",
        username: String = "ada"
    ) -> CurrentUser {
        CurrentUser(
            summary: author(id: id, username: username),
            email: "\(username)@example.com",
            customerStatus: .subscriber,
            isEmailVerified: true,
            isPrivateAccount: false,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }
}

/// Compact test error so view-model tests can pass a stable `Error`
/// into the stub and assert on it.
enum TestError: Error, Equatable {
    case upstream(String)
}
