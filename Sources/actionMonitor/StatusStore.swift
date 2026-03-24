import Foundation
#if canImport(Combine)
import Combine
#else
protocol ObservableObject: AnyObject {}

@propertyWrapper
struct Published<Value> {
    var wrappedValue: Value

    init(wrappedValue: Value) {
        self.wrappedValue = wrappedValue
    }
}
#endif

enum StatusStoreError: LocalizedError {
    case workflowNotFound
    case onboardingRequirementsNotMet

    var errorDescription: String? {
        switch self {
        case .workflowNotFound:
            return "That workflow could not be found."
        case .onboardingRequirementsNotMet:
            return "Complete GitHub sign-in and add a workflow before finishing setup."
        }
    }
}

@MainActor
final class StatusStore: ObservableObject {
    @Published private(set) var workflows: [MonitoredWorkflow]
    @Published private(set) var states: [DeployState]
    @Published private(set) var combinedStatus: DeployStatus
    @Published private(set) var workflowRefreshInterval: WorkflowRefreshInterval
    @Published private(set) var isRefreshing = false
    @Published private(set) var isResetting = false
    @Published private(set) var bannerMessage: String?
    @Published private(set) var authState: GitHubAuthState
    @Published private(set) var credentialMessage: String?
    @Published private(set) var resetMessage: String?
    @Published private(set) var workflowConfigurationMessage: String?
    @Published private(set) var gitHubSignInConfigurationMessage: String?
    @Published private(set) var onboardingStep: OnboardingStep?
    @Published private(set) var accessibleRepositories: [GitHubAccessibleRepositorySummary]
    @Published private(set) var isLoadingGitHubAccess = false
    @Published private(set) var discoveredWorkflowSuggestions: [DiscoveredWorkflowSuggestion]
    @Published private(set) var isDiscoveringWorkflows = false
    @Published private(set) var workflowDiscoveryMessage: String?
    @Published private(set) var workflowDiscoveryHelpTitle: String?

    private let workflowStore: any MonitoredWorkflowStore
    private let client: any GitHubDataFetching
    private let appSetupStore: any AppSetupStore
    private let windowPresenter: any SettingsPresenting
    private let authManager: any GitHubAuthManaging
    private let promptsForIncompleteSetup: Bool
    private let showsMissingCredentialBanner: Bool
    private let allowsPersonalAccessTokenFallback: Bool

    private var currentSession: GitHubOAuthSession?
    private var didCompleteOnboarding: Bool
    private var refreshLoopTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private var signInTask: Task<Void, Never>?
    private var accessDirectoryTask: Task<Void, Never>?
    private var workflowDiscoveryTask: Task<Void, Never>?
    private var resetTask: Task<Void, Never>?
    private var didStart = false
    private var hasPromptedForAuthFailure = false
    private var pendingRefresh = false
    private var workflowsVersion = 0
    private var sessionIdentity: EffectiveGitHubSessionIdentity?
    private var workflowDiscoveryHelpURL: URL?

    init(
        workflows initialWorkflows: [MonitoredWorkflow]? = nil,
        workflowStore: any MonitoredWorkflowStore = FileBackedMonitoredWorkflowStore(),
        client: any GitHubDataFetching = GitHubClient(),
        appSetupStore: any AppSetupStore = UserDefaultsAppSetupStore(),
        settingsPresenter: any SettingsPresenting = NoOpSettingsPresenter(),
        authManager: any GitHubAuthManaging = GitHubAuthManager(),
        promptsForIncompleteSetup: Bool = true,
        showsMissingCredentialBanner: Bool = true,
        allowsPersonalAccessTokenFallback: Bool = ProcessInfo.processInfo.environment["ACTIONMONITOR_ENABLE_PAT_FALLBACK"] == "1"
    ) {
        self.workflowStore = workflowStore
        self.client = client
        self.appSetupStore = appSetupStore
        self.windowPresenter = settingsPresenter
        self.authManager = authManager
        self.promptsForIncompleteSetup = promptsForIncompleteSetup
        self.showsMissingCredentialBanner = showsMissingCredentialBanner
        self.allowsPersonalAccessTokenFallback = allowsPersonalAccessTokenFallback
        accessibleRepositories = []
        discoveredWorkflowSuggestions = []

        let loadedWorkflows: [MonitoredWorkflow]
        if let initialWorkflows {
            loadedWorkflows = initialWorkflows
        } else {
            do {
                loadedWorkflows = try workflowStore.loadWorkflows()
            } catch {
                loadedWorkflows = []
                workflowConfigurationMessage = error.localizedDescription
            }
        }

        let initialStates = loadedWorkflows.map(DeployState.placeholder(for:))
        workflows = loadedWorkflows
        states = initialStates
        combinedStatus = CombinedStatus.reduce(initialStates)

        currentSession = nil
        authState = .signedOut
        onboardingStep = nil
        didCompleteOnboarding = appSetupStore.loadDidCompleteOnboarding()
        workflowRefreshInterval = appSetupStore.loadWorkflowRefreshInterval()
        gitHubSignInConfigurationMessage = authManager.configuration == nil
            ? GitHubOAuthAppConfiguration.missingConfigurationMessage
            : nil

        if !didCompleteOnboarding,
           !loadedWorkflows.isEmpty {
            didCompleteOnboarding = true
            appSetupStore.saveDidCompleteOnboarding(true)
        }
    }

    var gitHubSignInIsAvailable: Bool {
        authManager.configuration != nil
    }

    var isGitHubSignInBusy: Bool {
        signInTask != nil
    }

    var hasStoredCredential: Bool {
        currentSession != nil
    }

    var hasStoredPersonalAccessToken: Bool {
        currentSession?.source == .personalAccessToken
    }

