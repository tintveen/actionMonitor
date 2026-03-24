import Foundation

enum GitHubSessionSource: String, Codable, Equatable, Sendable {
    case githubAppBrowser
    case personalAccessToken

    var displayName: String {
        switch self {
        case .githubAppBrowser:
            return "GitHub App browser sign-in"
        case .personalAccessToken:
            return "Personal access token"
        }
    }
}

struct GitHubAppSession: Codable, Equatable, Sendable {
    let accessToken: String
    let accessTokenExpiresAt: Date?
    let refreshToken: String?
    let refreshTokenExpiresAt: Date?
    let userID: Int64?
    let login: String?
    let source: GitHubSessionSource
    let savedAt: Date
    let selectedInstallationIDs: [Int64]
    let selectedRepositoryIDs: [Int64]

    init(
        accessToken: String,
        accessTokenExpiresAt: Date? = nil,
        refreshToken: String? = nil,
        refreshTokenExpiresAt: Date? = nil,
        userID: Int64? = nil,
        login: String? = nil,
        source: GitHubSessionSource,
        savedAt: Date = Date(),
        selectedInstallationIDs: [Int64] = [],
        selectedRepositoryIDs: [Int64] = []
    ) {
        self.accessToken = accessToken.trimmingCharacters(in: .whitespacesAndNewlines)
        self.accessTokenExpiresAt = accessTokenExpiresAt

        let trimmedRefreshToken = refreshToken?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.refreshToken = trimmedRefreshToken?.isEmpty == true ? nil : trimmedRefreshToken
        self.refreshTokenExpiresAt = refreshTokenExpiresAt
        self.userID = userID

        let trimmedLogin = login?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.login = trimmedLogin?.isEmpty == true ? nil : trimmedLogin
        self.source = source
        self.savedAt = savedAt
        self.selectedInstallationIDs = Self.normalizedIDs(selectedInstallationIDs)
        self.selectedRepositoryIDs = Self.normalizedIDs(selectedRepositoryIDs)
    }

    var summary: GitHubAuthSessionSummary {
        GitHubAuthSessionSummary(
            source: source,
            userID: userID,
            login: login,
            accessTokenExpiresAt: accessTokenExpiresAt,
            refreshTokenExpiresAt: refreshTokenExpiresAt,
            savedAt: savedAt,
            selectedInstallationCount: selectedInstallationIDs.count,
            selectedRepositoryCount: selectedRepositoryIDs.count
        )
    }

    var canRefresh: Bool {
        guard let refreshToken, !refreshToken.isEmpty else {
            return false
        }

        return refreshTokenExpiresAt.map { $0 > Date() } ?? true
    }

    func updatingTokens(
        accessToken: String,
        accessTokenExpiresAt: Date?,
        refreshToken: String?,
        refreshTokenExpiresAt: Date?,
        savedAt: Date
    ) -> GitHubAppSession {
        GitHubAppSession(
            accessToken: accessToken,
            accessTokenExpiresAt: accessTokenExpiresAt,
            refreshToken: refreshToken,
            refreshTokenExpiresAt: refreshTokenExpiresAt,
            userID: userID,
            login: login,
            source: source,
            savedAt: savedAt,
            selectedInstallationIDs: selectedInstallationIDs,
            selectedRepositoryIDs: selectedRepositoryIDs
        )
    }

    func updatingSelections(
        installationIDs: [Int64],
        repositoryIDs: [Int64],
        savedAt: Date = Date()
    ) -> GitHubAppSession {
        GitHubAppSession(
            accessToken: accessToken,
            accessTokenExpiresAt: accessTokenExpiresAt,
            refreshToken: refreshToken,
            refreshTokenExpiresAt: refreshTokenExpiresAt,
            userID: userID,
            login: login,
            source: source,
            savedAt: savedAt,
            selectedInstallationIDs: installationIDs,
            selectedRepositoryIDs: repositoryIDs
        )
    }

    private static func normalizedIDs(_ ids: [Int64]) -> [Int64] {
        Array(Set(ids)).sorted()
    }
}

struct GitHubAuthSessionSummary: Equatable, Sendable {
    let source: GitHubSessionSource
    let userID: Int64?
    let login: String?
    let accessTokenExpiresAt: Date?
    let refreshTokenExpiresAt: Date?
    let savedAt: Date
    let selectedInstallationCount: Int
    let selectedRepositoryCount: Int
}

struct GitHubBrowserAuthorizationContext: Equatable, Sendable {
    let authorizationURL: URL
    let redirectURI: URL
    let state: String
    let codeVerifier: String
    let expiresAt: Date
}

struct GitHubAppAuthorizationResult: Equatable, Sendable {
    let accessToken: String
    let accessTokenExpiresAt: Date?
    let refreshToken: String?
    let refreshTokenExpiresAt: Date?
    let userID: Int64?
    let login: String?
}

struct GitHubUserProfile: Codable, Equatable, Sendable {
    let id: Int64
    let login: String
}

struct GitHubInstallationSummary: Codable, Equatable, Identifiable, Sendable {
    let id: Int64
    let accountLogin: String
    let accountType: String
    let targetType: String
    let repositorySelection: String

