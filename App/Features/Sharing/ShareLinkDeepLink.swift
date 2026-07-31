// ShareLinkDeepLink
//
// App-layer glue that turns an opened share URL (pasted or delivered via
// the `interlinedlist://` deep-link scheme) into a routed presentation of
// `ResolveShareView` (the-gaps.md G3). Mirrors the project's notification-
// name convention: a `Notification.Name` colocated with the feature and a
// static poster so the URL handler in `InterlinedListApp` stays a
// one-liner and `MainWindowView` owns the sheet presentation.
//
// The URL handler in `AppRootView` (`InterlinedListApp.swift`) already
// filters for the OAuth callback; this adds share-link handling *alongside*
// it: an `interlinedlist://…/shared/{token}` (or an https share URL) is
// parsed by `ShareURLParser`, and on a hit we post `.openShareLink` with
// the `ParsedShare` as the object. `MainWindowView` observes it and
// presents the landing sheet. A non-share URL returns `false` so the
// existing OAuth handling is untouched.

import Foundation

extension Foundation.Notification.Name {
    /// Posted when an opened URL resolves to a share link. `object` is the
    /// `ParsedShare`. Observed by `MainWindowView`, which presents
    /// `ResolveShareView`.
    static let openShareLink = Foundation.Notification.Name("InterlinedList.openShareLink")
}

enum ShareLinkDeepLink {

    /// Attempts to route `url` as a share link. Returns `true` (and posts
    /// `.openShareLink`) when the URL is a recognized share link; returns
    /// `false` otherwise so the caller can fall through to other handlers
    /// (e.g. the OAuth callback). `post` defaults to `nil`, in which case
    /// the parsed share is posted to `NotificationCenter.default`; tests
    /// pass a capturing closure to observe the routing without the center.
    @discardableResult
    @MainActor
    static func handle(_ url: URL, post: ((ParsedShare) -> Void)? = nil) -> Bool {
        guard let parsed = ShareURLParser.parse(url) else { return false }
        if let post {
            post(parsed)
        } else {
            NotificationCenter.default.post(name: .openShareLink, object: parsed)
        }
        return true
    }
}
