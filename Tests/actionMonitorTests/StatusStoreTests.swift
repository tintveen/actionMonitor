import XCTest
@testable import actionMonitor

@MainActor
final class StatusStoreTests: XCTestCase {
    func testStartShowsWelcomeOnboardingWhenSetupIsIncomplete() {
        let presenter = TestSettingsPresenter()
        let setupStore = TestAppSetupStore(didCompleteOnboarding: false)
        let store = StatusStore(
            workflowStore: InMemoryMonitoredWorkflowStore(),
            appSetupStore: setupStore,
            settingsPresenter: presenter,
            authManager: TestGitHubAuthManager(configuration: configuredOAuth()),
            promptsForIncompleteSetup: true
        )

        store.start()

        XCTAssertEqual(store.onboardingStep, .welcome)
        XCTAssertEqual(presenter.showOnboardingSteps, [.welcome])
    }

    func testStartShowsWorkflowStepWhenSessionExistsButNoWorkflow() {
        let presenter = TestSettingsPresenter()
        let authManager = TestGitHubAuthManager(
            configuration: configuredOAuth(),
            session: githubAppSession()
        )
        let store = StatusStore(
            workflowStore: InMemoryMonitoredWorkflowStore(),
            appSetupStore: TestAppSetupStore(didCompleteOnboarding: false),
            settingsPresenter: presenter,
            authManager: authManager
        )

        store.start()

        XCTAssertEqual(store.onboardingStep, .firstWorkflow)
        XCTAssertEqual(presenter.showOnboardingSteps, [.firstWorkflow])
    }

    func testExistingSessionAndWorkflowAutoCompletesOnboarding() {
        let setupStore = TestAppSetupStore(didCompleteOnboarding: false)
        let store = StatusStore(
            workflowStore: InMemoryMonitoredWorkflowStore(initialWorkflows: [sampleWorkflow()]),
            appSetupStore: setupStore,
            settingsPresenter: TestSettingsPresenter(),
            authManager: TestGitHubAuthManager(
                configuration: configuredOAuth(),
                session: githubAppSession()
            )
        )

        store.start()

        XCTAssertFalse(store.shouldRouteSettingsToOnboarding)
        XCTAssertEqual(setupStore.savedValues.last, true)
    }

    func testBrowserSignInPersistsSessionOpensBrowserAndAdvancesToWorkflowStep() async {
        let presenter = TestSettingsPresenter()
        let setupStore = TestAppSetupStore(didCompleteOnboarding: false)
        let authManager = TestGitHubAuthManager(
            configuration: configuredOAuth(),
            preparedContext: browserAuthorizationContext(),
            completedSession: githubAppSession()
        )
        let client = TestGitHubDataClient(
            installations: [
                GitHubInstallationSummary(
                    id: 1,
                    accountLogin: "octo-org",
                    accountType: "Organization",
                    targetType: "Organization",
                    repositorySelection: "selected"
                )
            ],
            repositoriesByInstallation: [
                1: [
                    GitHubAccessibleRepositorySummary(
                        id: 101,
                        installationID: 1,
                        ownerLogin: "octo-org",
                        name: "dashboard",
                        fullName: "octo-org/dashboard",
                        isPrivate: true,
                        defaultBranch: "main"
                    )
                ]
            ]
        )
        let store = StatusStore(
            workflowStore: InMemoryMonitoredWorkflowStore(),
            client: client,
            appSetupStore: setupStore,
            settingsPresenter: presenter,
            authManager: authManager,
            promptsForIncompleteSetup: false
        )

        store.beginOnboarding()
        store.continueFromWelcome()
        store.beginGitHubSignIn()

        await waitForCondition {
            authManager.completeAuthorizationCallCount == 1 && !store.isGitHubSignInBusy
        }

        XCTAssertEqual(authManager.prepareAuthorizationCallCount, 1)
        XCTAssertEqual(presenter.openedExternalURLs, [browserAuthorizationContext().authorizationURL])
        guard case .signedInGitHubApp(let summary) = store.authState else {
            return XCTFail("Expected signed-in GitHub App state, got \(store.authState)")
        }
        XCTAssertEqual(summary.login, "octocat")
        XCTAssertEqual(summary.selectedRepositoryCount, 1)
        XCTAssertEqual(store.onboardingStep, .firstWorkflow)
        XCTAssertEqual(authManager.session?.login, "octocat")
        XCTAssertEqual(authManager.session?.selectedInstallationIDs, [1])
        XCTAssertEqual(authManager.session?.selectedRepositoryIDs, [101])
        XCTAssertEqual(store.accessibleRepositories.map(\.fullName), ["octo-org/dashboard"])
    }

