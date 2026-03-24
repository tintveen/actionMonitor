import Foundation

protocol GitHubAuthManaging: Sendable {
    var configuration: GitHubOAuthAppConfiguration? { get }

    func loadPersistedSession() throws -> GitHubOAuthSession?
    func currentSession() -> GitHubOAuthSession?
    func ensureSessionLoaded() async throws -> GitHubOAuthSession?
    func prepareAuthorization() async throws -> GitHubBrowserAuthorizationContext
    func completeAuthorization(using context: GitHubBrowserAuthorizationContext) async throws -> GitHubOAuthSession
    func validSession() async throws -> GitHubOAuthSession?
    func saveManualSession(_ session: GitHubOAuthSession) throws
    func updateSelections(repositoryIDs: [Int64]) throws -> GitHubOAuthSession?
    func disconnect() throws
    func cancelAuthorization()
}

final class GitHubAuthManager: GitHubAuthManaging, @unchecked Sendable {
    let configuration: GitHubOAuthAppConfiguration?

    private let credentialStore: any CredentialStore
    private let browserAuthorizer: any GitHubBrowserOAuthAuthorizing
    private let now: @Sendable () -> Date
    private let stateLock = NSLock()
    private var cachedSession: GitHubOAuthSession?
    private var didAttemptPersistedSessionRestore = false
    private var restoreTask: Task<GitHubOAuthSession?, Error>?

    init(
        credentialStore: any CredentialStore = KeychainCredentialStore(),
        browserAuthorizer: any GitHubBrowserOAuthAuthorizing = GitHubBrowserOAuthAuthorizer(),
        configuration: GitHubOAuthAppConfiguration? = GitHubOAuthAppConfiguration.load(),
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.credentialStore = credentialStore
        self.browserAuthorizer = browserAuthorizer
        self.configuration = configuration
        self.now = now
    }

    func loadPersistedSession() throws -> GitHubOAuthSession? {
        let session = try credentialStore.loadSession()
        setRestoreState(session: session, didAttemptRestore: true, restoreTask: nil)
        return session
    }

    func currentSession() -> GitHubOAuthSession? {
        withStateLock { cachedSession }
    }

    func ensureSessionLoaded() async throws -> GitHubOAuthSession? {
        if let cachedSession = cachedSessionValue() {
            return cachedSession
        }

        let existingTask = withStateLock { () -> Task<GitHubOAuthSession?, Error>? in
            if didAttemptPersistedSessionRestore {
                return nil
            }

            if let restoreTask {
                return restoreTask
            }

            let restoreTask = Task { [credentialStore] in
                try credentialStore.loadSession()
            }
            self.restoreTask = restoreTask
            return restoreTask
        }

        guard let existingTask else {
            return cachedSessionValue()
        }

        do {
            let session = try await existingTask.value
            setRestoreState(session: session, didAttemptRestore: true, restoreTask: nil)
            return session
        } catch {
            setRestoreState(
                session: cachedSessionValue(),
                didAttemptRestore: true,
                restoreTask: nil
            )
            throw error
        }
    }

    func prepareAuthorization() async throws -> GitHubBrowserAuthorizationContext {
        guard let configuration else {
            throw GitHubBrowserOAuthError.invalidConfiguration
        }

        return try await browserAuthorizer.prepareAuthorization(using: configuration)
    }

    func completeAuthorization(using context: GitHubBrowserAuthorizationContext) async throws -> GitHubOAuthSession {
        guard let configuration else {
            throw GitHubBrowserOAuthError.invalidConfiguration
        }

        let result = try await browserAuthorizer.waitForAuthorization(
            using: context,
            configuration: configuration
        )

        let session = GitHubOAuthSession(
            accessToken: result.accessToken,
            userID: result.userID,
            login: result.login,
            source: .oauthBrowser,
            grantedScopes: result.grantedScopes,
            savedAt: now()
        )

        try credentialStore.saveSession(session)
        setRestoreState(session: session, didAttemptRestore: true, restoreTask: nil)
        return session
    }

    func validSession() async throws -> GitHubOAuthSession? {
        return cachedSessionValue()
    }

    func saveManualSession(_ session: GitHubOAuthSession) throws {
        try credentialStore.saveSession(session)
        setRestoreState(session: session, didAttemptRestore: true, restoreTask: nil)
    }

    func updateSelections(repositoryIDs: [Int64]) throws -> GitHubOAuthSession? {
        guard let cachedSession = cachedSessionValue() else {
            return nil
        }

        let updatedSession = cachedSession.updatingSelections(
            repositoryIDs: repositoryIDs,
            savedAt: now()
        )
        try credentialStore.saveSession(updatedSession)
        setRestoreState(session: updatedSession, didAttemptRestore: true, restoreTask: nil)
        return updatedSession
    }

    func disconnect() throws {
        browserAuthorizer.cancelAuthorization()
        setRestoreState(session: nil, didAttemptRestore: true, restoreTask: nil)
        try credentialStore.removeSession()
    }

    func cancelAuthorization() {
        browserAuthorizer.cancelAuthorization()
    }

    private func setRestoreState(
        session: GitHubOAuthSession?,
        didAttemptRestore: Bool? = nil,
        restoreTask: Task<GitHubOAuthSession?, Error>? = nil
    ) {
        stateLock.lock()
        cachedSession = session
        if let didAttemptRestore {
            self.didAttemptPersistedSessionRestore = didAttemptRestore
        }
        self.restoreTask = restoreTask
        stateLock.unlock()
    }

    private func withStateLock<T>(_ body: () -> T) -> T {
        stateLock.lock()
        defer { stateLock.unlock() }
        return body()
    }

    private func cachedSessionValue() -> GitHubOAuthSession? {
        withStateLock { cachedSession }
    }
}
