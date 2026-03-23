import XCTest
@testable import deployBar

@MainActor
final class StatusStoreTests: XCTestCase {
    func testStartPromptsForTokenWhenCredentialStoreIsEmpty() {
        let settingsPresenter = TestSettingsPresenter()
        let store = StatusStore(
            sites: [],
            credentialStore: TestCredentialStore(token: nil),
            settingsPresenter: settingsPresenter
        )

        store.start()

        XCTAssertEqual(settingsPresenter.showSettingsCallCount, 1)
    }

    func testStartOnlyPromptsOnceWhenTokenIsMissing() {
        let settingsPresenter = TestSettingsPresenter()
        let store = StatusStore(
            sites: [],
            credentialStore: TestCredentialStore(token: nil),
            settingsPresenter: settingsPresenter
        )

        store.start()
        store.start()

        XCTAssertEqual(settingsPresenter.showSettingsCallCount, 1)
    }

    func testStartDoesNotPromptWhenTokenExists() {
        let settingsPresenter = TestSettingsPresenter()
        let store = StatusStore(
            sites: [],
            credentialStore: TestCredentialStore(token: "github-token"),
            settingsPresenter: settingsPresenter
        )

        store.start()

        XCTAssertEqual(settingsPresenter.showSettingsCallCount, 0)
    }

    func testStartDoesNotPromptWhenMissingTokenPromptsAreDisabled() {
        let settingsPresenter = TestSettingsPresenter()
        let store = StatusStore(
            sites: [],
            credentialStore: TestCredentialStore(token: nil),
            settingsPresenter: settingsPresenter,
            promptsForMissingToken: false
        )

        store.start()

        XCTAssertEqual(settingsPresenter.showSettingsCallCount, 0)
    }

    func testUnauthorizedRefreshPromptsForSettingsOnceAndShowsBanner() async {
        let settingsPresenter = TestSettingsPresenter()
        let store = StatusStore(
            sites: [SiteConfig(
                displayName: "Example",
                owner: "tintveen",
                repo: "example.com",
                branch: "main",
                workflowFile: "deploy.yml",
                siteURL: URL(string: "https://example.com")!
            )],
            client: UnauthorizedWorkflowRunFetcher(),
            credentialStore: TestCredentialStore(token: "bad-token"),
            settingsPresenter: settingsPresenter
        )

        store.refreshNow()
        await waitForRefreshResult(on: store) {
            settingsPresenter.showSettingsCallCount == 1 && store.bannerMessage != nil
        }

        XCTAssertEqual(settingsPresenter.showSettingsCallCount, 1)
        XCTAssertEqual(store.bannerMessage, "GitHub rejected the stored token. Update it in Settings.")
        XCTAssertEqual(store.states.first?.errorMessage, GitHubClientError.unauthorized.localizedDescription)
    }

    func testRefreshDoesNotShowMissingTokenBannerWhenDisabled() async {
        let store = StatusStore(
            sites: [SiteConfig(
                displayName: "Example",
                owner: "tintveen",
                repo: "example.com",
                branch: "main",
                workflowFile: "deploy.yml",
                siteURL: URL(string: "https://example.com")!
            )],
            client: EmptyWorkflowRunFetcher(),
            credentialStore: TestCredentialStore(token: nil),
            showsMissingTokenBanner: false
        )

        store.refreshNow()
        await waitForRefreshResult(on: store) {
            !store.isRefreshing
        }

        XCTAssertNil(store.bannerMessage)
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
private final class TestSettingsPresenter: SettingsPresenting {
    private(set) var showSettingsCallCount = 0

    func showSettings() {
        showSettingsCallCount += 1
    }
}

private struct UnauthorizedWorkflowRunFetcher: WorkflowRunFetching {
    func fetchLatestRun(for site: SiteConfig, token: String?) async throws -> WorkflowRun? {
        throw GitHubClientError.unauthorized
    }
}

private struct EmptyWorkflowRunFetcher: WorkflowRunFetching {
    func fetchLatestRun(for site: SiteConfig, token: String?) async throws -> WorkflowRun? {
        nil
    }
}

@MainActor
private func waitForRefreshResult(
    on store: StatusStore,
    timeoutMilliseconds: UInt64 = 1_000,
    condition: @escaping @MainActor () -> Bool
) async {
    let deadline = ContinuousClock.now + .milliseconds(timeoutMilliseconds)

    while ContinuousClock.now < deadline {
        if condition() {
            return
        }

        try? await Task.sleep(for: .milliseconds(10))
    }

    XCTFail("Timed out waiting for refresh result. isRefreshing=\(store.isRefreshing), bannerMessage=\(store.bannerMessage ?? "nil")")
}