    var shouldRouteSettingsToOnboarding: Bool {
        !didCompleteOnboarding
    }

    var canFinishOnboarding: Bool {
        currentSession != nil && !workflows.isEmpty
    }

    var onboardingSummaryText: String {
        let loginText = currentSession?.login.map { "@\($0)" } ?? "your GitHub account"
        if workflows.isEmpty {
            return "Signed in as \(loginText). Add your first workflow to finish setup."
        }

        return "Signed in as \(loginText) and watching \(workflows.count) workflow\(workflows.count == 1 ? "" : "s")."
    }

    var selectedRepositoryIDs: Set<Int64> {
        Set(currentSession?.selectedRepositoryIDs ?? [])
    }

    var supportsRepositorySelection: Bool {
        currentSession?.source == .oauthBrowser
    }

    var selectedAccessibleRepositories: [GitHubAccessibleRepositorySummary] {
        accessibleRepositories.filter { selectedRepositoryIDs.contains($0.id) }
    }

    var hasSelectedAccessibleRepositories: Bool {
        !selectedAccessibleRepositories.isEmpty
    }

    var canDiscoverWorkflows: Bool {
        supportsRepositorySelection && hasStoredCredential
    }

    var hasSelectedDiscoveredWorkflows: Bool {
        discoveredWorkflowSuggestions.contains { $0.isSelectable && $0.isSelected }
    }

    var selectedDiscoveredWorkflowCount: Int {
        discoveredWorkflowSuggestions.filter { $0.isSelectable && $0.isSelected }.count
    }

    var selectableDiscoveredWorkflowCount: Int {
        discoveredWorkflowSuggestions.filter(\.isSelectable).count
    }

    var showsPersonalAccessTokenFallback: Bool {
        allowsPersonalAccessTokenFallback
    }

    var showsFreshInstallAuthenticationCTA: Bool {
        workflows.isEmpty && !didCompleteOnboarding && currentSession == nil
    }

    func start() {
        guard !didStart else {
            return
        }

        didStart = true
        restorePersistedSession()
        refreshNow()
        beginRefreshLoop()
    }

    func refreshNow() {
        guard refreshTask == nil else {
            pendingRefresh = true
            return
        }

        guard !workflows.isEmpty else {
            isRefreshing = false
            bannerMessage = nil
            states = []
            combinedStatus = .unknown
            return
        }

        let workflowSnapshot = workflows
        let workflowVersion = workflowsVersion

        refreshTask = Task { [weak self] in
            guard let self else {
                return
            }

            await self.performRefresh(workflows: workflowSnapshot, version: workflowVersion)
            self.refreshTask = nil

            if self.pendingRefresh {
                self.pendingRefresh = false
                self.refreshNow()
            }
        }
    }

    func setWorkflowRefreshInterval(_ interval: WorkflowRefreshInterval) {
        guard workflowRefreshInterval != interval else {
            return
        }

        workflowRefreshInterval = interval
        appSetupStore.saveWorkflowRefreshInterval(interval)

        if didStart {
            beginRefreshLoop()
        }

        refreshNow()
    }

    func beginOnboarding() {
        onboardingStep = suggestedOnboardingStep()
        windowPresenter.showOnboarding(startingAt: onboardingStep ?? .welcome)
    }

    func skipOnboarding() {
        onboardingStep = nil
        appSetupStore.saveDidCompleteOnboarding(false)
        didCompleteOnboarding = false
        windowPresenter.dismissOnboarding()
    }

    func continueFromWelcome() {
        onboardingStep = .githubSignIn
    }

    func continueFromSignInStep() {
        onboardingStep = .firstWorkflow
        if supportsRepositorySelection {
            discoverWorkflows()
        }
    }

    func continueFromWorkflowStep() {
        onboardingStep = .finish
    }

    func moveBackInOnboarding() {
        guard let onboardingStep else {
            return
        }

        switch onboardingStep {
        case .welcome:
            return
        case .githubSignIn:
            self.onboardingStep = .welcome
        case .firstWorkflow:
            self.onboardingStep = .githubSignIn
        case .finish:
            self.onboardingStep = .firstWorkflow
        }
    }

    func finishOnboarding() throws {
        guard canFinishOnboarding else {
            throw StatusStoreError.onboardingRequirementsNotMet
        }

        didCompleteOnboarding = true
        appSetupStore.saveDidCompleteOnboarding(true)
        onboardingStep = nil
        windowPresenter.dismissOnboarding()
    }

    func beginGitHubSignIn() {
        guard signInTask == nil else {
            return
        }

        guard gitHubSignInIsAvailable else {
            credentialMessage = gitHubSignInConfigurationMessage ?? GitHubOAuthAppConfiguration.missingConfigurationMessage
            return
        }

        credentialMessage = nil

        signInTask = Task { [weak self] in
            guard let self else {
                return
            }

            do {
                let context = try await self.authManager.prepareAuthorization()
                self.authState = .signingInBrowser(context)
                self.windowPresenter.openExternalURL(context.authorizationURL)

                let session = try await self.authManager.completeAuthorization(using: context)
                self.synchronizeSession(
                    session,
                    successMessage: session.login.map { "Connected GitHub as @\($0)." }
                        ?? "GitHub session saved locally."
                )
                self.hasPromptedForAuthFailure = false
                self.advanceOnboardingAfterSuccessfulAuth()
                self.reloadGitHubAccess()
                self.refreshNow()
            } catch let error as GitHubBrowserOAuthError where error == .callbackCancelled {
                self.restoreAuthStateFromCurrentSession()
            } catch {
                self.restoreAuthStateFromCurrentSession(orError: error.localizedDescription)
                self.credentialMessage = error.localizedDescription
            }

            self.signInTask = nil
        }
    }

