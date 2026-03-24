import Foundation

protocol CredentialStore: Sendable {
    func loadSession() throws -> GitHubOAuthSession?
    func saveSession(_ session: GitHubOAuthSession) throws
    func removeSession() throws
}

enum CredentialStoreError: LocalizedError {
    case unexpectedStatus(Int)
    case invalidData
    case migrationRequired
    case unsupportedPlatform
    case disabledInDemoMode

    var errorDescription: String? {
        switch self {
        case .unexpectedStatus(let status):
            return "Keychain access failed with status \(status)."
        case .invalidData:
            return "Keychain returned unreadable GitHub session data."
        case .migrationRequired:
            return "Your saved GitHub session came from the old GitHub App flow. Connect GitHub again."
        case .unsupportedPlatform:
            return "Saving GitHub sessions is only supported by the macOS menu bar app."
        case .disabledInDemoMode:
            return "GitHub sign-in is disabled while actionMonitor is running in demo mode."
        }
    }
}

#if canImport(Security)
import Security

struct KeychainCredentialStore: CredentialStore {
    private let service = "actionMonitor.github.oauth-session"
    private let legacyService = "actionMonitor.github.session"
    private let account = "github.com"
    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    func loadSession() throws -> GitHubOAuthSession? {
        if let data = try loadData(service: service) {
            return try Self.decodeStoredSessionData(data)
        }

        if let legacyData = try loadData(service: legacyService) {
            return try Self.decodeStoredSessionData(legacyData)
        }

        return nil
    }

    func saveSession(_ session: GitHubOAuthSession) throws {
        let data = try Self.encodeSession(session)
        try upsertData(data, service: service)
    }

    func removeSession() throws {
        try removeData(service: service)
        try removeData(service: legacyService)
    }

    static func decodeStoredSessionData(
        _ data: Data,
        legacySavedAt: Date = Date()
    ) throws -> GitHubOAuthSession {
        if let session = try? decoder.decode(GitHubOAuthSession.self, from: data) {
            return session
        }

        if let legacySession = try? decoder.decode(LegacyGitHubAppSession.self, from: data),
           legacySession.requiresReconnect {
            throw CredentialStoreError.migrationRequired
        }

        if let credential = try? decoder.decode(LegacyGitHubCredential.self, from: data) {
            return GitHubOAuthSession(
                accessToken: credential.accessToken,
                userID: nil,
                login: credential.login,
                source: credential.source.sessionSource,
                grantedScopes: [],
                savedAt: credential.savedAt ?? legacySavedAt
            )
        }

        guard let token = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !token.isEmpty else {
            throw CredentialStoreError.invalidData
        }

        return GitHubOAuthSession(
            accessToken: token,
            source: .personalAccessToken,
            grantedScopes: [],
            savedAt: legacySavedAt
        )
    }

    static func encodeSession(_ session: GitHubOAuthSession) throws -> Data {
        try encoder.encode(session)
    }

    static func decodeStoredCredentialData(
        _ data: Data,
        legacySavedAt: Date = Date()
    ) throws -> GitHubOAuthSession {
        try decodeStoredSessionData(data, legacySavedAt: legacySavedAt)
    }

    static func encodeCredential(_ credential: GitHubOAuthSession) throws -> Data {
        try encodeSession(credential)
    }

    private func loadData(service: String) throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        switch status {
        case errSecSuccess:
            guard let data = item as? Data else {
                throw CredentialStoreError.invalidData
            }
            return data
        case errSecItemNotFound:
            return nil
        default:
            throw CredentialStoreError.unexpectedStatus(Int(status))
        }
    }

    private func upsertData(_ data: Data, service: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]

        let attributes: [String: Any] = [
            kSecValueData as String: data,
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecItemNotFound {
            var insertQuery = query
            insertQuery[kSecValueData as String] = data

            let insertStatus = SecItemAdd(insertQuery as CFDictionary, nil)
            guard insertStatus == errSecSuccess else {
                throw CredentialStoreError.unexpectedStatus(Int(insertStatus))
            }

            return
        }

        guard updateStatus == errSecSuccess else {
            throw CredentialStoreError.unexpectedStatus(Int(updateStatus))
        }
    }

    private func removeData(service: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw CredentialStoreError.unexpectedStatus(Int(status))
        }
    }
}

struct DemoCredentialStore: CredentialStore {
    func loadSession() throws -> GitHubOAuthSession? {
        nil
    }

    func saveSession(_ session: GitHubOAuthSession) throws {
        throw CredentialStoreError.disabledInDemoMode
    }

    func removeSession() throws {
        throw CredentialStoreError.disabledInDemoMode
    }
}
#else
struct KeychainCredentialStore: CredentialStore {
    func loadSession() throws -> GitHubOAuthSession? {
        guard let token = ProcessInfo.processInfo.environment["GITHUB_TOKEN"],
              !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        return GitHubOAuthSession(
            accessToken: token,
            source: .personalAccessToken,
            grantedScopes: [],
            savedAt: Date()
        )
    }

    func saveSession(_ session: GitHubOAuthSession) throws {
        throw CredentialStoreError.unsupportedPlatform
    }

    func removeSession() throws {
        throw CredentialStoreError.unsupportedPlatform
    }
}

struct DemoCredentialStore: CredentialStore {
    func loadSession() throws -> GitHubOAuthSession? {
        nil
    }

    func saveSession(_ session: GitHubOAuthSession) throws {
        throw CredentialStoreError.disabledInDemoMode
    }

    func removeSession() throws {
        throw CredentialStoreError.disabledInDemoMode
    }
}
#endif

private struct LegacyGitHubCredential: Decodable {
    let accessToken: String
    let source: LegacyGitHubCredentialSource
    let login: String?
    let savedAt: Date?
}

private enum LegacyGitHubCredentialSource: String, Decodable {
    case oauthBrowser
    case personalAccessToken

    var sessionSource: GitHubSessionSource {
        switch self {
        case .oauthBrowser:
            return .oauthBrowser
        case .personalAccessToken:
            return .personalAccessToken
        }
    }
}

private struct LegacyGitHubAppSession: Decodable {
    let refreshToken: String?
    let selectedInstallationIDs: [Int64]?
    let source: LegacyGitHubAppSessionSource

    var requiresReconnect: Bool {
        source == .githubAppBrowser || refreshToken != nil || !(selectedInstallationIDs ?? []).isEmpty
    }
}

private enum LegacyGitHubAppSessionSource: String, Decodable {
    case githubAppBrowser
    case personalAccessToken
}
