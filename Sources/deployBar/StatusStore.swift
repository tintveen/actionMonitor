import Foundation

@MainActor
final class StatusStore: ObservableObject {
    @Published private(set) var states: [DeployState]
    @Published private(set) var combinedStatus: DeployStatus
    @Published private(set) var isRefreshing = false
    @Published private(set) var bannerMessage: String?
    @Published private(set) var token: String
    @Published private(set) var credentialMessage: String?
    @Published private(set) var settingsPresentationRequestCount = 0

    private let sites: [SiteConfig]
    private let client: GitHubClient
    private let credentialStore: any CredentialStore
    private var refreshLoopTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private var didStart = false
    private var hasPromptedForInitialToken = false
    private var hasPromptedForAuthFailure = false

    init(
        sites: [SiteConfig] = SiteConfig.monitoredSites,
        client: GitHubClient = GitHubClient(),
        credentialStore: any CredentialStore = KeychainCredentialStore()
    ) {
        let initialStates = sites.map(DeployState.placeholder(for:))
        self.sites = sites
        self.client = client
        self.credentialStore = credentialStore
        self.states = initialStates
        self.combinedStatus = CombinedStatus.reduce(initialStates)

        do {
            self.token = try credentialStore.loadToken() ?? ""
        } catch {
            self.token = ""
            self.credentialMessage = error.localizedDescription
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

        if tokenIsMissing {
            promptForTokenIfNeeded()
        }
    }

    func refreshNow() {
        guard refreshTask == nil else {
            return
        }

        refreshTask = Task { [weak self] in
            guard let self else {
                return
            }

            await self.performRefresh()
            self.refreshTask = nil
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

    private func beginRefreshLoop() {
        refreshLoopTask?.cancel()
        refreshLoopTask = Task { [weak self] in
            while let self, !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                guard !Task.isCancelled else {
                    break
                }

                await self.performRefresh()
            }
        }
    }

    private func performRefresh() async {
        isRefreshing = true
        defer {
            isRefreshing = false
        }

        let currentToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        var nextStates: [DeployState] = []
        var sawUnauthorized = false
        var sawRateLimit = false

        for site in sites {
            do {
                if let latestRun = try await client.fetchLatestRun(
                    for: site,
                    token: currentToken.isEmpty ? nil : currentToken
                ) {
                    nextStates.append(latestRun.deployState(for: site))
                } else {
                    nextStates.append(DeployState.unknown(for: site, message: "No deploy runs found yet."))
                }
            } catch let error as GitHubClientError {
                if case .unauthorized = error {
                    sawUnauthorized = true
                }

                if case .rateLimited = error {
                    sawRateLimit = true
                }

                nextStates.append(DeployState.unknown(for: site, message: error.localizedDescription))
            } catch {
                nextStates.append(DeployState.unknown(for: site, message: error.localizedDescription))
            }
        }

        states = nextStates
        combinedStatus = CombinedStatus.reduce(nextStates)

        if sawUnauthorized {
            bannerMessage = "GitHub rejected the stored token. Update it in Settings."
            promptForAuthFailureIfNeeded()
        } else if sawRateLimit && currentToken.isEmpty {
            bannerMessage = "Add a GitHub token to avoid anonymous rate limits."
        } else if currentToken.isEmpty {
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
        settingsPresentationRequestCount += 1
    }
}
