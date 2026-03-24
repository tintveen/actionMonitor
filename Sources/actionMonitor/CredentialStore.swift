import Foundation

protocol CredentialStore: Sendable {
    func loadSession() throws -> GitHubAppSession?
    func saveSession(_ session: GitHubAppSession) throws
    func removeSession() throws
}

enum CredentialStoreError: LocalizedError {
    case unexpectedStatus(Int)
    case invalidData
    case unsupportedPlatform
    case disabledInDemoMode

    var errorDescription: String? {
        switch self {
        case .unexpectedStatus(let status):
            return "Keychain access failed with status \(status)."
        case .invalidData:
            return "Keychain returned unreadable GitHub session data."
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
    private let service = "actionMonitor.github.session"
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

    func loadSession() throws -> GitHubAppSession? {
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

            return try Self.decodeStoredSessionData(data)
        case errSecItemNotFound:
            return nil
        default:
            throw CredentialStoreError.unexpectedStatus(Int(status))
        }
    }

    func saveSession(_ session: GitHubAppSession) throws {
        let data = try Self.encodeSession(session)
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

    func removeSession() throws {
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

    static func decodeStoredSessionData(
        _ data: Data,
        legacySavedAt: Date = Date()
    ) throws -> GitHubAppSession {
        if let session = try? decoder.decode(GitHubAppSession.self, from: data) {
            return session
        }

        if let credential = try? decoder.decode(LegacyGitHubCredential.self, from: data) {
            return GitHubAppSession(
                accessToken: credential.accessToken,
                userID: nil,
                login: credential.login,
                source: credential.source.sessionSource,
                savedAt: credential.savedAt ?? legacySavedAt
            )
        }

        guard let token = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !token.isEmpty else {
            throw CredentialStoreError.invalidData
        }

        return GitHubAppSession(
            accessToken: token,
            source: .personalAccessToken,
            savedAt: legacySavedAt
        )
    }

    static func encodeSession(_ session: GitHubAppSession) throws -> Data {
        try encoder.encode(session)
    }

    static func decodeStoredCredentialData(
        _ data: Data,
        legacySavedAt: Date = Date()
    ) throws -> GitHubAppSession {
        try decodeStoredSessionData(data, legacySavedAt: legacySavedAt)
    }

    static func encodeCredential(_ credential: GitHubAppSession) throws -> Data {
        try encodeSession(credential)
    }
}

struct DemoCredentialStore: CredentialStore {
    func loadSession() throws -> GitHubAppSession? {
        nil
    }

    func saveSession(_ session: GitHubAppSession) throws {
        throw CredentialStoreError.disabledInDemoMode
    }

    func removeSession() throws {
        throw CredentialStoreError.disabledInDemoMode
    }
}
#else
struct KeychainCredentialStore: CredentialStore {
    func loadSession() throws -> GitHubAppSession? {
        guard let token = ProcessInfo.processInfo.environment["GITHUB_TOKEN"],
              !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        return GitHubAppSession(
            accessToken: token,
            source: .personalAccessToken,
            savedAt: Date()
        )
    }

    func saveSession(_ session: GitHubAppSession) throws {
        throw CredentialStoreError.unsupportedPlatform
    }

    func removeSession() throws {
        throw CredentialStoreError.unsupportedPlatform
    }
}

struct DemoCredentialStore: CredentialStore {
    func loadSession() throws -> GitHubAppSession? {
        nil
    }

    func saveSession(_ session: GitHubAppSession) throws {
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
            return .githubAppBrowser
        case .personalAccessToken:
            return .personalAccessToken
        }
    }
}