    var displayName: String {
        accountLogin
    }
}

struct GitHubAccessibleRepositorySummary: Codable, Equatable, Identifiable, Sendable {
    let id: Int64
    let installationID: Int64
    let ownerLogin: String
    let name: String
    let fullName: String
    let isPrivate: Bool
    let defaultBranch: String?

    var ownerAndRepo: String {
        fullName
    }
}

enum GitHubAuthState: Equatable, Sendable {
    case signedOut
    case signingInBrowser(GitHubBrowserAuthorizationContext)
    case signedInGitHubApp(GitHubAuthSessionSummary)
    case signedInPersonalAccessToken(GitHubAuthSessionSummary)
    case authError(String)

    var signedInSummary: GitHubAuthSessionSummary? {
        switch self {
        case .signedInGitHubApp(let summary), .signedInPersonalAccessToken(let summary):
            return summary
        case .signedOut, .signingInBrowser, .authError:
            return nil
        }
    }
}

enum OnboardingStep: String, Codable, CaseIterable, Equatable, Sendable {
    case welcome
    case githubSignIn
    case firstWorkflow
    case finish
}

struct GitHubAppConfiguration: Equatable, Sendable {
    static let clientIDInfoDictionaryKey = "GitHubAppClientID"
    static let clientSecretInfoDictionaryKey = "GitHubAppClientSecret"
    static let legacyClientIDInfoDictionaryKey = "GitHubOAuthClientID"
    static let legacyClientSecretInfoDictionaryKey = "GitHubOAuthClientSecret"
    static let callbackHost = "127.0.0.1"
    static let callbackPath = "/callback"
    static let missingConfigurationMessage = "GitHub App sign-in is not configured for this build. Add GitHubAppClientID and GitHubAppClientSecret to Info.plist to enable it."

    let clientID: String
    let clientSecret: String
    let callbackHost: String
    let callbackPath: String
    let callbackTimeout: TimeInterval

    init?(
        clientID: String?,
        clientSecret: String?,
        callbackHost: String = GitHubAppConfiguration.callbackHost,
        callbackPath: String = GitHubAppConfiguration.callbackPath,
        callbackTimeout: TimeInterval = 300
    ) {
        let trimmedClientID = clientID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let trimmedClientSecret = clientSecret?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let normalizedCallbackPath = callbackPath.hasPrefix("/") ? callbackPath : "/" + callbackPath

        guard !trimmedClientID.isEmpty,
              !trimmedClientSecret.isEmpty,
              !callbackHost.isEmpty,
              !normalizedCallbackPath.isEmpty else {
            return nil
        }

        self.clientID = trimmedClientID
        self.clientSecret = trimmedClientSecret
        self.callbackHost = callbackHost
        self.callbackPath = normalizedCallbackPath
        self.callbackTimeout = callbackTimeout
    }

    static func load(
        from bundle: Bundle = .main,
        clientIDOverride: String? = nil,
        clientSecretOverride: String? = nil
    ) -> GitHubAppConfiguration? {
        let bundledClientID = bundle.object(forInfoDictionaryKey: clientIDInfoDictionaryKey) as? String
        let bundledClientSecret = bundle.object(forInfoDictionaryKey: clientSecretInfoDictionaryKey) as? String
        let legacyClientID = bundle.object(forInfoDictionaryKey: legacyClientIDInfoDictionaryKey) as? String
        let legacyClientSecret = bundle.object(forInfoDictionaryKey: legacyClientSecretInfoDictionaryKey) as? String

        let resolvedClientID = clientIDOverride ?? bundledClientID ?? legacyClientID
        let resolvedClientSecret = clientSecretOverride ?? bundledClientSecret ?? legacyClientSecret

        AuthDebugLogger.logConfigurationLoad(
            clientID: resolvedClientID,
            clientSecret: resolvedClientSecret,
            callbackRegistrationURL: URL(string: "http://\(callbackHost)\(callbackPath)")!,
            bundleIdentifier: bundle.bundleIdentifier
        )

        return GitHubAppConfiguration(
            clientID: resolvedClientID,
            clientSecret: resolvedClientSecret
        )
    }

    var callbackRegistrationURL: URL {
        URL(string: "http://\(callbackHost)\(callbackPath)")!
    }
}

typealias GitHubOAuthConfiguration = GitHubAppConfiguration
typealias GitHubCredential = GitHubAppSession
typealias GitHubCredentialSource = GitHubSessionSource
typealias GitHubAuthAccountSummary = GitHubAuthSessionSummary

extension GitHubSessionSource {
    static var oauthBrowser: GitHubSessionSource {
        .githubAppBrowser
    }
}

extension GitHubAppSession {
    init(
        accessToken: String,
        source: GitHubSessionSource,
        login: String?,
        grantedScopes: [String],
        savedAt: Date = Date()
    ) {
        self.init(
            accessToken: accessToken,
            userID: nil,
            login: login,
            source: source,
            savedAt: savedAt
        )
    }
}

extension GitHubAuthState {
    static func signedInOAuth(_ summary: GitHubAuthSessionSummary) -> GitHubAuthState {
        .signedInGitHubApp(summary)
    }
}
