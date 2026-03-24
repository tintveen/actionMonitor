import XCTest
@testable import actionMonitor

@MainActor
final class StatusStoreTests: XCTestCase {
    func testStartShowsFreshInstallAuthenticationStateWhenSetupIsIncomplete() {
        let presenter = TestSettingsPresenter()
        let authManager = TestGitHubAuthManager(configuration: configuredOAuth())
        let setupStore = TestAppSetupStore(didCompleteOnboarding: false)
        let store = StatusStore(
            workflowStore: InMemoryMonitoredWorkflowStore(),
            appSetupStore: setupStore,
            settingsPresenter: presenter,
            authManager: authManager,
            promptsForIncompleteSetup: true
        )

        store.start()

        XCTAssertNil(store.onboardingStep)
        XCTAssertTrue(store.showsFreshInstallAuthenticationCTA)
        XCTAssertEqual(presenter.showOnboardingSteps, [])
        XCTAssertEqual(authManager.loadPersistedSessionCallCount, 1)
        XCTAssertEqual(authManager.ensureSessionLoadedCallCount, 0)
        XCTAssertEqual(presenter.openedExternalURLs, [])
    }

    func testStartRestoresSavedSessionWhenNoWorkflowExists() {
        let presenter = TestSettingsPresenter()
        let authManager = TestGitHubAuthManager(
            configuration: configuredOAuth(),
            session: githubOAuthSession()
        )
        let store = StatusStore(
            workflowStore: InMemoryMonitoredWorkflowStore(),
            appSetupStore: TestAppSetupStore(didCompleteOnboarding: false),
            settingsPresenter: presenter,
            authManager: authManager
        )

        store.start()

        XCTAssertNil(store.onboardingStep)
        XCTAssertFalse(store.showsFreshInstallAuthenticationCTA)
        XCTAssertEqual(presenter.showOnboardingSteps, [])
        XCTAssertEqual(store.authState, .signedInOAuthApp(githubOAuthSession().summary))
        XCTAssertEqual(authManager.loadPersistedSessionCallCount, 1)
        XCTAssertEqual(authManager.ensureSessionLoadedCallCount, 0)
        XCTAssertEqual(presenter.openedExternalURLs, [])
    }

    func testExistingSessionAndWorkflowAutoCompletesOnboarding() {
        let setupStore = TestAppSetupStore(didCompleteOnboarding: false)
        let store = StatusStore(
            workflowStore: InMemoryMonitoredWorkflowStore(initialWorkflows: [sampleWorkflow()]),
            appSetupStore: setupStore,
            settingsPresenter: TestSettingsPresenter(),
            authManager: TestGitHubAuthManager(
                configuration: configuredOAuth(),
                session: githubOAuthSession()
            )
        )

        store.start()

        XCTAssertFalse(store.shouldRouteSettingsToOnboarding)
        XCTAssertEqual(setupStore.savedValues.last, true)
    }

    func testStartDoesNotShowOnboardingForReturningUserWithLocalWorkflowAndNoRestoredSession() {
        let presenter = TestSettingsPresenter()
        let authManager = TestGitHubAuthManager(configuration: configuredOAuth())
        let setupStore = TestAppSetupStore(didCompleteOnboarding: false)
        let store = StatusStore(
            workflowStore: InMemoryMonitoredWorkflowStore(initialWorkflows: [sampleWorkflow()]),
            appSetupStore: setupStore,
            settingsPresenter: presenter,
            authManager: authManager,
            promptsForIncompleteSetup: true
        )

        store.start()

        XCTAssertNil(store.onboardingStep)
        XCTAssertFalse(store.showsFreshInstallAuthenticationCTA)
        XCTAssertEqual(presenter.showOnboardingSteps, [])
        XCTAssertEqual(store.authState, .signedOut)
        XCTAssertEqual(authManager.loadPersistedSessionCallCount, 1)
        XCTAssertEqual(authManager.ensureSessionLoadedCallCount, 0)
        XCTAssertEqual(setupStore.savedValues.last, true)
    }

