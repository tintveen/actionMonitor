import Foundation

enum GitHubCredentialSource: String, Codable, Equatable, Sendable {
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

struct GitHubCredential: Codable, Equatable, Sendable {
    let accessToken: String
    let source: GitHubCredentialSource
    let login: String?
    let grantedScopes: [String]
    let savedAt: Date

    init(
        accessToken: String,
        source: GitHubCredentialSource,
        login: String?,
        grantedScopes: [String],
        savedAt: Date = Date()
    ) {
        self.accessToken = accessToken.trimmingCharacters(in: .whitespacesAndNewlines)
        self.source = source

        let trimmedLogin = login?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.login = trimmedLogin?.isEmpty == true ? nil : trimmedLogin
        self.grantedScopes = GitHubCredential.normalizedScopes(grantedScopes)
        self.savedAt = savedAt
    }

    var summary: GitHubAuthAccountSummary {
        GitHubAuthAccountSummary(
            source: source,
            login: login,
            grantedScopes: grantedScopes,
            savedAt: savedAt
        )
    }

    private static func normalizedScopes(_ scopes: [String]) -> [String] {
        var normalized: [String] = []
        var seen = Set<String>()

        for scope in scopes {
            let trimmedScope = scope.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedScope.isEmpty else {
                continue
            }

            let lowercasedScope = trimmedScope.lowercased()
            guard seen.insert(lowercasedScope).inserted else {
                continue
            }

            normalized.append(lowercasedScope)
        }

        return normalized.sorted()
    }
}

struct GitHubAuthAccountSummary: Equatable, Sendable {
    let source: GitHubCredentialSource
    let login: String?
    let grantedScopes: [String]
    let savedAt: Date
}

struct GitHubBrowserAuthorizationContext: Equatable, Sendable {
    let authorizationURL: URL
    let redirectURI: URL
    let state: String
    let codeVerifier: String
    let expiresAt: Date
}

enum GitHubAuthState: Equatable, Sendable {
    case signedOut
    case signingInBrowser(GitHubBrowserAuthorizationContext)
    case signedInOAuth(GitHubAuthAccountSummary)
    case signedInPersonalAccessToken(GitHubAuthAccountSummary)
    case authError(String)

    var signedInSummary: GitHubAuthAccountSummary? {
        switch self {
        case .signedInOAuth(let summary), .signedInPersonalAccessToken(let summary):
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

struct GitHubOAuthConfiguration: Equatable, Sendable {
    static let clientIDInfoDictionaryKey = "GitHubOAuthClientID"
    static let clientSecretInfoDictionaryKey = "GitHubOAuthClientSecret"
    static let defaultScope = "repo"
    static let callbackHost = "127.0.0.1"
    static let callbackPath = "/oauth/callback"
    static let missingConfigurationMessage = "GitHub sign-in is not configured for this build. Add GitHubOAuthClientID and GitHubOAuthClientSecret to Info.plist to enable it."

    let clientID: String
    let clientSecret: String
    let scope: String
    let callbackHost: String
    let callbackPath: String
    let callbackTimeout: TimeInterval

    init?(
        clientID: String?,
        clientSecret: String?,
        scope: String = GitHubOAuthConfiguration.defaultScope,
        callbackHost: String = GitHubOAuthConfiguration.callbackHost,
        callbackPath: String = GitHubOAuthConfiguration.callbackPath,
        callbackTimeout: TimeInterval = 300
    ) {
        let trimmedClientID = clientID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let trimmedClientSecret = clientSecret?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let trimmedScope = scope.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedCallbackPath = callbackPath.hasPrefix("/") ? callbackPath : "/" + callbackPath

        guard !trimmedClientID.isEmpty,
              !trimmedClientSecret.isEmpty,
              !trimmedScope.isEmpty,
              !callbackHost.isEmpty,
              !normalizedCallbackPath.isEmpty else {
            return nil
        }

        self.clientID = trimmedClientID
        self.clientSecret = trimmedClientSecret
        self.scope = trimmedScope
        self.callbackHost = callbackHost
        self.callbackPath = normalizedCallbackPath
        self.callbackTimeout = callbackTimeout
    }

    static func load(
        from bundle: Bundle = .main,
        clientIDOverride: String? = nil,
        clientSecretOverride: String? = nil
    ) -> GitHubOAuthConfiguration? {
        let bundledClientID = bundle.object(forInfoDictionaryKey: clientIDInfoDictionaryKey) as? String
        let bundledClientSecret = bundle.object(forInfoDictionaryKey: clientSecretInfoDictionaryKey) as? String
        return GitHubOAuthConfiguration(
            clientID: clientIDOverride ?? bundledClientID,
            clientSecret: clientSecretOverride ?? bundledClientSecret
        )
    }

    var callbackRegistrationURL: URL {
        URL(string: "http://\(callbackHost)\(callbackPath)")!
    }
}
