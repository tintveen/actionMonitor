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

    private let workflowStore: any MonitoredWorkflowStore
    private let client: any WorkflowRunFetching
    private let credentialStore: any CredentialStore
    private let appSetupStore: any AppSetupStore
    private let windowPresenter: any SettingsPresenting
    private let gitHubAuthorizer: any GitHubBrowserOAuthAuthorizing
    private let oauthConfiguration: GitHubOAuthConfiguration?
    private let promptsForIncompleteSetup: Bool
    private let showsMissingCredentialBanner: Bool

    private var currentCredential: GitHubCredential?
    private var didCompleteOnboarding: Bool
    private var refreshLoopTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private var signInTask: Task<Void, Never>?
    private var didStart = false
    private var hasPromptedForAuthFailure = false
    private var pendingRefresh = false
    private var workflowsVersion = 0

    init(
        workflows initialWorkflows: [MonitoredWorkflow]? = nil,
        workflowStore: any MonitoredWorkflowStore = FileBackedMonitoredWorkflowStore(),
        client: any WorkflowRunFetching = GitHubClient(),
        credentialStore: any CredentialStore = KeychainCredentialStore(),
        appSetupStore: any AppSetupStore = UserDefaultsAppSetupStore(),
        settingsPresenter: any SettingsPresenting = NoOpSettingsPresenter(),
        gitHubAuthorizer: any GitHubBrowserOAuthAuthorizing = GitHubBrowserOAuthAuthorizer(),
        oauthConfiguration: GitHubOAuthConfiguration? = GitHubOAuthConfiguration.load(),
        promptsForIncompleteSetup: Bool = true,
        showsMissingCredentialBanner: Bool = true
    ) {
        self.workflowStore = workflowStore
        self.client = client
        self.credentialStore = credentialStore
        self.appSetupStore = appSetupStore
        self.windowPresenter = settingsPresenter
        self.gitHubAuthorizer = gitHubAuthorizer
        self.oauthConfiguration = oauthConfiguration
        self.promptsForIncompleteSetup = promptsForIncompleteSetup
        self.showsMissingCredentialBanner = showsMissingCredentialBanner

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

        currentCredential = nil
        authState = .signedOut
        onboardingStep = nil
        didCompleteOnboarding = appSetupStore.loadDidCompleteOnboarding()
        gitHubSignInConfigurationMessage = oauthConfiguration == nil
            ? GitHubOAuthConfiguration.missingConfigurationMessage
            : nil

        do {
            let credential = try credentialStore.loadCredential()
            currentCredential = credential
            authState = Self.authState(for: credential)
        } catch {
            currentCredential = nil
            authState = .authError(error.localizedDescription)
            credentialMessage = error.localizedDescription
        }

        if !didCompleteOnboarding,
           currentCredential != nil,
           !loadedWorkflows.isEmpty {
            didCompleteOnboarding = true
            appSetupStore.saveDidCompleteOnboarding(true)
        }
    }

    var gitHubSignInIsAvailable: Bool {
        oauthConfiguration != nil
    }

    var isGitHubSignInBusy: Bool {
        signInTask != nil
    }

    var hasStoredCredential: Bool {
        currentCredential != nil
    }

    var hasStoredPersonalAccessToken: Bool {
        currentCredential?.source == .personalAccessToken
    }

    var shouldRouteSettingsToOnboarding: Bool {
        !didCompleteOnboarding
    }

    var canFinishOnboarding: Bool {
        currentCredential != nil && !workflows.isEmpty
    }

    var onboardingSummaryText: String {
        let loginText = currentCredential?.login.map { "@\($0)" } ?? "your GitHub account"
        if workflows.isEmpty {
            return "Signed in as \(loginText). Add your first workflow to finish setup."
        }

        return "Signed in as \(loginText) and watching \(workflows.count) workflow\(workflows.count == 1 ? "" : "s")."
    }

    func start() {
        guard !didStart else {
            return
        }

        didStart = true
        refreshNow()
        beginRefreshLoop()

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

        guard let oauthConfiguration else {
            credentialMessage = gitHubSignInConfigurationMessage ?? GitHubOAuthConfiguration.missingConfigurationMessage
            return
        }

        credentialMessage = nil

        signInTask = Task { [weak self] in
            guard let self else {
                return
            }

            do {
                let context = try await self.gitHubAuthorizer.prepareAuthorization(using: oauthConfiguration)
                self.authState = .signingInBrowser(context)
                self.windowPresenter.openExternalURL(context.authorizationURL)

                let credential = try await self.gitHubAuthorizer.waitForAuthorization(
                    using: context,
                    configuration: oauthConfiguration
                )

                try self.persistCredential(
                    credential,
                    successMessage: credential.login.map { "Signed in to GitHub as @\($0)." }
                        ?? "GitHub sign-in saved to Keychain."
                )
                self.hasPromptedForAuthFailure = false
                self.advanceOnboardingAfterSuccessfulAuth()
                self.refreshNow()
            } catch let error as GitHubBrowserOAuthError where error == .callbackCancelled {
                self.restoreAuthStateFromCurrentCredential()
            } catch {
                self.restoreAuthStateFromCurrentCredential(orError: error.localizedDescription)
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

        gitHubAuthorizer.cancelAuthorization()
        signInTask?.cancel()
        credentialMessage = "GitHub sign-in cancelled."
    }

    func savePersonalAccessToken(_ token: String) {
        let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            cancelGitHubSignInIfNeeded()

            if trimmedToken.isEmpty {
                try clearSavedCredential(message: "Saved GitHub credential removed.")
            } else {
                let credential = GitHubCredential(
                    accessToken: trimmedToken,
                    source: .personalAccessToken,
                    login: nil,
                    grantedScopes: []
                )
                try persistCredential(
                    credential,
                    successMessage: "Personal access token saved to Keychain."
                )
                advanceOnboardingAfterSuccessfulAuth()
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
            try clearSavedCredential(message: "Saved GitHub credential removed.")
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
           currentCredential != nil,
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

        let currentToken = currentCredential?.accessToken
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        var nextStates: [DeployState] = []
        var sawUnauthorized = false
        var sawRateLimit = false

        for workflow in workflowSnapshot {
            do {
                if let latestRun = try await client.fetchLatestRun(
                    for: workflow,
                    token: currentToken.isEmpty ? nil : currentToken
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
            bannerMessage = "GitHub rejected the saved credential. Sign in with GitHub or save a token in Settings."
            promptForAuthFailureIfNeeded()
        } else if showsMissingCredentialBanner && sawRateLimit && currentToken.isEmpty {
            bannerMessage = "Sign in with GitHub or save a token to avoid anonymous rate limits."
        } else if showsMissingCredentialBanner && currentToken.isEmpty {
            bannerMessage = "Sign in with GitHub or save a token for private repos and more reliable polling."
        } else {
            bannerMessage = nil
        }
    }

    private func persistCredential(
        _ credential: GitHubCredential,
        successMessage: String
    ) throws {
        try credentialStore.saveCredential(credential)
        currentCredential = credential
        authState = Self.authState(for: credential)
        credentialMessage = successMessage
    }

    private func clearSavedCredential(message: String) throws {
        try credentialStore.removeCredential()
        currentCredential = nil
        authState = .signedOut
        credentialMessage = message
    }

    private func restoreAuthStateFromCurrentCredential(orError errorMessage: String? = nil) {
        if let currentCredential {
            authState = Self.authState(for: currentCredential)
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

        gitHubAuthorizer.cancelAuthorization()
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
        if currentCredential == nil && workflows.isEmpty {
            return .welcome
        }

        if currentCredential == nil {
            return .githubSignIn
        }

        if workflows.isEmpty {
            return .firstWorkflow
        }

        return .finish
    }

    private static func authState(for credential: GitHubCredential?) -> GitHubAuthState {
        guard let credential else {
            return .signedOut
        }

        switch credential.source {
        case .oauthBrowser:
            return .signedInOAuth(credential.summary)
        case .personalAccessToken:
            return .signedInPersonalAccessToken(credential.summary)
        }
    }
}