    func testStartShowsReconnectMessageWhenPersistedSessionRequiresMigration() {
        let presenter = TestSettingsPresenter()
        let authManager = TestGitHubAuthManager(
            configuration: configuredOAuth(),
            loadPersistedSessionError: CredentialStoreError.migrationRequired
        )
        let store = StatusStore(
            workflowStore: InMemoryMonitoredWorkflowStore(),
            appSetupStore: TestAppSetupStore(didCompleteOnboarding: false),
            settingsPresenter: presenter,
            authManager: authManager,
            promptsForIncompleteSetup: false
        )

        store.start()

        XCTAssertEqual(store.authState, .signedOut)
        XCTAssertEqual(
            store.credentialMessage,
            CredentialStoreError.migrationRequired.localizedDescription
        )
        XCTAssertEqual(authManager.loadPersistedSessionCallCount, 1)
    }

    func testFreshInstallAuthenticateWithGitHubOpensBrowserImmediately() async {
        let presenter = TestSettingsPresenter()
        let authManager = TestGitHubAuthManager(
            configuration: configuredOAuth(),
            preparedContext: browserAuthorizationContext(),
            completedSession: githubOAuthSession()
        )
        let store = StatusStore(
            workflowStore: InMemoryMonitoredWorkflowStore(),
            appSetupStore: TestAppSetupStore(didCompleteOnboarding: false),
            settingsPresenter: presenter,
            authManager: authManager,
            promptsForIncompleteSetup: true
        )

        store.start()
        store.beginGitHubSignIn()

        await waitForCondition {
            authManager.completeAuthorizationCallCount == 1 && !store.isGitHubSignInBusy
        }

        XCTAssertEqual(presenter.openedExternalURLs, [browserAuthorizationContext().authorizationURL])
        XCTAssertEqual(authManager.ensureSessionLoadedCallCount, 0)
    }

