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

    var errorDescription: String? {
        switch self {
        case .workflowNotFound:
            return "That workflow could not be found."
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
    @Published private(set) var token: String
    @Published private(set) var credentialMessage: String?
    @Published private(set) var workflowConfigurationMessage: String?

    private let workflowStore: any MonitoredWorkflowStore
    private let client: any WorkflowRunFetching
    private let credentialStore: any CredentialStore
    private let settingsPresenter: any SettingsPresenting
    private let promptsForMissingToken: Bool
    private let showsMissingTokenBanner: Bool
    private var refreshLoopTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private var didStart = false
    private var hasPromptedForInitialToken = false
    private var hasPromptedForAuthFailure = false
    private var pendingRefresh = false
    private var workflowsVersion = 0

    init(
        workflows initialWorkflows: [MonitoredWorkflow]? = nil,
        workflowStore: any MonitoredWorkflowStore = FileBackedMonitoredWorkflowStore(),
        client: any WorkflowRunFetching = GitHubClient(),
        credentialStore: any CredentialStore = KeychainCredentialStore(),
        settingsPresenter: any SettingsPresenting = NoOpSettingsPresenter(),
        promptsForMissingToken: Bool = true,
        showsMissingTokenBanner: Bool = true
    ) {
        self.workflowStore = workflowStore
        self.client = client
        self.credentialStore = credentialStore
        self.settingsPresenter = settingsPresenter
        self.promptsForMissingToken = promptsForMissingToken
        self.showsMissingTokenBanner = showsMissingTokenBanner

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

        do {
            token = try credentialStore.loadToken() ?? ""
        } catch {
            token = ""
            credentialMessage = error.localizedDescription
        }
    }

    var tokenIsMissing: Bool {
        token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func start() {
        guard !didStart else {
            return
        }

        didStart = true
        refreshNow()
        beginRefreshLoop()

        if promptsForMissingToken && tokenIsMissing && !workflows.isEmpty {
            promptForTokenIfNeeded()
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

    func saveToken(_ token: String) {
        let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            if trimmedToken.isEmpty {
                try credentialStore.removeToken()
            } else {
                try credentialStore.saveToken(trimmedToken)
            }

            self.token = trimmedToken
            credentialMessage = trimmedToken.isEmpty ? "Stored token removed." : "GitHub token saved to Keychain."
            hasPromptedForAuthFailure = false
            refreshNow()
        } catch {
            credentialMessage = error.localizedDescription
        }
    }

    func clearToken() {
        saveToken("")
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

        let currentToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
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
            bannerMessage = "GitHub rejected the stored token. Update it in Settings."
            promptForAuthFailureIfNeeded()
        } else if showsMissingTokenBanner && sawRateLimit && currentToken.isEmpty {
            bannerMessage = "Add a GitHub token to avoid anonymous rate limits."
        } else if showsMissingTokenBanner && currentToken.isEmpty {
            bannerMessage = "Add a GitHub token for private repos and more reliable polling."
        } else {
            bannerMessage = nil
        }
    }

    private func promptForTokenIfNeeded() {
        guard !hasPromptedForInitialToken else {
            return
        }

        hasPromptedForInitialToken = true
        openSettingsWindow()
    }

    private func promptForAuthFailureIfNeeded() {
        guard !hasPromptedForAuthFailure else {
            return
        }

        hasPromptedForAuthFailure = true
        openSettingsWindow()
    }

    private func openSettingsWindow() {
        settingsPresenter.showSettings()
    }
}
