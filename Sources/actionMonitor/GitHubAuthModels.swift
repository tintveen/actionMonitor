import Foundation

enum GitHubSessionSource: String, Codable, Equatable, Sendable {
    case oauthBrowser
    case personalAccessToken

    var displayName: String {
        switch self {
        case .oauthBrowser:
            return "GitHub browser sign-in"
        case .personalAccessToken:
            return "Personal access token"
        }
    }
}

struct GitHubOAuthSession: Codable, Equatable, Sendable {
    let accessToken: String
    let userID: Int64?
    let login: String?
    let source: GitHubSessionSource
    let grantedScopes: [String]
    let savedAt: Date
    let selectedRepositoryIDs: [Int64]

    init(
        accessToken: String,
        userID: Int64? = nil,
        login: String? = nil,
        source: GitHubSessionSource,
        grantedScopes: [String] = [],
        savedAt: Date = Date(),
        selectedRepositoryIDs: [Int64] = []
    ) {
        self.accessToken = accessToken.trimmingCharacters(in: .whitespacesAndNewlines)
        self.userID = userID

        let trimmedLogin = login?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.login = trimmedLogin?.isEmpty == true ? nil : trimmedLogin
        self.source = source
        self.grantedScopes = Self.normalizedScopes(grantedScopes)
        self.savedAt = savedAt
        self.selectedRepositoryIDs = Self.normalizedIDs(selectedRepositoryIDs)
    }

    var summary: GitHubAuthSessionSummary {
        GitHubAuthSessionSummary(
            source: source,
            userID: userID,
            login: login,
            grantedScopes: grantedScopes,
            savedAt: savedAt,
            selectedRepositoryCount: selectedRepositoryIDs.count
        )
    }

    func updatingSelections(
        repositoryIDs: [Int64],
        savedAt: Date = Date()
    ) -> GitHubOAuthSession {
        GitHubOAuthSession(
            accessToken: accessToken,
            userID: userID,
            login: login,
            source: source,
            grantedScopes: grantedScopes,
            savedAt: savedAt,
            selectedRepositoryIDs: repositoryIDs
        )
    }

    private static func normalizedIDs(_ ids: [Int64]) -> [Int64] {
        Array(Set(ids)).sorted()
    }

    private static func normalizedScopes(_ scopes: [String]) -> [String] {
        Array(
            Set(
                scopes
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                    .filter { !$0.isEmpty }
            )
        )
        .sorted()
    }
}

struct GitHubAuthSessionSummary: Equatable, Sendable {
    let source: GitHubSessionSource
    let userID: Int64?
    let login: String?
    let grantedScopes: [String]
    let savedAt: Date
    let selectedRepositoryCount: Int
}

struct GitHubBrowserAuthorizationContext: Equatable, Sendable {
    let authorizationURL: URL
    let redirectURI: URL
    let state: String
    let codeVerifier: String
    let expiresAt: Date
}

struct GitHubOAuthAuthorizationResult: Equatable, Sendable {
    let accessToken: String
    let grantedScopes: [String]
    let userID: Int64?
    let login: String?
}

struct GitHubUserProfile: Codable, Equatable, Sendable {
    let id: Int64
    let login: String
}

struct GitHubAccessibleRepositorySummary: Codable, Equatable, Identifiable, Sendable {
    let id: Int64
    let ownerLogin: String
    let ownerType: String
    let name: String
    let fullName: String
    let isPrivate: Bool
    let defaultBranch: String?
}

enum GitHubAuthState: Equatable, Sendable {
    case signedOut
    case signingInBrowser(GitHubBrowserAuthorizationContext)
    case signedInOAuthApp(GitHubAuthSessionSummary)
    case signedInPersonalAccessToken(GitHubAuthSessionSummary)
    case authError(String)