    func reopenBrowserSignIn() {
        guard case .signingInBrowser(let context) = authState else {
            return
        }

        windowPresenter.openExternalURL(context.authorizationURL)
    }

    func cancelGitHubSignIn() {
        guard signInTask != nil else {
            return
        }

        authManager.cancelAuthorization()
        signInTask?.cancel()
        credentialMessage = "GitHub sign-in cancelled."
    }

    func savePersonalAccessToken(_ token: String) {
        guard showsPersonalAccessTokenFallback else {
            credentialMessage = "Personal access token fallback is disabled for this build."
            return
        }

        let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            cancelGitHubSignInIfNeeded()
            resetWorkflowDiscoveryState()

            if trimmedToken.isEmpty {
                try clearSavedSession(message: "Saved GitHub session removed.")
            } else {
                let session = GitHubOAuthSession(
                    accessToken: trimmedToken,
                    source: .personalAccessToken
                )
                try authManager.saveManualSession(session)
                synchronizeSession(session, successMessage: "Personal access token saved locally.")
            }

            hasPromptedForAuthFailure = false
            refreshNow()
        } catch {
            credentialMessage = error.localizedDescription
        }
    }

    func signOut() {
        do {
            cancelGitHubSignInIfNeeded()
            try clearSavedSession(message: "Saved GitHub session removed.")
            hasPromptedForAuthFailure = false
            if workflows.isEmpty {
                didCompleteOnboarding = false
                appSetupStore.saveDidCompleteOnboarding(false)
            }
            if onboardingStep != nil {
                onboardingStep = workflows.isEmpty ? .welcome : .githubSignIn
            }
            refreshNow()
        } catch {
            credentialMessage = error.localizedDescription
        }
    }

    func resetApp() {
        guard resetTask == nil else {
            return
        }

        cancelWorkInFlightForReset()
        isResetting = true
        resetMessage = nil

        resetTask = Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            do {
                try self.workflowStore.resetWorkflows()
                self.appSetupStore.resetDidCompleteOnboarding()
                self.appSetupStore.resetWorkflowRefreshInterval()
                try self.authManager.disconnect()
                self.applySuccessfulResetState()
                self.windowPresenter.dismissOnboarding()
                self.windowPresenter.dismissSettings()
            } catch {
                self.reconcileStateAfterFailedReset(error: error)
            }

            self.isResetting = false
            self.resetTask = nil
        }
    }

    func reloadGitHubAccess() {
        accessDirectoryTask?.cancel()
        accessDirectoryTask = Task { [weak self] in
            guard let self else {
                return
            }

            self.isLoadingGitHubAccess = true
            defer {
                self.isLoadingGitHubAccess = false
            }

            guard let session = await self.ensureSessionLoadedForUserTriggeredGitHubAction() else {
                self.accessibleRepositories = []
                self.resetWorkflowDiscoveryState()
                return
            }

            guard session.source == .oauthBrowser else {
                self.accessibleRepositories = []
                self.resetWorkflowDiscoveryState()
                return
            }

            do {
                _ = try await self.client.fetchViewer(accessToken: session.accessToken)
                let repositories = try await self.client.fetchAccessibleRepositories(accessToken: session.accessToken)
                    .sorted { $0.fullName.localizedCaseInsensitiveCompare($1.fullName) == .orderedAscending }

                self.accessibleRepositories = repositories
                try self.normalizeRepositorySelection()
                if self.onboardingStep == .firstWorkflow {
                    self.discoverWorkflows()
                }
            } catch {
                if self.shouldClearSession(for: error) {
                    self.handleInvalidSession(errorMessage: error.localizedDescription)
                }
                self.credentialMessage = error.localizedDescription
            }
        }
    }

    func isRepositorySelected(_ repositoryID: Int64) -> Bool {
        selectedRepositoryIDs.contains(repositoryID)
    }

    func toggleRepositorySelection(_ repositoryID: Int64) {
        var nextRepositoryIDs = selectedRepositoryIDs
        if nextRepositoryIDs.contains(repositoryID) {
            nextRepositoryIDs.remove(repositoryID)
        } else {
            nextRepositoryIDs.insert(repositoryID)
        }

        persistRepositorySelection(nextRepositoryIDs)
    }

    func setRepositorySelection(_ repositoryID: Int64, isSelected: Bool) {
        var nextRepositoryIDs = selectedRepositoryIDs
        if isSelected {
            nextRepositoryIDs.insert(repositoryID)
        } else {
            nextRepositoryIDs.remove(repositoryID)
        }

        persistRepositorySelection(nextRepositoryIDs)
    }

    func selectAllAccessibleRepositories() {
        persistRepositorySelection(Set(accessibleRepositories.map(\.id)))
    }

    func clearAccessibleRepositorySelection() {
        persistRepositorySelection([])
    }

    func addWorkflow(from draft: MonitoredWorkflowDraft) throws {
        let workflow = try draft.validated(existingWorkflows: workflows)
        var nextWorkflows = workflows
        nextWorkflows.append(workflow)
        try persistWorkflows(nextWorkflows)
    }

    func updateWorkflow(id: UUID, from draft: MonitoredWorkflowDraft) throws {
        guard let index = workflows.firstIndex(where: { $0.id == id }) else {
            throw StatusStoreError.workflowNotFound
        }

        var nextWorkflows = workflows
        nextWorkflows[index] = try draft.validated(
            existingWorkflows: workflows,
            editingWorkflow: workflows[index]
        )
        try persistWorkflows(nextWorkflows)
    }

    func discoverWorkflows() {
        workflowDiscoveryTask?.cancel()
        isDiscoveringWorkflows = true

        workflowDiscoveryTask = Task { [weak self] in
            guard let self else {
                return
            }

            guard let session = await self.ensureSessionLoadedForUserTriggeredGitHubAction() else {
                self.discoveredWorkflowSuggestions = []
                self.workflowDiscoveryMessage = "Connect GitHub to discover workflows."
                self.workflowDiscoveryHelpTitle = nil
                self.workflowDiscoveryHelpURL = nil
                self.isDiscoveringWorkflows = false
                self.workflowDiscoveryTask = nil
                return
            }

            guard session.source == .oauthBrowser else {
                self.discoveredWorkflowSuggestions = []
                self.workflowDiscoveryMessage = "Workflow discovery is available after GitHub browser sign-in."
                self.workflowDiscoveryHelpTitle = nil
                self.workflowDiscoveryHelpURL = nil
                self.isDiscoveringWorkflows = false
                self.workflowDiscoveryTask = nil
                return
            }

            let repositories = self.selectedAccessibleRepositories
                .sorted { $0.fullName.localizedCaseInsensitiveCompare($1.fullName) == .orderedAscending }

            guard !repositories.isEmpty else {
                self.discoveredWorkflowSuggestions = []
                self.workflowDiscoveryMessage = nil
                self.workflowDiscoveryHelpTitle = nil
                self.workflowDiscoveryHelpURL = nil
                self.isDiscoveringWorkflows = false
                self.workflowDiscoveryTask = nil
                return
            }

            self.workflowDiscoveryMessage = nil
            self.workflowDiscoveryHelpTitle = nil
            self.workflowDiscoveryHelpURL = nil

            let scanResults = await self.scanWorkflows(
                in: repositories,
                accessToken: session.accessToken
            )

            guard !Task.isCancelled else {
                return
            }

            let failedScanCount = scanResults.filter(\.hasError).count
            let suggestions = self.buildDiscoveredWorkflowSuggestions(from: scanResults)
            self.discoveredWorkflowSuggestions = suggestions

            let blockedAccess = self.blockedAccessSupport(from: scanResults)
            if let blockedAccess {
                self.workflowDiscoveryMessage = blockedAccess.message
                self.workflowDiscoveryHelpTitle = blockedAccess.helpTitle
                self.workflowDiscoveryHelpURL = blockedAccess.helpURL
            } else if failedScanCount > 0 {
                self.workflowDiscoveryMessage = "Scanned \(repositories.count) repos, \(failedScanCount) failed."
                self.workflowDiscoveryHelpTitle = nil
                self.workflowDiscoveryHelpURL = nil
            } else {
                self.workflowDiscoveryMessage = nil
                self.workflowDiscoveryHelpTitle = nil
                self.workflowDiscoveryHelpURL = nil
            }

            self.isDiscoveringWorkflows = false
            self.workflowDiscoveryTask = nil
        }
    }

    func setDiscoveredWorkflowSelection(_ suggestionID: String, isSelected: Bool) {
        guard let index = discoveredWorkflowSuggestions.firstIndex(where: { $0.id == suggestionID }) else {
            return
        }

        guard discoveredWorkflowSuggestions[index].isSelectable else {
            return
        }

        discoveredWorkflowSuggestions[index].isSelected = isSelected
    }

    func toggleDiscoveredWorkflowSelection(_ suggestionID: String) {
        guard let suggestion = discoveredWorkflowSuggestions.first(where: { $0.id == suggestionID }) else {
            return
        }

        setDiscoveredWorkflowSelection(suggestionID, isSelected: !suggestion.isSelected)
    }

    func selectAllDiscoveredWorkflows() {
        guard !discoveredWorkflowSuggestions.isEmpty else {
            return
        }

        discoveredWorkflowSuggestions = discoveredWorkflowSuggestions.map { suggestion in
            var updatedSuggestion = suggestion
            if updatedSuggestion.isSelectable {
                updatedSuggestion.isSelected = true
            }
            return updatedSuggestion
        }
    }

    func clearDiscoveredWorkflowSelection() {
        guard !discoveredWorkflowSuggestions.isEmpty else {
            return
        }

        discoveredWorkflowSuggestions = discoveredWorkflowSuggestions.map { suggestion in
            var updatedSuggestion = suggestion
            if updatedSuggestion.isSelectable {
                updatedSuggestion.isSelected = false
            }
            return updatedSuggestion
        }
    }

    func addSelectedDiscoveredWorkflows() throws {
        let selectedSuggestions = discoveredWorkflowSuggestions
            .filter { $0.isSelectable && $0.isSelected }

        guard !selectedSuggestions.isEmpty else {
            return
        }

        var nextWorkflows = workflows

        for suggestion in selectedSuggestions {
            let workflow = suggestion.asMonitoredWorkflow()
            guard !nextWorkflows.contains(where: {
                $0.matchesMonitor(
                    owner: workflow.owner,
                    repo: workflow.repo,
                    branch: workflow.branch,
                    workflowID: workflow.workflowID,
                    workflowFile: workflow.workflowFile
                )
            }) else {
                continue
            }

            nextWorkflows.append(workflow)
        }

        try persistWorkflows(nextWorkflows)
        reconcileDiscoveredWorkflowSuggestions()
    }

    func showSettingsDirectly() {
        windowPresenter.showSettingsDirectly()
        Task { [weak self] in
            guard let self else {
                return
            }

            guard let session = await self.ensureSessionLoadedForUserTriggeredGitHubAction() else {
                return
            }

            if session.source == .oauthBrowser {
                self.reloadGitHubAccess()
            }
        }
    }

    func showSettings() {
        windowPresenter.showSettings()

        guard !shouldRouteSettingsToOnboarding else {
            return
        }

        Task { [weak self] in
            guard let self else {
                return
            }

            guard let session = await self.ensureSessionLoadedForUserTriggeredGitHubAction() else {
                return
            }

            if session.source == .oauthBrowser {
                self.reloadGitHubAccess()
            }
        }
    }

    func openWorkflowDiscoveryHelp() {
        guard let helpURL = workflowDiscoveryHelpURL else {
            return
        }

        windowPresenter.openExternalURL(helpURL)
    }

    func deleteWorkflow(id: UUID) throws {
        guard let index = workflows.firstIndex(where: { $0.id == id }) else {
            throw StatusStoreError.workflowNotFound
        }

        var nextWorkflows = workflows
        nextWorkflows.remove(at: index)
        try persistWorkflows(nextWorkflows)
    }

    func moveWorkflowUp(id: UUID) throws {
        guard let index = workflows.firstIndex(where: { $0.id == id }) else {
            throw StatusStoreError.workflowNotFound
        }

        guard index > 0 else {
            return
        }

        var nextWorkflows = workflows
        nextWorkflows.swapAt(index, index - 1)
        try persistWorkflows(nextWorkflows)
    }

    func moveWorkflowDown(id: UUID) throws {
        guard let index = workflows.firstIndex(where: { $0.id == id }) else {
            throw StatusStoreError.workflowNotFound
        }

        guard index < workflows.index(before: workflows.endIndex) else {
            return
        }

        var nextWorkflows = workflows
        nextWorkflows.swapAt(index, index + 1)
        try persistWorkflows(nextWorkflows)
    }

    private func scanWorkflows(
        in repositories: [GitHubAccessibleRepositorySummary],
        accessToken: String
    ) async -> [WorkflowRepositoryScanResult] {
        var scanResults: [WorkflowRepositoryScanResult] = []
        let client = self.client

        for repositoryBatch in repositories.chunked(into: 4) {
            let batchResults = await withTaskGroup(of: WorkflowRepositoryScanResult.self) { group in
                for repository in repositoryBatch {
                    group.addTask {
                        do {
                            let workflows = try await client.fetchWorkflows(
                                owner: repository.ownerLogin,
                                repo: repository.name,
                                accessToken: accessToken
                            )
                            return WorkflowRepositoryScanResult(
                                repository: repository,
                                workflows: workflows,
                                errorMessage: nil
                            )
                        } catch {
                            return WorkflowRepositoryScanResult(
                                repository: repository,
                                workflows: [],
                                errorMessage: error.localizedDescription
                            )
                        }
                    }
                }

                var results: [WorkflowRepositoryScanResult] = []
                for await result in group {
                    results.append(result)
                }
                return results
            }

            scanResults.append(contentsOf: batchResults)
        }

        return scanResults
    }

    private func buildDiscoveredWorkflowSuggestions(
        from scanResults: [WorkflowRepositoryScanResult]
    ) -> [DiscoveredWorkflowSuggestion] {
        var suggestionsByIdentity: [MonitorIdentity: DiscoveredWorkflowSuggestion] = [:]

        for scanResult in scanResults {
            let branch = (scanResult.repository.defaultBranch ?? "main").normalizedMonitorBranchValue

            for workflow in scanResult.workflows {
                let monitorIdentity = MonitorIdentity(
                    owner: scanResult.repository.ownerLogin,
                    repo: scanResult.repository.name,
                    branch: branch,
                    workflowID: workflow.id,
                    workflowFile: workflow.path
                )
                let suggestion = DiscoveredWorkflowSuggestion(
                    owner: scanResult.repository.ownerLogin,
                    repo: scanResult.repository.name,
                    repoFullName: scanResult.repository.fullName,
                    branch: branch,
                    workflowID: workflow.id,
                    workflowName: workflow.name,
                    workflowFile: workflow.path.trimmedWorkflowValue,
                    workflowState: workflow.state,
                    isSelected: !workflows.contains(where: {
                        $0.matchesMonitor(
                            owner: scanResult.repository.ownerLogin,
                            repo: scanResult.repository.name,
                            branch: branch,
                            workflowID: workflow.id,
                            workflowFile: workflow.path
                        )
                    }) &&
                        workflow.state.normalizedWorkflowValue == "active",
                    isAlreadyMonitored: workflows.contains(where: {
                        $0.matchesMonitor(
                            owner: scanResult.repository.ownerLogin,
                            repo: scanResult.repository.name,
                            branch: branch,
                            workflowID: workflow.id,
                            workflowFile: workflow.path
                        )
                    })
                )

                if let existingSuggestion = suggestionsByIdentity[monitorIdentity] {
                    let shouldReplaceExisting =
                        suggestion.workflowID != nil && existingSuggestion.workflowID == nil
                    if shouldReplaceExisting {
                        suggestionsByIdentity[monitorIdentity] = suggestion
                    }
                } else {
                    suggestionsByIdentity[monitorIdentity] = suggestion
                }
            }
        }

        return suggestionsByIdentity.values.sorted {
            if $0.repoFullName.localizedCaseInsensitiveCompare($1.repoFullName) != .orderedSame {
                return $0.repoFullName.localizedCaseInsensitiveCompare($1.repoFullName) == .orderedAscending
            }

            if $0.displayName.localizedCaseInsensitiveCompare($1.displayName) != .orderedSame {
                return $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
            }

            return $0.workflowFile.localizedCaseInsensitiveCompare($1.workflowFile) == .orderedAscending
        }
    }

    private func blockedAccessSupport(
        from scanResults: [WorkflowRepositoryScanResult]
    ) -> WorkflowDiscoveryBlockedAccessSupport? {
        guard let blockedResult = scanResults.first(where: { result in
            guard let errorMessage = result.errorMessage?.lowercased() else {
                return false
            }

            return errorMessage.contains("saml") ||
                errorMessage.contains("sso") ||
                errorMessage.contains("oauth app access restrictions") ||
                errorMessage.contains("third-party application access policy")
        }) else {
            return nil
        }

        let errorMessage = blockedResult.errorMessage?.lowercased() ?? ""
        if errorMessage.contains("saml") || errorMessage.contains("sso") {
            let helpURL = blockedResult.repository.ownerType == "Organization"
                ? URL(string: "https://github.com/orgs/\(blockedResult.repository.ownerLogin)/sso")
                : nil
            return WorkflowDiscoveryBlockedAccessSupport(
                message: "Connected to GitHub, but \(blockedResult.repository.fullName) needs an active SSO session before workflows can be loaded.",
                helpTitle: helpURL == nil ? nil : "Open Org SSO",
                helpURL: helpURL
            )
        }

        return WorkflowDiscoveryBlockedAccessSupport(
            message: "Connected to GitHub, but \(blockedResult.repository.fullName) is blocked by the organization's OAuth app approval policy. An organization owner may need to approve the app first.",
            helpTitle: nil,
            helpURL: nil
        )
    }

    private func reconcileDiscoveredWorkflowSuggestions() {
        guard !discoveredWorkflowSuggestions.isEmpty else {
            return
        }

        discoveredWorkflowSuggestions = discoveredWorkflowSuggestions.map { suggestion in
            var updatedSuggestion = suggestion
            let isAlreadyMonitored = workflows.contains {
                $0.matchesMonitor(
                    owner: suggestion.owner,
                    repo: suggestion.repo,
                    branch: suggestion.branch,
                    workflowID: suggestion.workflowID,
                    workflowFile: suggestion.workflowFile
                )
            }
            updatedSuggestion.isAlreadyMonitored = isAlreadyMonitored
            updatedSuggestion.isSelected = !isAlreadyMonitored && updatedSuggestion.isSelected
            return updatedSuggestion
        }
    }

    private func resetWorkflowDiscoveryState() {
        workflowDiscoveryTask?.cancel()
        workflowDiscoveryTask = nil
        isDiscoveringWorkflows = false
        discoveredWorkflowSuggestions = []
        workflowDiscoveryMessage = nil
        workflowDiscoveryHelpTitle = nil
        workflowDiscoveryHelpURL = nil
    }

    private func beginRefreshLoop() {
        refreshLoopTask?.cancel()
        let refreshInterval = workflowRefreshInterval
        refreshLoopTask = Task { [weak self] in
            while let self, !Task.isCancelled {
                try? await Task.sleep(for: .seconds(refreshInterval.seconds))
                guard !Task.isCancelled else {
                    break
                }

                self.refreshNow()
            }
        }
    }

    private func persistWorkflows(_ nextWorkflows: [MonitoredWorkflow]) throws {
        do {
            try workflowStore.saveWorkflows(nextWorkflows)
            workflowConfigurationMessage = nil
        } catch {
            workflowConfigurationMessage = error.localizedDescription
            throw error
        }

        workflowsVersion += 1
        replaceWorkflows(with: nextWorkflows)
        reconcileDiscoveredWorkflowSuggestions()

        if onboardingStep != nil,
           currentSession != nil,
           !nextWorkflows.isEmpty {
            onboardingStep = .finish
        } else if onboardingStep == .finish,
                  nextWorkflows.isEmpty {
            onboardingStep = .firstWorkflow
        }

        refreshNow()
    }

    private func replaceWorkflows(with nextWorkflows: [MonitoredWorkflow]) {
        let existingStates = Dictionary(uniqueKeysWithValues: states.map { ($0.id, $0) })

        workflows = nextWorkflows
        states = nextWorkflows.map { workflow in
            guard let existingState = existingStates[workflow.id],
                  existingState.workflow.monitorIdentity == workflow.monitorIdentity else {
                return DeployState.placeholder(for: workflow)
            }

            return existingState.updatingWorkflow(workflow)
        }
        combinedStatus = CombinedStatus.reduce(states)

        if nextWorkflows.isEmpty {
            bannerMessage = nil
        }
    }

    private func performRefresh(workflows workflowSnapshot: [MonitoredWorkflow], version: Int) async {
        guard !workflowSnapshot.isEmpty else {
            return
        }

        isRefreshing = true
        defer {
            isRefreshing = false
        }

        let currentToken = currentSession?.accessToken.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let repositoryAccessIsConfigured = supportsRepositorySelection && !accessibleRepositories.isEmpty
        var nextStates: [DeployState] = []
        var sawUnauthorized = false
        var sawRateLimit = false

        for workflow in workflowSnapshot {
            if repositoryAccessIsConfigured && !isWorkflowSelectedForMonitoring(workflow) {
                nextStates.append(
                    DeployState.unknown(
                        for: workflow,
                        message: "This repository is not selected in GitHub access settings."
                    )
                )
                continue
            }

            do {
                if let latestRun = try await fetchLatestRunWithRetry(
                    for: workflow,
                    accessToken: currentToken.isEmpty ? nil : currentToken
                ) {
                    nextStates.append(latestRun.deployState(for: workflow))
                } else {
                    nextStates.append(
                        DeployState.unknown(
                            for: workflow,
                            message: "No deploy runs found yet."
                        )
                    )
                }
            } catch let error as GitHubClientError {
                if case .unauthorized = error {
                    sawUnauthorized = true
                }

                if case .rateLimited = error {
                    sawRateLimit = true
                }

                nextStates.append(DeployState.unknown(for: workflow, message: error.localizedDescription))
            } catch {
                nextStates.append(DeployState.unknown(for: workflow, message: error.localizedDescription))
            }
        }

        guard version == workflowsVersion else {
            return
        }

        states = nextStates
        combinedStatus = CombinedStatus.reduce(nextStates)

        if sawUnauthorized {
            bannerMessage = "GitHub rejected the saved session. Connect GitHub again in Settings."
            promptForAuthFailureIfNeeded()
        } else if showsMissingCredentialBanner && sawRateLimit && currentToken.isEmpty {
            bannerMessage = "Connect GitHub to avoid anonymous rate limits."
        } else if showsMissingCredentialBanner && currentToken.isEmpty {
            bannerMessage = "Connect GitHub for private repositories and more reliable polling."
        } else {
            bannerMessage = nil
        }
    }

    private func fetchLatestRunWithRetry(
        for workflow: MonitoredWorkflow,
        accessToken: String?
    ) async throws -> WorkflowRun? {
        do {
            return try await client.fetchLatestRun(for: workflow, token: accessToken)
        } catch GitHubClientError.unauthorized {
            handleInvalidSession(errorMessage: GitHubClientError.unauthorized.localizedDescription)
            throw GitHubClientError.unauthorized
        }
    }

    private func normalizeRepositorySelection() throws {
        let availableRepositoryIDs = Set(accessibleRepositories.map(\.id))
        let existingSelectedRepositoryIDs = selectedRepositoryIDs.intersection(availableRepositoryIDs)
        let nextSelectedRepositoryIDs: Set<Int64>

        if existingSelectedRepositoryIDs.isEmpty && !accessibleRepositories.isEmpty {
            nextSelectedRepositoryIDs = availableRepositoryIDs
        } else {
            nextSelectedRepositoryIDs = existingSelectedRepositoryIDs
        }

        guard nextSelectedRepositoryIDs != selectedRepositoryIDs else {
            return
        }

        try updateRepositorySelection(repositoryIDs: nextSelectedRepositoryIDs)
    }

    private func persistRepositorySelection(_ repositoryIDs: Set<Int64>) {
        do {
            let previousRepositoryIDs = selectedRepositoryIDs
            try updateRepositorySelection(repositoryIDs: repositoryIDs)
            if previousRepositoryIDs != repositoryIDs {
                resetWorkflowDiscoveryState()
            }
            refreshNow()
        } catch {
            credentialMessage = error.localizedDescription
        }
    }

    private func updateRepositorySelection(
        repositoryIDs: Set<Int64>
    ) throws {
        let updatedSession = try authManager.updateSelections(repositoryIDs: Array(repositoryIDs).sorted())
        synchronizeSession(updatedSession, successMessage: nil)
    }

    private func isWorkflowSelectedForMonitoring(_ workflow: MonitoredWorkflow) -> Bool {
        guard !selectedRepositoryIDs.isEmpty else {
            return true
        }

        let workflowKey = "\(workflow.owner)/\(workflow.repo)".lowercased()
        return accessibleRepositories.contains { repository in
            selectedRepositoryIDs.contains(repository.id) &&
            repository.fullName.lowercased() == workflowKey
        }
    }

    private func synchronizeSession(
        _ session: GitHubOAuthSession?,
        successMessage: String?
    ) {
        let nextSessionIdentity = session.map { EffectiveGitHubSessionIdentity(session: $0) }
        if sessionIdentity != nextSessionIdentity {
            resetWorkflowDiscoveryState()
        }

        currentSession = session
        sessionIdentity = nextSessionIdentity
        authState = Self.authState(for: session)
        if let successMessage {
            credentialMessage = successMessage
        }

        if !supportsRepositorySelection {
            accessibleRepositories = []
            resetWorkflowDiscoveryState()
        }
    }

    @discardableResult
    private func ensureSessionLoadedForUserTriggeredGitHubAction() async -> GitHubOAuthSession? {
        if let currentSession {
            return currentSession
        }

        do {
            let session = try await authManager.ensureSessionLoaded()
            synchronizeSession(session, successMessage: nil)
            return session
        } catch CredentialStoreError.migrationRequired {
            currentSession = nil
            sessionIdentity = nil
            authState = .signedOut
            credentialMessage = CredentialStoreError.migrationRequired.localizedDescription
            accessibleRepositories = []
            resetWorkflowDiscoveryState()
            return nil
        } catch {
            currentSession = nil
            sessionIdentity = nil
            authState = .authError(error.localizedDescription)
            credentialMessage = error.localizedDescription
            accessibleRepositories = []
            resetWorkflowDiscoveryState()
            return nil
        }
    }

    private func clearSavedSession(message: String) throws {
        try authManager.disconnect()
        currentSession = nil
        sessionIdentity = nil
        authState = .signedOut
        credentialMessage = message
        accessibleRepositories = []
        resetWorkflowDiscoveryState()
    }

    private func restoreAuthStateFromCurrentSession(orError errorMessage: String? = nil) {
        if let currentSession {
            authState = Self.authState(for: currentSession)
        } else if let errorMessage {
            authState = .authError(errorMessage)
        } else {
            authState = .signedOut
        }
    }

    private func cancelGitHubSignInIfNeeded() {
        guard signInTask != nil else {
            return
        }

        authManager.cancelAuthorization()
        signInTask?.cancel()
        signInTask = nil
    }

    private func cancelWorkInFlightForReset() {
        authManager.cancelAuthorization()
        signInTask?.cancel()
        signInTask = nil
        refreshTask?.cancel()
        refreshTask = nil
        accessDirectoryTask?.cancel()
        accessDirectoryTask = nil
        workflowDiscoveryTask?.cancel()
        workflowDiscoveryTask = nil
        refreshLoopTask?.cancel()
        refreshLoopTask = nil
        pendingRefresh = false
        isRefreshing = false
        isLoadingGitHubAccess = false
        isDiscoveringWorkflows = false
    }

    private func applySuccessfulResetState() {
        workflowsVersion += 1
        replaceWorkflows(with: [])
        resetWorkflowDiscoveryState()
        currentSession = nil
        sessionIdentity = nil
        authState = .signedOut
        credentialMessage = nil
        resetMessage = nil
        bannerMessage = nil
        workflowConfigurationMessage = nil
        accessibleRepositories = []
        onboardingStep = nil
        didCompleteOnboarding = false
        workflowRefreshInterval = .default
        hasPromptedForAuthFailure = false
        if didStart {
            beginRefreshLoop()
        }
    }

    private func reconcileStateAfterFailedReset(error: Error) {
        let reloadedWorkflows: [MonitoredWorkflow]
        do {
            reloadedWorkflows = try workflowStore.loadWorkflows()
            workflowConfigurationMessage = nil
        } catch {
            reloadedWorkflows = []
            workflowConfigurationMessage = error.localizedDescription
        }

        workflowsVersion += 1
        replaceWorkflows(with: reloadedWorkflows)
        didCompleteOnboarding = appSetupStore.loadDidCompleteOnboarding()
        workflowRefreshInterval = appSetupStore.loadWorkflowRefreshInterval()
        accessibleRepositories = []
        resetWorkflowDiscoveryState()
        isLoadingGitHubAccess = false
        hasPromptedForAuthFailure = false
        onboardingStep = nil
        resetMessage = "Reset App failed: \(error.localizedDescription)"

        restorePersistedSession()

        if didStart {
            beginRefreshLoop()
        }
    }

    private func restorePersistedSession() {
        do {
            let session = try authManager.loadPersistedSession()
            synchronizeSession(session, successMessage: nil)
        } catch CredentialStoreError.migrationRequired {
            currentSession = nil
            sessionIdentity = nil
            authState = .signedOut
            credentialMessage = CredentialStoreError.migrationRequired.localizedDescription
            accessibleRepositories = []
            resetWorkflowDiscoveryState()
        } catch {
            currentSession = nil
            sessionIdentity = nil
            authState = .authError(error.localizedDescription)
            credentialMessage = error.localizedDescription
            accessibleRepositories = []
            resetWorkflowDiscoveryState()
        }
    }

    private func showOnboardingIfNeeded() {
        let step = startupOnboardingStep()
        onboardingStep = step
        windowPresenter.showOnboarding(startingAt: step)
    }

    private func promptForAuthFailureIfNeeded() {
        guard !hasPromptedForAuthFailure else {
            return
        }

        hasPromptedForAuthFailure = true
        windowPresenter.showSettings()
    }

    private func advanceOnboardingAfterSuccessfulAuth() {
        guard onboardingStep != nil else {
            return
        }

        onboardingStep = workflows.isEmpty ? .firstWorkflow : .finish
    }

    private func suggestedOnboardingStep() -> OnboardingStep {
        if currentSession == nil && workflows.isEmpty {
            return .welcome
        }

        if currentSession == nil {
            return .githubSignIn
        }

        if workflows.isEmpty {
            return .firstWorkflow
        }

        return .finish
    }

    private func startupOnboardingStep() -> OnboardingStep {
        if !didCompleteOnboarding && currentSession == nil {
            return .githubSignIn
        }

        return suggestedOnboardingStep()
    }

}

