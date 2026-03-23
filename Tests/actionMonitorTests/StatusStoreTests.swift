import XCTest
@testable import actionMonitor

@MainActor
final class StatusStoreTests: XCTestCase {
    func testStartDoesNotPromptWhenNoWorkflowsAreConfigured() {
        let settingsPresenter = TestSettingsPresenter()
        let workflowStore = InMemoryMonitoredWorkflowStore()
        let store = StatusStore(
            workflowStore: workflowStore,
            credentialStore: TestCredentialStore(token: nil),
            settingsPresenter: settingsPresenter
        )

        store.start()

        XCTAssertEqual(settingsPresenter.showSettingsCallCount, 0)
        XCTAssertTrue(store.workflows.isEmpty)
    }

    func testStartPromptsForTokenWhenWorkflowExistsAndCredentialStoreIsEmpty() {
        let settingsPresenter = TestSettingsPresenter()
        let workflowStore = InMemoryMonitoredWorkflowStore(initialWorkflows: [sampleWorkflow()])
        let store = StatusStore(
            workflowStore: workflowStore,
            credentialStore: TestCredentialStore(token: nil),
            settingsPresenter: settingsPresenter
        )

        store.start()

        XCTAssertEqual(settingsPresenter.showSettingsCallCount, 1)
    }

    func testStartOnlyPromptsOnceWhenTokenIsMissing() {
        let settingsPresenter = TestSettingsPresenter()
        let workflowStore = InMemoryMonitoredWorkflowStore(initialWorkflows: [sampleWorkflow()])
        let store = StatusStore(
            workflowStore: workflowStore,
            credentialStore: TestCredentialStore(token: nil),
            settingsPresenter: settingsPresenter
        )

        store.start()
        store.start()

        XCTAssertEqual(settingsPresenter.showSettingsCallCount, 1)
    }

    func testStartDoesNotPromptWhenTokenExists() {
        let settingsPresenter = TestSettingsPresenter()
        let workflowStore = InMemoryMonitoredWorkflowStore(initialWorkflows: [sampleWorkflow()])
        let store = StatusStore(
            workflowStore: workflowStore,
            credentialStore: TestCredentialStore(token: "github-token"),
            settingsPresenter: settingsPresenter
        )

        store.start()

        XCTAssertEqual(settingsPresenter.showSettingsCallCount, 0)
    }

    func testUnauthorizedRefreshPromptsForSettingsOnceAndShowsBanner() async {
        let settingsPresenter = TestSettingsPresenter()
        let workflowStore = InMemoryMonitoredWorkflowStore(initialWorkflows: [sampleWorkflow()])
        let store = StatusStore(
            workflowStore: workflowStore,
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
        let workflowStore = InMemoryMonitoredWorkflowStore(initialWorkflows: [sampleWorkflow()])
        let store = StatusStore(
            workflowStore: workflowStore,
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

    func testAddWorkflowPersistsAndCreatesPlaceholderState() throws {
        let workflowStore = InMemoryMonitoredWorkflowStore()
        let store = StatusStore(
            workflowStore: workflowStore,
            client: EmptyWorkflowRunFetcher(),
            credentialStore: TestCredentialStore(token: nil),
            promptsForMissingToken: false
        )

        try store.addWorkflow(
            from: MonitoredWorkflowDraft(
                displayName: "Dashboard",
                owner: "octo-org",
                repo: "dashboard",
                branch: "main",
                workflowFile: "deploy.yml",
                siteURLText: "https://dashboard.example.com"
            )
        )

        XCTAssertEqual(store.workflows.count, 1)
        XCTAssertEqual(store.states.count, 1)
        XCTAssertEqual(store.states.first?.status, .unknown)
        XCTAssertEqual(try workflowStore.loadWorkflows().count, 1)
    }

    func testMoveWorkflowDownPersistsOrder() throws {
        let first = sampleWorkflow(displayName: "First", repo: "first")
        let second = sampleWorkflow(displayName: "Second", repo: "second")
        let workflowStore = InMemoryMonitoredWorkflowStore(initialWorkflows: [first, second])
        let store = StatusStore(
            workflowStore: workflowStore,
            client: EmptyWorkflowRunFetcher(),
            credentialStore: TestCredentialStore(token: nil),
            promptsForMissingToken: false
        )

        try store.moveWorkflowDown(id: first.id)

        XCTAssertEqual(store.workflows.map(\.displayName), ["Second", "First"])
        XCTAssertEqual(try workflowStore.loadWorkflows().map(\.displayName), ["Second", "First"])
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
    func fetchLatestRun(for workflow: MonitoredWorkflow, token: String?) async throws -> WorkflowRun? {
        throw GitHubClientError.unauthorized
    }
}

private struct EmptyWorkflowRunFetcher: WorkflowRunFetching {
    func fetchLatestRun(for workflow: MonitoredWorkflow, token: String?) async throws -> WorkflowRun? {
        nil
    }
}

private func sampleWorkflow(
    displayName: String = "Example",
    owner: String = "tintveen",
    repo: String = "example.com",
    branch: String = "main",
    workflowFile: String = "deploy.yml",
    siteURL: URL? = URL(string: "https://example.com")
) -> MonitoredWorkflow {
    MonitoredWorkflow(
        id: UUID(),
        displayName: displayName,
        owner: owner,
        repo: repo,
        branch: branch,
        workflowFile: workflowFile,
        siteURL: siteURL
    )
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