    func testSavingFirstWorkflowAdvancesOnboardingToFinish() throws {
        let store = StatusStore(
            workflowStore: InMemoryMonitoredWorkflowStore(),
            client: TestGitHubDataClient(),
            appSetupStore: TestAppSetupStore(didCompleteOnboarding: false),
            settingsPresenter: TestSettingsPresenter(),
            authManager: TestGitHubAuthManager(
                configuration: configuredOAuth(),
                session: githubAppSession()
            ),
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

    func testDiscoverWorkflowsPreselectsActiveSuggestionsAndLeavesInactiveSelectable() async {
        let repository = accessibleRepository()
        let store = StatusStore(
            workflowStore: InMemoryMonitoredWorkflowStore(),
            client: TestGitHubDataClient(
                installations: [installationSummary(id: repository.installationID, accountLogin: repository.ownerLogin)],
                repositoriesByInstallation: [1: [repository]],
                workflowsByRepository: [
                    "octo-org/dashboard": [
                        GitHubWorkflowSummary(id: 201, name: "Deploy", path: ".github/workflows/deploy.yml", state: "active"),
                        GitHubWorkflowSummary(id: 202, name: "Nightly", path: ".github/workflows/nightly.yml", state: "disabled_manually"),
                    ]
                ]
            ),
            appSetupStore: TestAppSetupStore(didCompleteOnboarding: false),
            settingsPresenter: TestSettingsPresenter(),
            authManager: TestGitHubAuthManager(
                configuration: configuredOAuth(),
                session: githubAppSession(selectedRepositoryIDs: [repository.id], selectedInstallationIDs: [repository.installationID])
            ),
            promptsForIncompleteSetup: false,
            allowsPersonalAccessTokenFallback: true
        )

        store.beginOnboarding()
        store.continueFromSignInStep()
        store.reloadGitHubAccess()

        await waitForCondition {
            !store.isDiscoveringWorkflows && store.discoveredWorkflowSuggestions.count == 2
        }

        let suggestionsByName = Dictionary(uniqueKeysWithValues: store.discoveredWorkflowSuggestions.map { ($0.displayName, $0) })
        XCTAssertEqual(suggestionsByName["Deploy"]?.isSelected, true)
        XCTAssertEqual(suggestionsByName["Deploy"]?.isSelectable, true)
        XCTAssertEqual(suggestionsByName["Nightly"]?.isSelected, false)
        XCTAssertEqual(suggestionsByName["Nightly"]?.isSelectable, true)
        XCTAssertEqual(suggestionsByName["Nightly"]?.statusLabel, "Not active on GitHub")
    }

    func testDiscoverWorkflowsMarksLegacyPathMatchAsAlreadyAdded() async {
        let repository = accessibleRepository()
        let existingWorkflow = sampleWorkflow(
            displayName: "Deploy",
            owner: repository.ownerLogin,
            repo: repository.name,
            branch: repository.defaultBranch ?? "main",
            workflowID: nil,
            workflowFile: ".github/workflows/deploy.yml"
        )
        let store = StatusStore(
            workflowStore: InMemoryMonitoredWorkflowStore(initialWorkflows: [existingWorkflow]),
            client: TestGitHubDataClient(
                installations: [installationSummary(id: repository.installationID, accountLogin: repository.ownerLogin)],
                repositoriesByInstallation: [1: [repository]],
                workflowsByRepository: [
                    "octo-org/dashboard": [
                        GitHubWorkflowSummary(id: 201, name: "Deploy", path: ".github/workflows/deploy.yml", state: "active")
                    ]
                ]
            ),
            appSetupStore: TestAppSetupStore(didCompleteOnboarding: false),
            settingsPresenter: TestSettingsPresenter(),
            authManager: TestGitHubAuthManager(
                configuration: configuredOAuth(),
                session: githubAppSession(selectedRepositoryIDs: [repository.id], selectedInstallationIDs: [repository.installationID])
            ),
            promptsForIncompleteSetup: false,
            allowsPersonalAccessTokenFallback: true
        )

        store.beginOnboarding()
        store.continueFromSignInStep()
        store.reloadGitHubAccess()

        await waitForCondition {
            !store.isDiscoveringWorkflows && store.discoveredWorkflowSuggestions.count == 1
        }

        XCTAssertEqual(store.discoveredWorkflowSuggestions.first?.isAlreadyMonitored, true)
        XCTAssertEqual(store.discoveredWorkflowSuggestions.first?.isSelectable, false)
        XCTAssertEqual(store.discoveredWorkflowSuggestions.first?.statusLabel, "Already added")
    }

    func testDiscoverWorkflowsHandlesZeroSelectedRepositoriesWithoutError() async {
        let repository = accessibleRepository()
        let store = StatusStore(
            workflowStore: InMemoryMonitoredWorkflowStore(),
            client: TestGitHubDataClient(
                installations: [installationSummary(id: repository.installationID, accountLogin: repository.ownerLogin)],
                repositoriesByInstallation: [1: [repository]],
                workflowsByRepository: [
                    "octo-org/dashboard": [
                        GitHubWorkflowSummary(id: 201, name: "Deploy", path: ".github/workflows/deploy.yml", state: "active")
                    ]
                ]
            ),
            appSetupStore: TestAppSetupStore(didCompleteOnboarding: false),
            settingsPresenter: TestSettingsPresenter(),
            authManager: TestGitHubAuthManager(
                configuration: configuredOAuth(),
                session: githubAppSession(selectedRepositoryIDs: [repository.id], selectedInstallationIDs: [repository.installationID])
            ),
            promptsForIncompleteSetup: false,
            allowsPersonalAccessTokenFallback: true
        )

        store.reloadGitHubAccess()
        await waitForCondition {
            store.accessibleRepositories.count == 1
        }

        store.clearAccessibleRepositorySelection()
        store.discoverWorkflows()

        XCTAssertTrue(store.selectedRepositoryIDs.isEmpty)
        XCTAssertFalse(store.hasSelectedAccessibleRepositories)
        XCTAssertEqual(store.discoveredWorkflowSuggestions, [])
        XCTAssertNil(store.workflowDiscoveryMessage)
    }

    func testAddingSelectedDiscoveredWorkflowsPersistsAndAdvancesOnboarding() async throws {
        let repository = accessibleRepository()
        let store = StatusStore(
            workflowStore: InMemoryMonitoredWorkflowStore(),
            client: TestGitHubDataClient(
                installations: [installationSummary(id: repository.installationID, accountLogin: repository.ownerLogin)],
                repositoriesByInstallation: [1: [repository]],
                workflowsByRepository: [
                    "octo-org/dashboard": [
                        GitHubWorkflowSummary(id: 201, name: "Deploy", path: ".github/workflows/deploy.yml", state: "active")
                    ]
                ]
            ),
            appSetupStore: TestAppSetupStore(didCompleteOnboarding: false),
            settingsPresenter: TestSettingsPresenter(),
            authManager: TestGitHubAuthManager(
                configuration: configuredOAuth(),
                session: githubAppSession(selectedRepositoryIDs: [repository.id], selectedInstallationIDs: [repository.installationID])
            ),
            promptsForIncompleteSetup: false
        )

        store.beginOnboarding()
        store.continueFromSignInStep()
        store.reloadGitHubAccess()

        await waitForCondition {
            !store.isDiscoveringWorkflows && store.discoveredWorkflowSuggestions.count == 1
        }

        try store.addSelectedDiscoveredWorkflows()

        XCTAssertEqual(store.workflows.count, 1)
        XCTAssertEqual(store.workflows.first?.workflowID, 201)
        XCTAssertEqual(store.workflows.first?.branch, "main")
        XCTAssertEqual(store.onboardingStep, .finish)
    }

    func testRepositorySelectionAndSessionChangesResetDiscoveryState() async {
        let repository = accessibleRepository()
        let store = StatusStore(
            workflowStore: InMemoryMonitoredWorkflowStore(),
            client: TestGitHubDataClient(
                installations: [installationSummary(id: repository.installationID, accountLogin: repository.ownerLogin)],
                repositoriesByInstallation: [1: [repository]],
                workflowsByRepository: [
                    "octo-org/dashboard": [
                        GitHubWorkflowSummary(id: 201, name: "Deploy", path: ".github/workflows/deploy.yml", state: "active")
                    ]
                ]
            ),
            appSetupStore: TestAppSetupStore(didCompleteOnboarding: false),
            settingsPresenter: TestSettingsPresenter(),
            authManager: TestGitHubAuthManager(
                configuration: configuredOAuth(),
                session: githubAppSession(selectedRepositoryIDs: [repository.id], selectedInstallationIDs: [repository.installationID])
            ),
            promptsForIncompleteSetup: false,
            allowsPersonalAccessTokenFallback: true
        )

        store.beginOnboarding()
        store.continueFromSignInStep()
        store.reloadGitHubAccess()

        await waitForCondition {
            !store.isDiscoveringWorkflows && store.discoveredWorkflowSuggestions.count == 1
        }

        store.clearAccessibleRepositorySelection()
        XCTAssertEqual(store.discoveredWorkflowSuggestions, [])

        store.reloadGitHubAccess()
        await waitForCondition {
            store.accessibleRepositories.count == 1 && store.selectedRepositoryIDs == [repository.id]
        }
        store.discoverWorkflows()
        await waitForCondition {
            !store.isDiscoveringWorkflows && store.discoveredWorkflowSuggestions.count == 1
        }

        store.savePersonalAccessToken("manual-token")
        XCTAssertEqual(store.discoveredWorkflowSuggestions, [])
        XCTAssertFalse(store.canDiscoverWorkflows)
    }

    func testFinishOnboardingPersistsCompletionAndDismissesWindow() throws {
        let presenter = TestSettingsPresenter()
        let setupStore = TestAppSetupStore(didCompleteOnboarding: false)
        let store = StatusStore(
            workflowStore: InMemoryMonitoredWorkflowStore(initialWorkflows: [sampleWorkflow()]),
            client: TestGitHubDataClient(),
            appSetupStore: setupStore,
            settingsPresenter: presenter,
            authManager: TestGitHubAuthManager(
                configuration: configuredOAuth(),
                session: githubAppSession()
            ),
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
            appSetupStore: setupStore,
            settingsPresenter: presenter,
            authManager: TestGitHubAuthManager(configuration: configuredOAuth()),
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
        let authManager = TestGitHubAuthManager(
            configuration: configuredOAuth(),
            session: githubAppSession()
        )
        let store = StatusStore(
            workflowStore: InMemoryMonitoredWorkflowStore(initialWorkflows: [sampleWorkflow()]),
            appSetupStore: setupStore,
            settingsPresenter: TestSettingsPresenter(),
            authManager: authManager,
            promptsForIncompleteSetup: false
        )

        store.signOut()

        XCTAssertTrue(store.shouldRouteSettingsToOnboarding)
        XCTAssertEqual(store.authState, .signedOut)
        XCTAssertEqual(setupStore.savedValues.last, false)
        XCTAssertNil(authManager.session)
    }
}

private final class TestGitHubAuthManager: GitHubAuthManaging, @unchecked Sendable {
    let configuration: GitHubAppConfiguration?
    var session: GitHubAppSession?
    let preparedContext: GitHubBrowserAuthorizationContext
    let completedSession: GitHubAppSession
    private(set) var prepareAuthorizationCallCount = 0
    private(set) var completeAuthorizationCallCount = 0
    private(set) var forceRefreshCallCount = 0

    init(
        configuration: GitHubAppConfiguration?,
        session: GitHubAppSession? = nil,
        preparedContext: GitHubBrowserAuthorizationContext = browserAuthorizationContext(),
        completedSession: GitHubAppSession = githubAppSession()
    ) {
        self.configuration = configuration
        self.session = session
        self.preparedContext = preparedContext
        self.completedSession = completedSession
    }

    func loadPersistedSession() throws -> GitHubAppSession? {
        session
    }

    func currentSession() -> GitHubAppSession? {
        session
    }

    func prepareAuthorization() async throws -> GitHubBrowserAuthorizationContext {
        prepareAuthorizationCallCount += 1
        return preparedContext
    }

    func completeAuthorization(using context: GitHubBrowserAuthorizationContext) async throws -> GitHubAppSession {
        completeAuthorizationCallCount += 1
        session = completedSession
        return completedSession
    }

    func validSession() async throws -> GitHubAppSession? {
        session
    }

    func refreshSessionIfNeeded() async throws -> GitHubAppSession? {
        session
    }

    func forceRefreshSession() async throws -> GitHubAppSession? {
        forceRefreshCallCount += 1
        return session
    }

    func saveManualSession(_ session: GitHubAppSession) throws {
        self.session = session
    }

    func updateSelections(installationIDs: [Int64], repositoryIDs: [Int64]) throws -> GitHubAppSession? {
        guard let session else {
            return nil
        }

        let updated = session.updatingSelections(
            installationIDs: installationIDs,
            repositoryIDs: repositoryIDs
        )
        self.session = updated
        return updated
    }

    func disconnect() throws {
        session = nil
    }

    func cancelAuthorization() {}
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
    private(set) var showSettingsDirectlyCallCount = 0
    private(set) var showOnboardingSteps: [OnboardingStep] = []
    private(set) var dismissOnboardingCallCount = 0
    private(set) var openedExternalURLs: [URL] = []

    func showSettings() {
        showSettingsCallCount += 1
    }

    func showSettingsDirectly() {
        showSettingsDirectlyCallCount += 1
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

private struct TestGitHubDataClient: GitHubDataFetching {
    var installations: [GitHubInstallationSummary] = []
    var repositoriesByInstallation: [Int64: [GitHubAccessibleRepositorySummary]] = [:]
    var workflowsByRepository: [String: [GitHubWorkflowSummary]] = [:]
    var workflowErrorMessagesByRepository: [String: String] = [:]

    func fetchViewer(accessToken: String) async throws -> GitHubUserProfile {
        GitHubUserProfile(id: 1, login: "octocat")
    }

    func fetchInstallations(accessToken: String) async throws -> [GitHubInstallationSummary] {
        installations
    }

    func fetchRepositories(
        for installationID: Int64,
        accessToken: String
    ) async throws -> [GitHubAccessibleRepositorySummary] {
        repositoriesByInstallation[installationID] ?? []
    }

    func fetchWorkflows(
        owner: String,
        repo: String,
        accessToken: String
    ) async throws -> [GitHubWorkflowSummary] {
        let repositoryKey = "\(owner)/\(repo)"
        if let errorMessage = workflowErrorMessagesByRepository[repositoryKey] {
            throw TestGitHubDataClientError(message: errorMessage)
        }

        return workflowsByRepository[repositoryKey] ?? []
    }

    func fetchLatestRun(for workflow: MonitoredWorkflow, token: String?) async throws -> WorkflowRun? {
        nil
    }

    func fetchJobs(
        owner: String,
        repo: String,
        runID: Int64,
        accessToken: String
    ) async throws -> [GitHubWorkflowJob] {
        []
    }

    func fetchJob(
        owner: String,
        repo: String,
        jobID: Int64,
        accessToken: String
    ) async throws -> GitHubWorkflowJob {
        GitHubWorkflowJob(
            id: jobID,
            runID: 1,
            htmlURL: nil,
            status: "completed",
            conclusion: "success",
            startedAt: nil,
            completedAt: nil,
            name: "deploy",
            workflowName: "Deploy",
            headBranch: "main"
        )
    }
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
        redirectURI: URL(string: "http://127.0.0.1:8123/callback")!,
        state: "oauth-state",
        codeVerifier: "oauth-code-verifier",
        expiresAt: Date(timeIntervalSince1970: 1_712_000_000)
    )
}

private func githubAppSession() -> GitHubAppSession {
    githubAppSession(selectedRepositoryIDs: [], selectedInstallationIDs: [])
}

private func githubAppSession(
    login: String = "octocat",
    selectedRepositoryIDs: [Int64],
    selectedInstallationIDs: [Int64]
) -> GitHubAppSession {
    GitHubAppSession(
        accessToken: "oauth-token",
        accessTokenExpiresAt: Date(timeIntervalSince1970: 1_712_028_800),
        refreshToken: "refresh-token",
        refreshTokenExpiresAt: Date(timeIntervalSince1970: 1_727_897_600),
        userID: 42,
        login: login,
        source: .githubAppBrowser,
        savedAt: Date(timeIntervalSince1970: 1_712_000_000),
        selectedInstallationIDs: selectedInstallationIDs,
        selectedRepositoryIDs: selectedRepositoryIDs
    )
}

private func sampleWorkflow(
    displayName: String = "Example",
    owner: String = "tintveen",
    repo: String = "example.com",
    branch: String = "main",
    workflowID: Int64? = nil,
    workflowFile: String = "deploy.yml",
    siteURL: URL? = URL(string: "https://example.com")
) -> MonitoredWorkflow {
    MonitoredWorkflow(
        id: UUID(),
        displayName: displayName,
        owner: owner,
        repo: repo,
        branch: branch,
        workflowID: workflowID,
        workflowFile: workflowFile,
        siteURL: siteURL
    )
}

private func accessibleRepository(
    id: Int64 = 101,
    installationID: Int64 = 1,
    ownerLogin: String = "octo-org",
    name: String = "dashboard",
    defaultBranch: String? = "main"
) -> GitHubAccessibleRepositorySummary {
    GitHubAccessibleRepositorySummary(
        id: id,
        installationID: installationID,
        ownerLogin: ownerLogin,
        name: name,
        fullName: "\(ownerLogin)/\(name)",
        isPrivate: true,
        defaultBranch: defaultBranch
    )
}

private func installationSummary(
    id: Int64 = 1,
    accountLogin: String = "octo-org"
) -> GitHubInstallationSummary {
    GitHubInstallationSummary(
        id: id,
        accountLogin: accountLogin,
        accountType: "Organization",
        targetType: "Organization",
        repositorySelection: "selected"
    )
}

private struct TestGitHubDataClientError: LocalizedError {
    let message: String

    var errorDescription: String? {
        message
    }
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
