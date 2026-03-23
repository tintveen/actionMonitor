import XCTest
@testable import actionMonitor

@MainActor
final class StatusStoreTests: XCTestCase {
    func testStartShowsWelcomeOnboardingWhenSetupIsIncomplete() {
        let presenter = TestSettingsPresenter()
        let setupStore = TestAppSetupStore(didCompleteOnboarding: false)
        let store = StatusStore(
            workflowStore: InMemoryMonitoredWorkflowStore(),
            credentialStore: TestCredentialStore(credential: nil),
            appSetupStore: setupStore,
            settingsPresenter: presenter,
            oauthConfiguration: configuredOAuth()
        )

        store.start()

        XCTAssertEqual(store.onboardingStep, .welcome)
        XCTAssertEqual(presenter.showOnboardingSteps, [.welcome])
    }

    func testStartShowsWorkflowStepWhenCredentialExistsButNoWorkflow() {
        let presenter = TestSettingsPresenter()
        let store = StatusStore(
            workflowStore: InMemoryMonitoredWorkflowStore(),
            credentialStore: TestCredentialStore(credential: oauthCredential()),
            appSetupStore: TestAppSetupStore(didCompleteOnboarding: false),
            settingsPresenter: presenter,
            oauthConfiguration: configuredOAuth()
        )

        store.start()

        XCTAssertEqual(store.onboardingStep, .firstWorkflow)
        XCTAssertEqual(presenter.showOnboardingSteps, [.firstWorkflow])
    }

    func testExistingCredentialAndWorkflowAutoCompletesOnboarding() {
        let setupStore = TestAppSetupStore(didCompleteOnboarding: false)
        let store = StatusStore(
            workflowStore: InMemoryMonitoredWorkflowStore(initialWorkflows: [sampleWorkflow()]),
            credentialStore: TestCredentialStore(credential: oauthCredential()),
            appSetupStore: setupStore,
            settingsPresenter: TestSettingsPresenter(),
            oauthConfiguration: configuredOAuth()
        )

        store.start()

        XCTAssertFalse(store.shouldRouteSettingsToOnboarding)
        XCTAssertEqual(setupStore.savedValues.last, true)
    }

    func testBrowserSignInPersistsCredentialOpensBrowserAndAdvancesToWorkflowStep() async {
        let presenter = TestSettingsPresenter()
        let setupStore = TestAppSetupStore(didCompleteOnboarding: false)
        let credentialStore = TestCredentialStore(credential: nil)
        let authorizer = TestGitHubBrowserOAuthAuthorizer(
            context: browserAuthorizationContext(),
            result: .success(oauthCredential())
        )
        let store = StatusStore(
            workflowStore: InMemoryMonitoredWorkflowStore(),
            client: EmptyWorkflowRunFetcher(),
            credentialStore: credentialStore,
            appSetupStore: setupStore,
            settingsPresenter: presenter,
            gitHubAuthorizer: authorizer,
            oauthConfiguration: configuredOAuth(),
            promptsForIncompleteSetup: false
        )

        store.beginOnboarding()
        store.continueFromWelcome()
        store.beginGitHubSignIn()

        await waitForCondition {
            credentialStore.saveCallCount == 1 && !store.isGitHubSignInBusy
        }

        XCTAssertEqual(authorizer.preparedConfigurations.map(\.clientID), ["client-id"])
        XCTAssertEqual(authorizer.waitedConfigurations.map(\.clientSecret), ["client-secret"])
        XCTAssertEqual(presenter.openedExternalURLs, [browserAuthorizationContext().authorizationURL])
        XCTAssertEqual(store.authState, .signedInOAuth(oauthCredential().summary))
        XCTAssertEqual(store.onboardingStep, .firstWorkflow)
        XCTAssertEqual(credentialStore.credential, oauthCredential())
    }

    func testSavingFirstWorkflowAdvancesOnboardingToFinish() throws {
        let store = StatusStore(
            workflowStore: InMemoryMonitoredWorkflowStore(),
            client: EmptyWorkflowRunFetcher(),
            credentialStore: TestCredentialStore(credential: oauthCredential()),
            appSetupStore: TestAppSetupStore(didCompleteOnboarding: false),
            settingsPresenter: TestSettingsPresenter(),
            oauthConfiguration: configuredOAuth(),
            promptsForIncompleteSetup: false
        )

        store.beginOnboarding()
        store.continueFromSignInStep()
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

        XCTAssertEqual(store.onboardingStep, .finish)
        XCTAssertEqual(store.workflows.count, 1)
    }

    func testFinishOnboardingPersistsCompletionAndDismissesWindow() throws {
        let presenter = TestSettingsPresenter()
        let setupStore = TestAppSetupStore(didCompleteOnboarding: false)
        let store = StatusStore(
            workflowStore: InMemoryMonitoredWorkflowStore(initialWorkflows: [sampleWorkflow()]),
            client: EmptyWorkflowRunFetcher(),
            credentialStore: TestCredentialStore(credential: oauthCredential()),
            appSetupStore: setupStore,
            settingsPresenter: presenter,
            oauthConfiguration: configuredOAuth(),
            promptsForIncompleteSetup: false
        )

        store.beginOnboarding()
        store.continueFromSignInStep()
        store.continueFromWorkflowStep()
        try store.finishOnboarding()

        XCTAssertFalse(store.shouldRouteSettingsToOnboarding)
        XCTAssertEqual(setupStore.savedValues.last, true)
        XCTAssertEqual(presenter.dismissOnboardingCallCount, 1)
    }

