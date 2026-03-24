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
    @Published private(set) var isRefreshing = false
    @Published private(set) var bannerMessage: String?
    @Published private(set) var authState: GitHubAuthState
    @Published private(set) var credentialMessage: String?
    @Published private(set) var workflowConfigurationMessage: String?
    @Published private(set) var gitHubSignInConfigurationMessage: String?
    @Published private(set) var onboardingStep: OnboardingStep?
    @Published private(set) var installations: [GitHubInstallationSummary]
    @Published private(set) var accessibleRepositories: [GitHubAccessibleRepositorySummary]
    @Published private(set) var isLoadingGitHubAccess = false
    @Published private(set) var discoveredWorkflowSuggestions: [DiscoveredWorkflowSuggestion]
    @Published private(set) var isDiscoveringWorkflows = false
    @Published private(set) var workflowDiscoveryMessage: String?

    private let workflowStore: any MonitoredWorkflowStore
    private let client: any GitHubDataFetching
    private let appSetupStore: any AppSetupStore
    private let windowPresenter: any SettingsPresenting
    private let authManager: any GitHubAuthManaging
    private let promptsForIncompleteSetup: Bool
    private let showsMissingCredentialBanner: Bool
    private let allowsPersonalAccessTokenFallback: Bool

    private var currentSession: GitHubAppSession?
    private var didCompleteOnboarding: Bool
    private var refreshLoopTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private var signInTask: Task<Void, Never>?
    private var accessDirectoryTask: Task<Void, Never>?
    private var workflowDiscoveryTask: Task<Void, Never>?
    private var didStart = false
    private var hasPromptedForAuthFailure = false
    private var pendingRefresh = false
    private var workflowsVersion = 0
    private var sessionIdentity: EffectiveGitHubSessionIdentity?

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
        installations = []
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
        gitHubSignInConfigurationMessage = authManager.configuration == nil
            ? GitHubAppConfiguration.missingConfigurationMessage
            : nil

        do {
            let session = try authManager.loadPersistedSession()
            synchronizeSession(session, successMessage: nil)
        } catch {
            currentSession = nil
            authState = .authError(error.localizedDescription)
            credentialMessage = error.localizedDescription
        }

        if !didCompleteOnboarding,
           currentSession != nil,
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

    var selectedInstallationIDs: Set<Int64> {
        Set(currentSession?.selectedInstallationIDs ?? [])
    }

    var supportsRepositorySelection: Bool {
        currentSession?.source == .githubAppBrowser
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

    var showsPersonalAccessTokenFallback: Bool {
        allowsPersonalAccessTokenFallback
    }

    func start() {
        guard !didStart else {
            return
        }

        didStart = true
        refreshNow()
        beginRefreshLoop()

        if supportsRepositorySelection {
            reloadGitHubAccess()
        }

        if promptsForIncompleteSetup && !didCompleteOnboarding {
            showOnboardingIfNeeded()
        }
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
            credentialMessage = gitHubSignInConfigurationMessage ?? GitHubAppConfiguration.missingConfigurationMessage
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
                        ?? "GitHub session saved to Keychain."
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
                let session = GitHubAppSession(
                    accessToken: trimmedToken,
                    source: .personalAccessToken
                )
                try authManager.saveManualSession(session)
                synchronizeSession(session, successMessage: "Personal access token saved to Keychain.")
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
            didCompleteOnboarding = false
            appSetupStore.saveDidCompleteOnboarding(false)
            if onboardingStep != nil {
                onboardingStep = workflows.isEmpty ? .welcome : .githubSignIn
            }
            refreshNow()
        } catch {
            credentialMessage = error.localizedDescription
        }
    }

    func reloadGitHubAccess() {
        guard supportsRepositorySelection else {
            installations = []
            accessibleRepositories = []
            resetWorkflowDiscoveryState()
            return
        }

        accessDirectoryTask?.cancel()
        accessDirectoryTask = Task { [weak self] in
            guard let self else {
                return
            }

            self.isLoadingGitHubAccess = true
            defer {
                self.isLoadingGitHubAccess = false
            }

            do {
                guard let session = try await self.authManager.validSession() else {
                    self.installations = []
                    self.accessibleRepositories = []
                    return
                }

                self.synchronizeSession(session, successMessage: nil)

                let installations = try await self.client.fetchInstallations(accessToken: session.accessToken)
                    .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }

                var repositories: [GitHubAccessibleRepositorySummary] = []
                for installation in installations {
                    let installationRepositories = try await self.client.fetchRepositories(
                        for: installation.id,
                        accessToken: session.accessToken
                    )
                    repositories.append(contentsOf: installationRepositories)
                }

                repositories.sort { $0.fullName.localizedCaseInsensitiveCompare($1.fullName) == .orderedAscending }

                self.installations = installations
                self.accessibleRepositories = repositories
                try self.normalizeRepositorySelection()
                if self.onboardingStep == .firstWorkflow {
                    self.discoverWorkflows()
                }
            } catch {
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

        guard supportsRepositorySelection else {
            discoveredWorkflowSuggestions = []
            workflowDiscoveryMessage = "Workflow discovery is available after GitHub browser sign-in."
            isDiscoveringWorkflows = false
            return
        }

        guard let session = currentSession else {
            discoveredWorkflowSuggestions = []
            workflowDiscoveryMessage = "Connect GitHub to discover workflows."
            isDiscoveringWorkflows = false
            return
        }

        let repositories = selectedAccessibleRepositories
            .sorted { $0.fullName.localizedCaseInsensitiveCompare($1.fullName) == .orderedAscending }

        guard !repositories.isEmpty else {
            discoveredWorkflowSuggestions = []
            workflowDiscoveryMessage = nil
            isDiscoveringWorkflows = false
            return
        }

        workflowDiscoveryMessage = nil
        isDiscoveringWorkflows = true

        workflowDiscoveryTask = Task { [weak self] in
            guard let self else {
                return
            }

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

            if failedScanCount > 0 {
                self.workflowDiscoveryMessage = "Scanned \(repositories.count) repos, \(failedScanCount) failed."
            } else {
                self.workflowDiscoveryMessage = nil
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
    }

    private func beginRefreshLoop() {
        refreshLoopTask?.cancel()
        refreshLoopTask = Task { [weak self] in
            while let self, !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
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

        do {
            if let session = try await authManager.validSession() {
                synchronizeSession(session, successMessage: nil)
            }
        } catch {
            credentialMessage = error.localizedDescription
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
            guard currentSession?.source == .githubAppBrowser,
                  let refreshedSession = try await authManager.forceRefreshSession() else {
                throw GitHubClientError.unauthorized
            }

            synchronizeSession(refreshedSession, successMessage: nil)
            return try await client.fetchLatestRun(
                for: workflow,
                token: refreshedSession.accessToken
            )
        }
    }

    private func normalizeRepositorySelection() throws {
        let availableRepositoryIDs = Set(accessibleRepositories.map(\.id))
        let availableInstallationIDs = Set(accessibleRepositories.map(\.installationID))
        let existingSelectedRepositoryIDs = selectedRepositoryIDs.intersection(availableRepositoryIDs)
        let nextSelectedRepositoryIDs: Set<Int64>

        if existingSelectedRepositoryIDs.isEmpty && !accessibleRepositories.isEmpty {
            nextSelectedRepositoryIDs = availableRepositoryIDs
        } else {
            nextSelectedRepositoryIDs = existingSelectedRepositoryIDs
        }

        let nextSelectedInstallationIDs = Set(
            accessibleRepositories
                .filter { nextSelectedRepositoryIDs.contains($0.id) }
                .map(\.installationID)
        ).intersection(availableInstallationIDs)

        guard nextSelectedRepositoryIDs != selectedRepositoryIDs ||
              nextSelectedInstallationIDs != selectedInstallationIDs else {
            return
        }

        try updateRepositorySelection(
            installationIDs: nextSelectedInstallationIDs,
            repositoryIDs: nextSelectedRepositoryIDs
        )
    }

    private func persistRepositorySelection(_ repositoryIDs: Set<Int64>) {
        let installationIDs = Set(
            accessibleRepositories
                .filter { repositoryIDs.contains($0.id) }
                .map(\.installationID)
        )

        do {
            let previousRepositoryIDs = selectedRepositoryIDs
            try updateRepositorySelection(
                installationIDs: installationIDs,
                repositoryIDs: repositoryIDs
            )
            if previousRepositoryIDs != repositoryIDs {
                resetWorkflowDiscoveryState()
            }
            refreshNow()
        } catch {
            credentialMessage = error.localizedDescription
        }
    }

    private func updateRepositorySelection(
        installationIDs: Set<Int64>,
        repositoryIDs: Set<Int64>
    ) throws {
        let updatedSession = try authManager.updateSelections(
            installationIDs: Array(installationIDs).sorted(),
            repositoryIDs: Array(repositoryIDs).sorted()
        )
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
        _ session: GitHubAppSession?,
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
            installations = []
            accessibleRepositories = []
            resetWorkflowDiscoveryState()
        }
    }

    private func clearSavedSession(message: String) throws {
        try authManager.disconnect()
        currentSession = nil
        sessionIdentity = nil
        authState = .signedOut
        credentialMessage = message
        installations = []
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

    private func showOnboardingIfNeeded() {
        let step = suggestedOnboardingStep()
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

    private static func authState(for session: GitHubAppSession?) -> GitHubAuthState {
        guard let session else {
            return .signedOut
        }

        switch session.source {
        case .githubAppBrowser:
            return .signedInGitHubApp(session.summary)
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

private struct EffectiveGitHubSessionIdentity: Equatable {
    let source: GitHubSessionSource
    let userID: Int64?
    let login: String?

    init(session: GitHubAppSession) {
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