private extension StatusStore {
    func shouldClearSession(for error: Error) -> Bool {
        guard let error = error as? GitHubClientError else {
            return false
        }

        switch error {
        case .unauthorized:
            return true
        case .unexpectedStatus(_, let message):
            let normalizedMessage = message?.lowercased() ?? ""
            return normalizedMessage.contains("bad credentials") ||
                normalizedMessage.contains("expired") ||
                normalizedMessage.contains("revoked") ||
                normalizedMessage.contains("invalid token")
        case .invalidResponse, .rateLimited, .decodingFailed, .network:
            return false
        }
    }

    func handleInvalidSession(errorMessage: String) {
        do {
            try authManager.disconnect()
        } catch {
            credentialMessage = error.localizedDescription
        }

        currentSession = nil
        sessionIdentity = nil
        authState = .authError(errorMessage)
        accessibleRepositories = []
        resetWorkflowDiscoveryState()
        bannerMessage = errorMessage
        hasPromptedForAuthFailure = false
        promptForAuthFailureIfNeeded()
    }
}

private extension StatusStore {
    static func authState(for session: GitHubOAuthSession?) -> GitHubAuthState {
        guard let session else {
            return .signedOut
        }

        switch session.source {
        case .oauthBrowser:
            return .signedInOAuthApp(session.summary)
        case .personalAccessToken:
            return .signedInPersonalAccessToken(session.summary)
        }
    }
}

private struct WorkflowRepositoryScanResult: Sendable {
    let repository: GitHubAccessibleRepositorySummary
    let workflows: [GitHubWorkflowSummary]
    let errorMessage: String?

    var hasError: Bool {
        errorMessage != nil
    }
}

private struct WorkflowDiscoveryBlockedAccessSupport {
    let message: String
    let helpTitle: String?
    let helpURL: URL?
}

private struct EffectiveGitHubSessionIdentity: Equatable {
    let source: GitHubSessionSource
    let userID: Int64?
    let login: String?

    init(session: GitHubOAuthSession) {
        source = session.source
        userID = session.userID
        login = session.login?.trimmedWorkflowValue
    }
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else {
            return [self]
        }

        var result: [[Element]] = []
        var index = startIndex
        while index < endIndex {
            let nextIndex = Swift.min(index + size, endIndex)
            result.append(Array(self[index..<nextIndex]))
            index = nextIndex
        }
        return result
    }
}