    var signedInSummary: GitHubAuthSessionSummary? {
        switch self {
        case .signedInOAuthApp(let summary), .signedInPersonalAccessToken(let summary):
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

struct GitHubOAuthAppConfiguration: Equatable, Sendable {
    static let clientIDInfoDictionaryKey = "GitHubOAuthAppClientID"
    static let clientSecretInfoDictionaryKey = "GitHubOAuthAppClientSecret"
    static let legacyClientIDInfoDictionaryKeys = ["GitHubOAuthClientID", "GitHubAppClientID"]
    static let legacyClientSecretInfoDictionaryKeys = ["GitHubOAuthClientSecret", "GitHubAppClientSecret"]
    static let environmentClientIDKeys = ["ACTIONMONITOR_GITHUB_OAUTH_APP_CLIENT_ID", "GITHUB_OAUTH_APP_CLIENT_ID"]
    static let environmentClientSecretKeys = ["ACTIONMONITOR_GITHUB_OAUTH_APP_CLIENT_SECRET", "GITHUB_OAUTH_APP_CLIENT_SECRET"]
    static let callbackHost = "127.0.0.1"
    static let callbackPath = "/callback"
    static let missingConfigurationMessage = "GitHub sign-in is not configured for this build. Add GitHubOAuthAppClientID and GitHubOAuthAppClientSecret to Info.plist to enable it. If you recently changed Support/Info.plist, do a clean rebuild so the embedded plist updates."

    let clientID: String
    let clientSecret: String
    let callbackHost: String
    let callbackPath: String
    let callbackTimeout: TimeInterval

    init?(
        clientID: String?,
        clientSecret: String?,
        callbackHost: String = GitHubOAuthAppConfiguration.callbackHost,
        callbackPath: String = GitHubOAuthAppConfiguration.callbackPath,
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
    ) -> GitHubOAuthAppConfiguration? {
        let bundleInfoDictionary = bundle.infoDictionary ?? [:]
        let sourceInfoDictionary = sourceInfoDictionaryFallback()
        let environment = ProcessInfo.processInfo.environment

        let bundledClientID = firstNonEmptyValue(
            for: [clientIDInfoDictionaryKey],
            in: bundleInfoDictionary
        )
        let bundledClientSecret = firstNonEmptyValue(
            for: [clientSecretInfoDictionaryKey],
            in: bundleInfoDictionary
        )
        let legacyBundledClientID = firstNonEmptyValue(
            for: legacyClientIDInfoDictionaryKeys,
            in: bundleInfoDictionary
        )
        let legacyBundledClientSecret = firstNonEmptyValue(
            for: legacyClientSecretInfoDictionaryKeys,
            in: bundleInfoDictionary
        )
        let sourceClientID = firstNonEmptyValue(
            for: [clientIDInfoDictionaryKey] + legacyClientIDInfoDictionaryKeys,
            in: sourceInfoDictionary
        )
        let sourceClientSecret = firstNonEmptyValue(
            for: [clientSecretInfoDictionaryKey] + legacyClientSecretInfoDictionaryKeys,
            in: sourceInfoDictionary
        )
        let environmentClientID = firstNonEmptyEnvironmentValue(for: environmentClientIDKeys, in: environment)
        let environmentClientSecret = firstNonEmptyEnvironmentValue(for: environmentClientSecretKeys, in: environment)

        let resolvedClientID = clientIDOverride ??
            bundledClientID ??
            environmentClientID ??
            sourceClientID ??
            legacyBundledClientID
        let resolvedClientSecret = clientSecretOverride ??
            bundledClientSecret ??
            environmentClientSecret ??
            sourceClientSecret ??
            legacyBundledClientSecret

        AuthDebugLogger.logConfigurationLoad(
            clientID: resolvedClientID,
            clientSecret: resolvedClientSecret,
            callbackRegistrationURL: URL(string: "http://\(callbackHost)\(callbackPath)")!,
            bundleIdentifier: bundle.bundleIdentifier
        )

        return GitHubOAuthAppConfiguration(
            clientID: resolvedClientID,
            clientSecret: resolvedClientSecret
        )
    }

    var callbackRegistrationURL: URL {
        URL(string: "http://\(callbackHost)\(callbackPath)")!
    }

    private static func firstNonEmptyValue(
        for keys: [String],
        in dictionary: [String: Any]?
    ) -> String? {
        guard let dictionary else {
            return nil
        }

        return keys.lazy
            .compactMap { dictionary[$0] as? String }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty })
    }

    private static func firstNonEmptyEnvironmentValue(
        for keys: [String],
        in environment: [String: String]
    ) -> String? {
        keys.lazy
            .compactMap { environment[$0] }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty })
    }

    private static func sourceInfoDictionaryFallback() -> [String: Any]? {
        #if DEBUG
        let sourceFileURL = URL(fileURLWithPath: #filePath)
        let repositoryRootURL = sourceFileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let plistURL = repositoryRootURL.appendingPathComponent("Support/Info.plist")
        return NSDictionary(contentsOf: plistURL) as? [String: Any]
        #else
        return nil
        #endif
    }
}

typealias GitHubOAuthConfiguration = GitHubOAuthAppConfiguration
typealias GitHubCredential = GitHubOAuthSession
typealias GitHubCredentialSource = GitHubSessionSource
typealias GitHubAuthAccountSummary = GitHubAuthSessionSummary

extension GitHubAuthState {
    static func signedInOAuth(_ summary: GitHubAuthSessionSummary) -> GitHubAuthState {
        .signedInOAuthApp(summary)
    }
}
