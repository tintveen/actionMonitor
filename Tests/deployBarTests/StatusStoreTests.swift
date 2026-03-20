import XCTest
@testable import deployBar

@MainActor
final class StatusStoreTests: XCTestCase {
    func testStartPromptsForTokenWhenCredentialStoreIsEmpty() {
        let store = StatusStore(
            sites: [],
            credentialStore: TestCredentialStore(token: nil)
        )

        store.start()

        XCTAssertEqual(store.settingsPresentationRequestCount, 1)
    }

    func testStartOnlyPromptsOnceWhenTokenIsMissing() {
        let store = StatusStore(
            sites: [],
            credentialStore: TestCredentialStore(token: nil)
        )

        store.start()
        store.start()

        XCTAssertEqual(store.settingsPresentationRequestCount, 1)
    }

    func testStartDoesNotPromptWhenTokenExists() {
        let store = StatusStore(
            sites: [],
            credentialStore: TestCredentialStore(token: "github-token")
        )

        store.start()

        XCTAssertEqual(store.settingsPresentationRequestCount, 0)
    }
}

private struct TestCredentialStore: CredentialStore {
    let token: String?

    func loadToken() throws -> String? {
        token
    }

    func saveToken(_ token: String) throws {}

    func removeToken() throws {}
}
