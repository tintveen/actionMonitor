import XCTest
@testable import deployBar

@MainActor
final class StatusStoreTests: XCTestCase {
    func testStartPromptsForTokenWhenCredentialStoreIsEmpty() {
        let settingsOpener = SettingsOpener()
        let store = StatusStore(
            sites: [],
            credentialStore: TestCredentialStore(token: nil),
            settingsWindowOpener: settingsOpener.open
        )

        store.start()

        XCTAssertEqual(settingsOpener.openCallCount, 1)
    }

    func testStartOnlyPromptsOnceWhenTokenIsMissing() {
        let settingsOpener = SettingsOpener()
        let store = StatusStore(
            sites: [],
            credentialStore: TestCredentialStore(token: nil),
            settingsWindowOpener: settingsOpener.open
        )

        store.start()
        store.start()

        XCTAssertEqual(settingsOpener.openCallCount, 1)
    }

    func testStartDoesNotPromptWhenTokenExists() {
        let settingsOpener = SettingsOpener()
        let store = StatusStore(
            sites: [],
            credentialStore: TestCredentialStore(token: "github-token"),
            settingsWindowOpener: settingsOpener.open
        )

        store.start()

        XCTAssertEqual(settingsOpener.openCallCount, 0)
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

@MainActor
private final class SettingsOpener {
    private(set) var openCallCount = 0

    func open() {
        openCallCount += 1
    }
}