    func testSkipOnboardingLeavesSetupIncomplete() {
        let presenter = TestSettingsPresenter()
        let setupStore = TestAppSetupStore(didCompleteOnboarding: false)
        let store = StatusStore(
            workflowStore: InMemoryMonitoredWorkflowStore(),
            credentialStore: TestCredentialStore(credential: nil),
            appSetupStore: setupStore,
            settingsPresenter: presenter,
            oauthConfiguration: configuredOAuth(),
            promptsForIncompleteSetup: false
        )

        store.beginOnboarding()
        store.skipOnboarding()

        XCTAssertTrue(store.shouldRouteSettingsToOnboarding)
        XCTAssertEqual(setupStore.savedValues.last, false)
        XCTAssertEqual(presenter.dismissOnboardingCallCount, 1)
    }

    func testSignOutAfterCompletionMarksSetupIncompleteAgain() {
        let setupStore = TestAppSetupStore(didCompleteOnboarding: true)
        let store = StatusStore(
            workflowStore: InMemoryMonitoredWorkflowStore(initialWorkflows: [sampleWorkflow()]),
            credentialStore: TestCredentialStore(credential: oauthCredential()),
            appSetupStore: setupStore,
            settingsPresenter: TestSettingsPresenter(),
            oauthConfiguration: configuredOAuth(),
            promptsForIncompleteSetup: false
        )

        store.signOut()

        XCTAssertTrue(store.shouldRouteSettingsToOnboarding)
        XCTAssertEqual(store.authState, .signedOut)
        XCTAssertEqual(setupStore.savedValues.last, false)
    }
}

private final class TestCredentialStore: CredentialStore, @unchecked Sendable {
    var credential: GitHubCredential?
    private(set) var saveCallCount = 0

    init(credential: GitHubCredential?) {
        self.credential = credential
    }

    func loadCredential() throws -> GitHubCredential? {
        credential
    }

    func saveCredential(_ credential: GitHubCredential) throws {
        saveCallCount += 1
        self.credential = credential
    }

    func removeCredential() throws {
        credential = nil
    }
}

private final class TestAppSetupStore: AppSetupStore, @unchecked Sendable {
    private var didCompleteOnboarding: Bool
    private(set) var savedValues: [Bool] = []

    init(didCompleteOnboarding: Bool) {
        self.didCompleteOnboarding = didCompleteOnboarding
    }

    func loadDidCompleteOnboarding() -> Bool {
        didCompleteOnboarding
    }

    func saveDidCompleteOnboarding(_ didCompleteOnboarding: Bool) {
        savedValues.append(didCompleteOnboarding)
        self.didCompleteOnboarding = didCompleteOnboarding
    }
}

@MainActor
private final class TestSettingsPresenter: SettingsPresenting {
    private(set) var showSettingsCallCount = 0
    private(set) var showOnboardingSteps: [OnboardingStep] = []
    private(set) var dismissOnboardingCallCount = 0
    private(set) var openedExternalURLs: [URL] = []

    func showSettings() {
        showSettingsCallCount += 1
    }

    func showOnboarding(startingAt step: OnboardingStep) {
        showOnboardingSteps.append(step)
    }

    func dismissOnboarding() {
        dismissOnboardingCallCount += 1
    }

    func openExternalURL(_ url: URL) {
        openedExternalURLs.append(url)
    }
}

private struct EmptyWorkflowRunFetcher: WorkflowRunFetching {
    func fetchLatestRun(for workflow: MonitoredWorkflow, token: String?) async throws -> WorkflowRun? {
        nil
    }
}

private final class TestGitHubBrowserOAuthAuthorizer: GitHubBrowserOAuthAuthorizing, @unchecked Sendable {
    let context: GitHubBrowserAuthorizationContext
    let result: Result<GitHubCredential, Error>
    private(set) var preparedConfigurations: [GitHubOAuthConfiguration] = []
    private(set) var waitedConfigurations: [GitHubOAuthConfiguration] = []

    init(
        context: GitHubBrowserAuthorizationContext,
        result: Result<GitHubCredential, Error>
    ) {
        self.context = context
        self.result = result
    }

    func prepareAuthorization(using configuration: GitHubOAuthConfiguration) async throws -> GitHubBrowserAuthorizationContext {
        preparedConfigurations.append(configuration)
        return context
    }

    func waitForAuthorization(
        using context: GitHubBrowserAuthorizationContext,
        configuration: GitHubOAuthConfiguration
    ) async throws -> GitHubCredential {
        waitedConfigurations.append(configuration)
        return try result.get()
    }

    func cancelAuthorization() {}
}

private func configuredOAuth() -> GitHubOAuthConfiguration {
    GitHubOAuthConfiguration(
        clientID: "client-id",
        clientSecret: "client-secret"
    )!
}

private func browserAuthorizationContext() -> GitHubBrowserAuthorizationContext {
    GitHubBrowserAuthorizationContext(
        authorizationURL: URL(string: "https://github.com/login/oauth/authorize?client_id=client-id")!,
        redirectURI: URL(string: "http://127.0.0.1:8123/oauth/callback")!,
        state: "oauth-state",
        codeVerifier: "oauth-code-verifier",
        expiresAt: Date(timeIntervalSince1970: 1_712_000_000)
    )
}

private func oauthCredential() -> GitHubCredential {
    GitHubCredential(
        accessToken: "oauth-token",
        source: .oauthBrowser,
        login: "octocat",
        grantedScopes: ["repo"],
        savedAt: Date(timeIntervalSince1970: 1_712_000_000)
    )
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
private func waitForCondition(
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

    XCTFail("Timed out waiting for condition.")
}
