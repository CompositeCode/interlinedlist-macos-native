import XCTest
@testable import InterlinedKit

final class TokenStoreTests: XCTestCase {

    // MARK: - InMemoryTokenStore

    // Note: we deliberately do not exercise the real `KeychainTokenStore`
    // in unit tests. The Keychain is a host-process resource; touching it
    // from `swift test` is flaky in CI and pollutes the developer's
    // keychain. Production code injects `KeychainTokenStore`; tests
    // inject `InMemoryTokenStore`. Behaviour parity is enforced by the
    // shared `TokenStore` protocol.

    func test_givenEmptyStore_whenRead_thenReturnsNil() throws {
        // Boundary: never-written store.
        let store = InMemoryTokenStore()
        XCTAssertNil(try store.read())
    }

    func test_givenWrittenToken_whenRead_thenReturnsValue() throws {
        // Happy path.
        let store = InMemoryTokenStore()
        try store.write("il_tok_round_trip")
        XCTAssertEqual(try store.read(), "il_tok_round_trip")
    }

    func test_givenExistingToken_whenWrittenAgain_thenReplaces() throws {
        // Invalid input class: caller wrote twice; the second value wins.
        let store = InMemoryTokenStore(initial: "old")
        try store.write("new")
        XCTAssertEqual(try store.read(), "new")
    }

    func test_givenStoredToken_whenDeleted_thenReadsNil() throws {
        // Upstream failure analogue: sign-out path.
        let store = InMemoryTokenStore(initial: "il_tok")
        try store.delete()
        XCTAssertNil(try store.read())
    }

    func test_givenEmptyStore_whenDeleted_thenSucceedsSilently() throws {
        // Boundary: delete is idempotent.
        let store = InMemoryTokenStore()
        XCTAssertNoThrow(try store.delete())
    }
}
