import InterlinedDomain

// Foundation also declares a `Notification` type, which shadows the
// domain's `Notification` under a plain `import Foundation`. Persistence
// pervasively imports Foundation (SwiftData transitively requires it), so
// every file in this module that needs the domain notification value would
// otherwise need to fully-qualify it. The fully-qualified form
// `InterlinedDomain.Notification` does not work either, because there is a
// `public enum InterlinedDomain` namespace marker with the same identifier
// as the module — Swift resolves the dot syntax as member lookup on the
// enum and fails.
//
// The fix: an `internal` typealias scoped to this module, declared in one
// file. Persistence code references `DomainNotification` instead of
// `Notification` whenever there is risk of confusion with
// `Foundation.Notification`.

/// Module-scoped alias for `InterlinedDomain.Notification`, used by the
/// notification store and its mapper to disambiguate from
/// `Foundation.Notification`. See the file-level note above.
typealias DomainNotification = InterlinedDomain.Notification
