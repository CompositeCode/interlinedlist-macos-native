import Foundation
import InterlinedKit

// MARK: - Moderation DTO → domain mapping
//
// Per-group slice of the audit-in-one-place mapper convention (PLAN.md §3).
// Per decision 0003 the App layer never references the kit DTOs — this file is
// the one place the block/mute list rows cross the boundary into `ModeratedUser`.

extension ModeratedUser {

    /// Maps a `ModeratedUserDTO` (block/mute list row) to the domain value.
    /// Tolerant of missing fields: only `id` is guaranteed on the wire.
    public init(from dto: ModeratedUserDTO) {
        self.init(
            id: dto.id,
            username: dto.username,
            displayName: dto.displayName,
            avatarURL: dto.avatar.flatMap(URL.init(string:))
        )
    }
}
