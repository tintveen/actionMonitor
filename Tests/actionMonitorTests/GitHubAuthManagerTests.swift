import XCTest
@testable import actionMonitor

final class GitHubAuthManagerTests: XCTestCase {
    func testEnsureSessionLoadedMemoizesConcurrentReads() async throws {
        let expectedSession = testGitHubOAuthSession()
        let credentialStore = CountingCredentialStore(
            session: expectedSession,
            loadDelay: 0.05
        )
        let authManager = GitHubAuthManager(
            credentialStore: credentialStore,
            configuration: testConfiguredOAuth()
        )

        async let first = authManager.ensureSessionLoaded()
        async let second = authManager.ensureSessionLoaded()
        async let third = authManager.ensureSessionLoaded()

        let firstSession = try await first
        let secondSession = try await second
        let thirdSession = try await third

        XCTAssertEqual(credentialStore.loadSessionCallCount, 1)
        XCTAssertEqual(firstSession, expectedSession)
        XCTAssertEqual(secondSession, expectedSession)
        XCTAssertEqual(thirdSession, expectedSession)
        XCTAssertEqual(authManager.currentSession(), expectedSession)
    }

    func testValidSessionDoesNotReadKeychainBeforeExplicitRestore() async throws {
        let credentialStore = CountingCredentialStore(session: testGitHubOAuthSession())
        let authManager = GitHubAuthManager(
            credentialStore: credentialStore,
            configuration: testConfiguredOAuth()
        )

        let session = try await authManager.validSession()

        XCTAssertNil(session)
        XCTAssertEqual(credentialStore.loadSessionCallCount, 0)
    }
}

private func testConfiguredOAuth() -> GitHubOAuthConfiguration {
    GitHubOAuthConfiguration(
        clientID: "client-id",
        clientSecret: "client-secret"
    )!
}

private func testGitHubOAuthSession() -> GitHubOAuthSession {
    GitHubOAuthSession(
        accessToken: "oauth-token",
        userID: 42,
        login: "octocat",
        source: .oauthBrowser,
        grantedScopes: ["repo"],
        savedAt: Date(timeIntervalSince1970: 1_712_000_000)
    )
}

private final class CountingCredentialStore: CredentialStore, @unchecked Sendable {
    private let stateLock = NSLock()
    private var session: GitHubOAuthSession?
    private let loadDelay: TimeInterval
    private(set) var loadSessionCallCount = 0

    init(
        session: GitHubOAuthSession?,
        loadDelay: TimeInterval = 0
    ) {
        self.session = session
        self.loadDelay = loadDelay
    }

    func loadSession() throws -> GitHubOAuthSession? {
        if loadDelay > 0 {
            Thread.sleep(forTimeInterval: loadDelay)
        }

        stateLock.lock()
        loadSessionCallCount += 1
        let session = self.session
        stateLock.unlock()
        return session
    }

    func saveSession(_ session: GitHubOAuthSession) throws {
        stateLock.lock()
        self.session = session
        stateLock.unlock()
    }

    func removeSession() throws {
        stateLock.lock()
        session = nil
        stateLock.unlock()
    }
}
