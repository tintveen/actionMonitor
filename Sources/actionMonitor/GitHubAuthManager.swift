import Foundation

protocol GitHubAuthManaging: Sendable {
    var configuration: GitHubAppConfiguration? { get }

    func loadPersistedSession() throws -> GitHubAppSession?
    func currentSession() -> GitHubAppSession?
    func prepareAuthorization() async throws -> GitHubBrowserAuthorizationContext
    func completeAuthorization(using context: GitHubBrowserAuthorizationContext) async throws -> GitHubAppSession
    func validSession() async throws -> GitHubAppSession?
    func refreshSessionIfNeeded() async throws -> GitHubAppSession?
    func forceRefreshSession() async throws -> GitHubAppSession?
    func saveManualSession(_ session: GitHubAppSession) throws
    func updateSelections(installationIDs: [Int64], repositoryIDs: [Int64]) throws -> GitHubAppSession?
    func disconnect() throws
    func cancelAuthorization()
}

final class GitHubAuthManager: GitHubAuthManaging, @unchecked Sendable {
    let configuration: GitHubAppConfiguration?

    private let credentialStore: any CredentialStore
    private let browserAuthorizer: any GitHubBrowserOAuthAuthorizing
    private let now: @Sendable () -> Date
    private let stateLock = NSLock()
    private var cachedSession: GitHubAppSession?
    private var refreshTask: Task<GitHubAppSession, Error>?

    init(
        credentialStore: any CredentialStore = KeychainCredentialStore(),
        browserAuthorizer: any GitHubBrowserOAuthAuthorizing = GitHubBrowserOAuthAuthorizer(),
        configuration: GitHubAppConfiguration? = GitHubAppConfiguration.load(),
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.credentialStore = credentialStore
        self.browserAuthorizer = browserAuthorizer
        self.configuration = configuration
        self.now = now
    }

    func loadPersistedSession() throws -> GitHubAppSession? {
        let session = try credentialStore.loadSession()
        setCachedSession(session)
        return session
    }

    func currentSession() -> GitHubAppSession? {
        withStateLock { cachedSession }
    }

    func prepareAuthorization() async throws -> GitHubBrowserAuthorizationContext {
        guard let configuration else {
            throw GitHubBrowserOAuthError.invalidConfiguration
        }

        return try await browserAuthorizer.prepareAuthorization(using: configuration)
    }

    func completeAuthorization(using context: GitHubBrowserAuthorizationContext) async throws -> GitHubAppSession {
        guard let configuration else {
            throw GitHubBrowserOAuthError.invalidConfiguration
        }

        let result = try await browserAuthorizer.waitForAuthorization(
            using: context,
            configuration: configuration
        )

        let session = GitHubAppSession(
            accessToken: result.accessToken,
            accessTokenExpiresAt: result.accessTokenExpiresAt,
            refreshToken: result.refreshToken,
            refreshTokenExpiresAt: result.refreshTokenExpiresAt,
            userID: result.userID,
            login: result.login,
            source: .githubAppBrowser,
            savedAt: now()
        )

        try credentialStore.saveSession(session)
        setCachedSession(session)
        return session
    }

    func validSession() async throws -> GitHubAppSession? {
        if cachedSessionValue() == nil {
            let session = try credentialStore.loadSession()
            setCachedSession(session)
        }

        return try await refreshSessionIfNeeded()
    }

    func refreshSessionIfNeeded() async throws -> GitHubAppSession? {
        guard let session = cachedSessionValue() else {
            return nil
        }

        guard session.source == .githubAppBrowser else {
            return session
        }

        if let accessTokenExpiresAt = session.accessTokenExpiresAt,
           accessTokenExpiresAt <= now().addingTimeInterval(300) {
            return try await refreshSession()
        }

        return session
    }

    func forceRefreshSession() async throws -> GitHubAppSession? {
        guard cachedSessionValue() != nil else {
            return nil
        }

        return try await refreshSession()
    }

    func saveManualSession(_ session: GitHubAppSession) throws {
        clearRefreshTask()
        try credentialStore.saveSession(session)
        setCachedSession(session)
    }

    func updateSelections(installationIDs: [Int64], repositoryIDs: [Int64]) throws -> GitHubAppSession? {
        guard let cachedSession = cachedSessionValue() else {
            return nil
        }

        let updatedSession = cachedSession.updatingSelections(
            installationIDs: installationIDs,
            repositoryIDs: repositoryIDs,
            savedAt: now()
        )
        try credentialStore.saveSession(updatedSession)
        setCachedSession(updatedSession)
        return updatedSession
    }

    func disconnect() throws {
        browserAuthorizer.cancelAuthorization()
        clearRefreshTask()
        setCachedSession(nil)
        try credentialStore.removeSession()
    }

    func cancelAuthorization() {
        browserAuthorizer.cancelAuthorization()
    }

    private func refreshSession() async throws -> GitHubAppSession {
        let existingTask: Task<GitHubAppSession, Error>? = withStateLock { self.refreshTask }
        if let existingTask = existingTask {
            return try await existingTask.value
        }

        let maybeSession = withStateLock { cachedSession }
        if maybeSession == nil {
            throw GitHubBrowserOAuthError.invalidConfiguration
        }
        let session = maybeSession!

        if configuration == nil {
            throw GitHubBrowserOAuthError.invalidConfiguration
        }
        let configuration = configuration!

        let newRefreshTask = Task<GitHubAppSession, Error> {
            let refreshedSession = try await browserAuthorizer.refreshSession(
                session,
                configuration: configuration
            )
            try credentialStore.saveSession(refreshedSession)
            return refreshedSession
        }
        setRefreshTask(newRefreshTask)

        do {
            let refreshedSession = try await newRefreshTask.value
            setCachedSession(refreshedSession)
            clearRefreshTask()
            return refreshedSession
        } catch {
            clearRefreshTask()
            if case GitHubBrowserOAuthError.refreshTokenUnavailable = error {
                try? credentialStore.removeSession()
                setCachedSession(nil)
            }

            throw error
        }
    }

    private func setCachedSession(_ session: GitHubAppSession?) {
        stateLock.lock()
        cachedSession = session
        stateLock.unlock()
    }

    private func setRefreshTask(_ task: Task<GitHubAppSession, Error>?) {
        stateLock.lock()
        refreshTask = task
        stateLock.unlock()
    }

    private func clearRefreshTask() {
        stateLock.lock()
        refreshTask?.cancel()
        refreshTask = nil
        stateLock.unlock()
    }

    private func withStateLock<T>(_ body: () -> T) -> T {
        stateLock.lock()
        defer { stateLock.unlock() }
        return body()
    }

    private func cachedSessionValue() -> GitHubAppSession? {
        withStateLock { cachedSession }
    }
}
