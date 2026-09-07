// CrashReportRedactor
//
// Scrubs a crash-report payload before it can leave the machine (GitHub issue
// #29, PR 1). Pure and synchronous: string in, string out, no I/O, no state.
//
// This is the highest-risk file in the crash-reporting change. The destination
// repo is **public and permanent**, and the rotating app log legitimately
// contains bearer tokens, JWTs, email addresses, usernames and document /
// list content. Anything this function misses is a credential disclosure, not
// a cosmetic bug — so the deny-list below is deliberately over-eager and the
// tests are table-driven over real-shaped log lines.
//
// Redaction is the *first* of two defences. The second is that the user sees
// the exact, editable payload in the confirmation sheet before anything is
// submitted, and nothing is ever transmitted without an explicit press.
//
// The deny-list here is the one signed off on issue #29; changing it is a
// security decision, not a refactor.

import Foundation

public enum CrashReportRedactor {

    // MARK: - Deny-list

    /// One deny-list entry. Kept as a *pattern string* rather than a compiled
    /// `NSRegularExpression` so the table is `Sendable` and can be a `static
    /// let`; compiling six small patterns once per crash is free.
    public struct Rule: Sendable, Equatable {
        /// ICU pattern matched against the whole payload, line by line.
        public let pattern: String
        /// Replacement template — `$1` etc. refer to capture groups, so a rule
        /// can keep the key (`token=`) while destroying the value.
        public let template: String
        /// Why the rule exists; surfaced in test failures.
        public let rationale: String

        public init(pattern: String, template: String, rationale: String) {
            self.pattern = pattern
            self.template = template
            self.rationale = rationale
        }
    }

    /// Characters that can appear in a bearer token / JWT segment. Kept as one
    /// constant so every token rule agrees on the alphabet.
    private static let tokenChars = "A-Za-z0-9\\-._~+/="

    /// The approved deny-list, applied **in order**. Order matters: the
    /// specific credential shapes run before the generic `key=value` sweeps so
    /// a token is labelled `[redacted-token]` rather than the vaguer
    /// `[redacted]`.
    ///
    /// What is deliberately **kept**: stack frames, signal numbers and names,
    /// app / OS versions, HTTP status codes, API route paths, timestamps and
    /// `AppLog` category names. Those carry the diagnostic value and none of
    /// them is user data.
    public static let rules: [Rule] = [

        // 1a. An `Authorization` header in any casing or punctuation, whether
        //     logged as `Authorization: Bearer x` or `authorization=x`.
        Rule(
            pattern: "(?i)\\bauthorization\\b\\s*[:=]\\s*(\"[^\"]*\"|'[^']*'|\\S+)",
            template: "Authorization: [redacted-token]",
            rationale: "Authorization header value is a live credential"
        ),

        // 1b. A bare `Bearer <token>` anywhere in a line — the common shape
        //     when a request is logged without its header name.
        //
        //     What follows `Bearer` has to *look* like a token: either 16+
        //     characters, or 8+ containing at least one digit or separator.
        //     Without that qualifier this rule eats ordinary English, and it
        //     demonstrably did: `APIClient.swift` logs "Bearer request
        //     returned 401 [/api/user]", which the naive pattern turned into
        //     "Bearer [redacted-token] returned 401" — destroying a real
        //     diagnostic line and teaching the reader to distrust the
        //     redaction markers. Both thresholds sit far below any credential
        //     this app handles (session tokens are JWTs, hundreds of
        //     characters, and are caught by rule 2 regardless).
        Rule(
            pattern: "(?i)\\bbearer\\s+(?:[\(tokenChars)]{16,}|(?=[\(tokenChars)]*[0-9\\-._~+/=])[\(tokenChars)]{8,})",
            template: "Bearer [redacted-token]",
            rationale: "Bearer token is a live credential"
        ),

        // 2.  JWT shape. Our session tokens are JWTs, so this catches them even
        //     when they appear with no surrounding key — inside a URL, a decode
        //     error, or a reflected `URLError`. The trailing segments are
        //     optional so a *truncated* JWT is still caught.
        Rule(
            pattern: "\\beyJ[A-Za-z0-9_-]{4,}(?:\\.[A-Za-z0-9_.-]*){0,2}",
            template: "[redacted-token]",
            rationale: "JWT-shaped string is a session token"
        ),

        // 3.  Secret-bearing key positions. The key name is preserved (it is
        //     diagnostically useful to know *which* credential was involved);
        //     only the value dies. `[A-Za-z0-9_]*` on both sides so
        //     `accessToken`, `refresh_token`, `apiKey`, `keychainItem` … all hit.
        Rule(
            pattern: "(?i)\\b([A-Za-z0-9_]*(?:password|passwd|secret|token|apikey|api_key|keychain|credential|session_id|sessionid|cookie)[A-Za-z0-9_]*)\\b\\s*[\"']?\\s*[:=]\\s*(\"[^\"]*\"|'[^']*'|\\S+)",
            template: "$1=[redacted]",
            rationale: "credential value position"
        ),

        // 4.  User content key positions — document and list bodies and titles.
        //     Also sweeps up `username`/`displayName` via the `name` stem,
        //     which is intended: a public issue should not carry an account
        //     handle either.
        Rule(
            pattern: "(?i)\\b([A-Za-z0-9_]*(?:title|name|content|body|note|summary|description|caption|excerpt|text)[A-Za-z0-9_]*)\\b\\s*[\"']?\\s*[:=]\\s*(\"[^\"]*\"|'[^']*'|\\S+)",
            template: "$1=[redacted-content]",
            rationale: "document / list content and account handles"
        ),

        // 5.  Email addresses, wherever they appear. Runs last so an address
        //     inside an already-redacted value costs nothing, and a bare
        //     address in prose is still caught.
        Rule(
            pattern: "[A-Za-z0-9._%+\\-]+@[A-Za-z0-9.\\-]+\\.[A-Za-z]{2,}",
            template: "[redacted-email]",
            rationale: "email address identifies the reporter or a third party"
        )
    ]

    // MARK: - Redaction

    /// Applies every deny-list rule, in order, to `text`.
    ///
    /// Never throws and never returns `nil`: a payload that cannot be scrubbed
    /// must not silently fall back to the raw text, so a rule that fails to
    /// compile is skipped and the remaining rules still run. (Compilation is
    /// exercised by `test_everyRuleCompiles`, so a broken pattern fails the
    /// build gate rather than leaking at runtime.)
    public static func redact(_ text: String) -> String {
        var result = text
        for rule in rules {
            guard let regex = try? NSRegularExpression(pattern: rule.pattern) else { continue }
            result = regex.stringByReplacingMatches(
                in: result,
                options: [],
                range: NSRange(result.startIndex..., in: result),
                withTemplate: rule.template
            )
        }
        return result
    }

    /// Redacts each line of a backtrace independently.
    ///
    /// Frames are on the *keep* list, but running them through the same rules
    /// is free insurance: a mangled Swift symbol contains no `=`, `@` or
    /// `Bearer`, so real frames pass through untouched while a frame that
    /// somehow embeds a credential still gets caught.
    public static func redact(frames: [String]) -> [String] {
        frames.map(redact)
    }
}