    func testBrowserSignInPersistsSessionOpensBrowserAndAdvancesToWorkflowStep() async {
        let presenter = TestSettingsPresenter()
        let setupStore = TestAppSetupStore(didCompleteOnboarding: false)
        let authManager = TestGitHubAuthManager(
            configuration: configuredOAuth(),
            preparedContext: browserAuthorizationContext(),
            completedSession: githubOAuthSession()
        )
        let client = TestGitHubDataClient(
            accessibleRepositories: [
                GitHubAccessibleRepositorySummary(
                    id: 101,
                    ownerLogin: "octo-org",
                    ownerType: "Organization",
                    name: "dashboard",
                    fullName: "octo-org/dashboard",
                    isPrivate: true,
                    defaultBranch: "main"
                )
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
        guard case .signedInOAuthApp(let summary) = store.authState else {
            return XCTFail("Expected signed-in OAuth state, got \(store.authState)")
        }
        XCTAssertEqual(summary.login, "octocat")
        XCTAssertEqual(summary.selectedRepositoryCount, 1)
        XCTAssertEqual(store.onboardingStep, .firstWorkflow)
        XCTAssertEqual(authManager.session?.login, "octocat")
        XCTAssertEqual(authManager.session?.selectedRepositoryIDs, [101])
        XCTAssertEqual(store.accessibleRepositories.map(\.fullName), ["octo-org/dashboard"])
        XCTAssertEqual(authManager.ensureSessionLoadedCallCount, 0)
    }

    func testContinueInBrowserSkipsLazySessionRestore() async {
        let authManager = TestGitHubAuthManager(
            configuration: configuredOAuth(),
            session: githubOAuthSession(),
            preparedContext: browserAuthorizationContext(),
            completedSession: githubOAuthSession(login: "new-octocat", selectedRepositoryIDs: [])
        )
        let store = StatusStore(
            workflowStore: InMemoryMonitoredWorkflowStore(),
            appSetupStore: TestAppSetupStore(didCompleteOnboarding: false),
            settingsPresenter: TestSettingsPresenter(),
            authManager: authManager,
            promptsForIncompleteSetup: false
        )

        store.beginOnboarding()
        store.continueFromWelcome()
        store.beginGitHubSignIn()

        await waitForCondition {
            authManager.completeAuthorizationCallCount == 1 && !store.isGitHubSignInBusy
        }

        XCTAssertEqual(authManager.ensureSessionLoadedCallCount, 0)
        XCTAssertEqual(authManager.prepareAuthorizationCallCount, 1)
    }

    func testSavingFirstWorkflowAdvancesOnboardingToFinish() async throws {
        let store = StatusStore(
            workflowStore: InMemoryMonitoredWorkflowStore(),
            client: TestGitHubDataClient(),
            appSetupStore: TestAppSetupStore(didCompleteOnboarding: false),
            settingsPresenter: TestSettingsPresenter(),
            authManager: TestGitHubAuthManager(
                configuration: configuredOAuth(),
                session: githubOAuthSession()
            ),
            promptsForIncompleteSetup: false
        )

        store.showSettingsDirectly()
        await waitForCondition {
            store.hasStoredCredential
        }

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
                accessibleRepositories: [repository],
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
                session: githubOAuthSession(selectedRepositoryIDs: [repository.id])
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
                accessibleRepositories: [repository],
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
                session: githubOAuthSession(selectedRepositoryIDs: [repository.id])
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
                accessibleRepositories: [repository],
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
                session: githubOAuthSession(selectedRepositoryIDs: [repository.id])
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

    func testDiscoverWorkflowsShowsSSOGuidanceForBlockedOrganizationRepo() async {
        let repository = accessibleRepository()
        let store = StatusStore(
            workflowStore: InMemoryMonitoredWorkflowStore(),
            client: TestGitHubDataClient(
                accessibleRepositories: [repository],
                workflowErrorMessagesByRepository: [
                    "octo-org/dashboard": "Resource protected by organization SAML enforcement. You must grant your OAuth token access."
                ]
            ),
            appSetupStore: TestAppSetupStore(didCompleteOnboarding: false),
            settingsPresenter: TestSettingsPresenter(),
            authManager: TestGitHubAuthManager(
                configuration: configuredOAuth(),
                session: githubOAuthSession(selectedRepositoryIDs: [repository.id])
            ),
            promptsForIncompleteSetup: false
        )

        store.beginOnboarding()
        store.continueFromSignInStep()
        store.reloadGitHubAccess()

        await waitForCondition {
            !store.isDiscoveringWorkflows && store.workflowDiscoveryMessage != nil
        }

        XCTAssertEqual(store.workflowDiscoveryHelpTitle, "Open Org SSO")
        XCTAssertTrue(store.workflowDiscoveryMessage?.contains("needs an active SSO session") == true)
    }

    func testAddingSelectedDiscoveredWorkflowsPersistsAndAdvancesOnboarding() async throws {
        let repository = accessibleRepository()
        let store = StatusStore(
            workflowStore: InMemoryMonitoredWorkflowStore(),
            client: TestGitHubDataClient(
                accessibleRepositories: [repository],
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
                session: githubOAuthSession(selectedRepositoryIDs: [repository.id])
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
                accessibleRepositories: [repository],
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
                session: githubOAuthSession(selectedRepositoryIDs: [repository.id])
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

    func testFinishOnboardingPersistsCompletionAndDismissesWindow() async throws {
        let presenter = TestSettingsPresenter()
        let setupStore = TestAppSetupStore(didCompleteOnboarding: false)
        let store = StatusStore(
            workflowStore: InMemoryMonitoredWorkflowStore(initialWorkflows: [sampleWorkflow()]),
            client: TestGitHubDataClient(),
            appSetupStore: setupStore,
            settingsPresenter: presenter,
            authManager: TestGitHubAuthManager(
                configuration: configuredOAuth(),
                session: githubOAuthSession()
            ),
            promptsForIncompleteSetup: false
        )

        store.showSettingsDirectly()
        await waitForCondition {
            store.hasStoredCredential
        }

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

    func testSignOutAfterCompletionKeepsReturningUserOutOfFreshInstallState() {
        let setupStore = TestAppSetupStore(didCompleteOnboarding: true)
        let authManager = TestGitHubAuthManager(
            configuration: configuredOAuth(),
            session: githubOAuthSession()
        )
        let store = StatusStore(
            workflowStore: InMemoryMonitoredWorkflowStore(initialWorkflows: [sampleWorkflow()]),
            appSetupStore: setupStore,
            settingsPresenter: TestSettingsPresenter(),
            authManager: authManager,
            promptsForIncompleteSetup: false
        )

        store.signOut()

        XCTAssertEqual(store.authState, .signedOut)
        XCTAssertFalse(store.showsFreshInstallAuthenticationCTA)
        XCTAssertNil(setupStore.savedValues.last)
        XCTAssertNil(authManager.session)
    }

    func testLegacyGitHubAppSessionShowsReconnectMessageWithoutAuthErrorState() {
        let presenter = TestSettingsPresenter()
        let store = StatusStore(
            workflowStore: InMemoryMonitoredWorkflowStore(),
            appSetupStore: TestAppSetupStore(didCompleteOnboarding: false),
            settingsPresenter: presenter,
            authManager: TestGitHubAuthManager(
                configuration: configuredOAuth(),
                ensureSessionLoadedError: CredentialStoreError.migrationRequired
            ),
            promptsForIncompleteSetup: false
        )

        store.showSettingsDirectly()

        Task { @MainActor in }

        let expectation = XCTestExpectation(description: "migration message shown")
        Task { @MainActor in
            while store.credentialMessage == nil {
                try? await Task.sleep(for: .milliseconds(10))
            }
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)

        XCTAssertEqual(store.authState, .signedOut)
        XCTAssertEqual(
            store.credentialMessage,
            CredentialStoreError.migrationRequired.localizedDescription
        )
        XCTAssertEqual(presenter.showSettingsDirectlyCallCount, 1)
    }

    func testShowSettingsDirectlyLazilyRestoresOAuthSessionOnce() async {
        let presenter = TestSettingsPresenter()
        let repository = accessibleRepository()
        let authManager = TestGitHubAuthManager(
            configuration: configuredOAuth(),
            session: githubOAuthSession(selectedRepositoryIDs: [repository.id])
        )
        let store = StatusStore(
            workflowStore: InMemoryMonitoredWorkflowStore(),
            client: TestGitHubDataClient(accessibleRepositories: [repository]),
            appSetupStore: TestAppSetupStore(didCompleteOnboarding: true),
            settingsPresenter: presenter,
            authManager: authManager,
            promptsForIncompleteSetup: false
        )

        store.showSettingsDirectly()

        await waitForCondition {
            authManager.ensureSessionLoadedCallCount == 1 &&
                store.accessibleRepositories.map(\.fullName) == ["octo-org/dashboard"]
        }

        XCTAssertEqual(presenter.showSettingsDirectlyCallCount, 1)
        XCTAssertEqual(store.authState, .signedInOAuthApp(githubOAuthSession(selectedRepositoryIDs: [repository.id]).summary))
    }

    func testResetAppClearsPersistedStateAndClosesSettings() async throws {
        let presenter = TestSettingsPresenter()
        let workflowStore = InMemoryMonitoredWorkflowStore(initialWorkflows: [sampleWorkflow()])
        let setupStore = TestAppSetupStore(didCompleteOnboarding: true)
        let authManager = TestGitHubAuthManager(
            configuration: configuredOAuth(),
            session: githubOAuthSession()
        )
        let store = StatusStore(
            workflowStore: workflowStore,
            appSetupStore: setupStore,
            settingsPresenter: presenter,
            authManager: authManager,
            promptsForIncompleteSetup: false
        )

        store.showSettingsDirectly()
        await waitForCondition {
            store.hasStoredCredential
        }

        store.resetApp()

        await waitForCondition {
            !store.isResetting && store.workflows.isEmpty
        }

        XCTAssertTrue(store.showsFreshInstallAuthenticationCTA)
        XCTAssertEqual(store.authState, .signedOut)
        XCTAssertEqual(try workflowStore.loadWorkflows(), [])
        XCTAssertFalse(setupStore.loadDidCompleteOnboarding())
        XCTAssertEqual(presenter.dismissSettingsCallCount, 1)
        XCTAssertEqual(presenter.dismissOnboardingCallCount, 1)
    }

    func testResetAppCanBeRetriedAfterWorkflowResetFailure() async {
        let presenter = TestSettingsPresenter()
        let workflowStore = ResettableTestWorkflowStore(
            workflows: [sampleWorkflow()],
            resetError: MonitoredWorkflowStoreError.failedToSave(
                URL(fileURLWithPath: "/tmp/monitored-workflows.json"),
                "boom"
            )
        )
        let setupStore = TestAppSetupStore(didCompleteOnboarding: true)
        let authManager = TestGitHubAuthManager(
            configuration: configuredOAuth(),
            session: githubOAuthSession()
        )
        let store = StatusStore(
            workflowStore: workflowStore,
            appSetupStore: setupStore,
            settingsPresenter: presenter,
            authManager: authManager,
            promptsForIncompleteSetup: false
        )

        store.resetApp()
        await waitForCondition {
            !store.isResetting && store.resetMessage != nil
        }

        XCTAssertEqual(store.workflows.count, 1)
        XCTAssertNotNil(store.resetMessage)

        workflowStore.resetError = nil
        store.resetApp()

        await waitForCondition {
            !store.isResetting && store.workflows.isEmpty
        }

        XCTAssertTrue(store.showsFreshInstallAuthenticationCTA)
        XCTAssertNil(store.resetMessage)
    }
}

private final class TestGitHubAuthManager: GitHubAuthManaging, @unchecked Sendable {
    let configuration: GitHubOAuthAppConfiguration?
    var session: GitHubOAuthSession?
    let preparedContext: GitHubBrowserAuthorizationContext
    let completedSession: GitHubOAuthSession
    let loadPersistedSessionError: Error?
    let ensureSessionLoadedError: Error?
    private(set) var loadPersistedSessionCallCount = 0
    private(set) var prepareAuthorizationCallCount = 0
    private(set) var completeAuthorizationCallCount = 0
    private(set) var ensureSessionLoadedCallCount = 0
    private var didEnsureSessionLoad = false

    init(
        configuration: GitHubOAuthAppConfiguration?,
        session: GitHubOAuthSession? = nil,
        preparedContext: GitHubBrowserAuthorizationContext = browserAuthorizationContext(),
        completedSession: GitHubOAuthSession = githubOAuthSession(),
        loadPersistedSessionError: Error? = nil,
        ensureSessionLoadedError: Error? = nil
    ) {
        self.configuration = configuration
        self.session = session
        self.preparedContext = preparedContext
        self.completedSession = completedSession
        self.loadPersistedSessionError = loadPersistedSessionError
        self.ensureSessionLoadedError = ensureSessionLoadedError
    }

    func loadPersistedSession() throws -> GitHubOAuthSession? {
        loadPersistedSessionCallCount += 1

        if let loadPersistedSessionError {
            throw loadPersistedSessionError
        }

        return session
    }

    func currentSession() -> GitHubOAuthSession? {
        session
    }

    func ensureSessionLoaded() async throws -> GitHubOAuthSession? {
        if didEnsureSessionLoad {
            return session
        }

        didEnsureSessionLoad = true
        ensureSessionLoadedCallCount += 1

        if let ensureSessionLoadedError {
            throw ensureSessionLoadedError
        }

        return session
    }

    func prepareAuthorization() async throws -> GitHubBrowserAuthorizationContext {
        prepareAuthorizationCallCount += 1
        return preparedContext
    }

    func completeAuthorization(using context: GitHubBrowserAuthorizationContext) async throws -> GitHubOAuthSession {
        completeAuthorizationCallCount += 1
        session = completedSession
        return completedSession
    }

    func validSession() async throws -> GitHubOAuthSession? {
        session
    }

    func saveManualSession(_ session: GitHubOAuthSession) throws {
        self.session = session
    }

    func updateSelections(repositoryIDs: [Int64]) throws -> GitHubOAuthSession? {
        guard let session else {
            return nil
        }

        let updated = session.updatingSelections(repositoryIDs: repositoryIDs)
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
    private(set) var resetCallCount = 0

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

    func resetDidCompleteOnboarding() {
        resetCallCount += 1
        didCompleteOnboarding = false
    }
}

@MainActor
private final class TestSettingsPresenter: SettingsPresenting {
    private(set) var showSettingsCallCount = 0
    private(set) var showSettingsDirectlyCallCount = 0
    private(set) var dismissSettingsCallCount = 0
    private(set) var showOnboardingSteps: [OnboardingStep] = []
    private(set) var dismissOnboardingCallCount = 0
    private(set) var openedExternalURLs: [URL] = []

    func showSettings() {
        showSettingsCallCount += 1
    }

    func showSettingsDirectly() {
        showSettingsDirectlyCallCount += 1
    }

    func dismissSettings() {
        dismissSettingsCallCount += 1
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

private final class ResettableTestWorkflowStore: MonitoredWorkflowStore, @unchecked Sendable {
    private var workflows: [MonitoredWorkflow]
    var resetError: Error?

    init(workflows: [MonitoredWorkflow], resetError: Error? = nil) {
        self.workflows = workflows
        self.resetError = resetError
    }

    func loadWorkflows() throws -> [MonitoredWorkflow] {
        workflows
    }

    func saveWorkflows(_ workflows: [MonitoredWorkflow]) throws {
        self.workflows = workflows
    }

    func resetWorkflows() throws {
        if let resetError {
            throw resetError
        }

        workflows = []
    }
}

private struct TestGitHubDataClient: GitHubDataFetching {
    var accessibleRepositories: [GitHubAccessibleRepositorySummary] = []
    var workflowsByRepository: [String: [GitHubWorkflowSummary]] = [:]
    var workflowErrorMessagesByRepository: [String: String] = [:]

    func fetchViewer(accessToken: String) async throws -> GitHubUserProfile {
        GitHubUserProfile(id: 1, login: "octocat")
    }

    func fetchAccessibleRepositories(accessToken: String) async throws -> [GitHubAccessibleRepositorySummary] {
        accessibleRepositories
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

private func githubOAuthSession() -> GitHubOAuthSession {
    githubOAuthSession(selectedRepositoryIDs: [])
}

private func githubOAuthSession(
    login: String = "octocat",
    selectedRepositoryIDs: [Int64]
) -> GitHubOAuthSession {
    GitHubOAuthSession(
        accessToken: "oauth-token",
        userID: 42,
        login: login,
        source: .oauthBrowser,
        grantedScopes: ["repo"],
        savedAt: Date(timeIntervalSince1970: 1_712_000_000),
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
    ownerLogin: String = "octo-org",
    name: String = "dashboard",
    defaultBranch: String? = "main"
) -> GitHubAccessibleRepositorySummary {
    GitHubAccessibleRepositorySummary(
        id: id,
        ownerLogin: ownerLogin,
        ownerType: "Organization",
        name: name,
        fullName: "\(ownerLogin)/\(name)",
        isPrivate: true,
        defaultBranch: defaultBranch
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
