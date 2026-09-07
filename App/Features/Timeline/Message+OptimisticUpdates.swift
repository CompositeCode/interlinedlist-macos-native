// Message+OptimisticUpdates
//
// Local, non-networking copies of a `Message` used to paint an optimistic
// change before the round-trip resolves. Shared by `TimelineViewModel` and
// `MessageDetailViewModel`, which previously each carried a private copy of
// the dig helper (GitHub #27 needed a second one for Push, so the duplication
// was consolidated rather than tripled).
//
// Both helpers route through `replacing(...)`, which copies EVERY field. The
// two private versions this replaces omitted `crossPostResults`,
// `crossPostLocations` and `linkPreviews`, so digging a post visibly dropped
// its link preview cards and cross-post pills until the next refetch. Copying
// exhaustively fixes that.

import Foundation
import InterlinedDomain

extension Message {

    /// A copy with the dig state flipped — boolean toggled and the count
    /// nudged ±1, floored at zero so a stale count can't go negative.
    func byTogglingDig() -> Message {
        let newDidDig = !didDig
        let delta = newDidDig ? 1 : -1
        return replacing(digCount: max(0, digCount + delta), didDig: newDidDig)
    }

    /// A copy with the push ("repost") count incremented by one. Used by the
    /// one-tap Push action: the API returns the *new* push message, not an
    /// updated original, so the original's count is nudged locally.
    func byIncrementingPushCount() -> Message {
        replacing(repostCount: repostCount + 1)
    }

    /// Field-wise copy. Only the named counters vary; everything else —
    /// including the fetch-time-only `linkPreviews` and `crossPostLocations`
    /// — is carried across untouched.
    private func replacing(
        digCount: Int? = nil,
        didDig: Bool? = nil,
        repostCount: Int? = nil
    ) -> Message {
        Message(
            id: id,
            author: author,
            text: text,
            createdAt: createdAt,
            updatedAt: updatedAt,
            tags: tags,
            visibility: visibility,
            digCount: digCount ?? self.digCount,
            didDig: didDig ?? self.didDig,
            repostCount: repostCount ?? self.repostCount,
            replyCount: replyCount,
            parentID: parentID,
            repost: repost,
            scheduledAt: scheduledAt,
            crossPostResults: crossPostResults,
            crossPostLocations: crossPostLocations,
            linkPreviews: linkPreviews
        )
    }
}
