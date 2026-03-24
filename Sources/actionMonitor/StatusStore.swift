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
    private var didStart = false
    private var hasPromptedForAuthFailure = false
    private var pendingRefresh = false
    private var workflowsVersion = 0

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
            editingID: id
        )
        try persistWorkflows(nextWorkflows)
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
                  existingState.workflow.owner == workflow.owner,
                  existingState.workflow.repo == workflow.repo,
                  existingState.workflow.branch == workflow.branch,
                  existingState.workflow.workflowFile == workflow.workflowFile else {
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
            try updateRepositorySelection(
                installationIDs: installationIDs,
                repositoryIDs: repositoryIDs
            )
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
        currentSession = session
        authState = Self.authState(for: session)
        if let successMessage {
            credentialMessage = successMessage
        }

        if !supportsRepositorySelection {
            installations = []
            accessibleRepositories = []
        }
    }

    private func clearSavedSession(message: String) throws {
        try authManager.disconnect()
        currentSession = nil
        authState = .signedOut
        credentialMessage = message
        installations = []
        accessibleRepositories = []
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
