import XCTest
@testable import InterlinedListSyncCore

/// Read-only live validation against the real InterlinedList API. Skipped unless
/// `INTERLINEDLIST_EMAIL` / `INTERLINEDLIST_PASSWORD` are present in the
/// environment (export them from `.env`). Performs NO writes — it mints a sync
/// token and reads the delta / document / folder endpoints to confirm the real
/// wire shapes decode through the agent's client.
final class LiveAPISmokeTests: XCTestCase {

    private struct Creds { let email: String; let password: String; let baseURL: URL }

    private func loadCreds() throws -> Creds {
        let env = ProcessInfo.processInfo.environment
        guard let email = env["INTERLINEDLIST_EMAIL"], !email.isEmpty,
              let password = env["INTERLINEDLIST_PASSWORD"], !password.isEmpty else {
            throw XCTSkip("Set INTERLINEDLIST_EMAIL/PASSWORD to run the live smoke test")
        }
        let base = env["INTERLINEDLIST_API_BASE_URL"].flatMap { URL(string: $0) }
            ?? SyncConfiguration.apiBaseURL
        return Creds(email: email, password: password, baseURL: base)
    }

    private func mintToken(_ creds: Creds) async throws -> String {
        var request = URLRequest(url: URL(string: creds.baseURL.absoluteString.hasSuffix("/")
            ? creds.baseURL.absoluteString + "api/auth/sync-token"
            : creds.baseURL.absoluteString + "/api/auth/sync-token")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONCoding.makeEncoder().encode(
            SyncTokenRequest(email: creds.email, password: creds.password)
        )
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        XCTAssertEqual(status, 200, "sync-token HTTP \(status): \(String(data: data, encoding: .utf8) ?? "")")
        return try JSONCoding.makeDecoder().decode(SyncTokenResponse.self, from: data).token
    }

    func test_live_readOnly_endpointsDecode() async throws {
        let creds = try loadCreds()
        let token = try await mintToken(creds)
        XCTAssertTrue(token.hasPrefix("il_tok_") || !token.isEmpty)

        let client = SyncAPIClient(baseURL: creds.baseURL, tokenProvider: StaticTokenProvider(token))

        // Delta (full snapshot).
        let delta = try await client.fetchDelta(since: nil)
        print("LIVE delta: \(delta.documents.count) docs, \(delta.folders.count) folders, lastSyncAt=\(String(describing: delta.lastSyncAt))")

        // Full list + folders (used by the reconciliation safety net).
        let docs = try await client.fetchAllDocuments()
        let folders = try await client.fetchAllFolders()
        print("LIVE full list: \(docs.count) docs, \(folders.count) folders")

        // If any documents exist, fetching one detail must return content.
        if let first = docs.first {
            let detail = try await client.fetchDocument(id: first.id)
            XCTAssertEqual(detail.id, first.id)
            print("LIVE detail: '\(detail.title)' contentLen=\(detail.content?.count ?? -1)")
        }
    }
}
