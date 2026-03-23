import Foundation

protocol CredentialStore: Sendable {
    func loadCredential() throws -> GitHubCredential?
    func saveCredential(_ credential: GitHubCredential) throws
    func removeCredential() throws
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
            return "Keychain returned unreadable credential data."
        case .unsupportedPlatform:
            return "Saving GitHub credentials is only supported by the macOS menu bar app."
        case .disabledInDemoMode:
            return "GitHub sign-in is disabled while actionMonitor is running in demo mode."
        }
    }
}

#if canImport(Security)
import Security

struct KeychainCredentialStore: CredentialStore {
    private let service = "actionMonitor.github.token"
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

    func loadCredential() throws -> GitHubCredential? {
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

            return try Self.decodeStoredCredentialData(data)
        case errSecItemNotFound:
            return nil
        default:
            throw CredentialStoreError.unexpectedStatus(Int(status))
        }
    }

    func saveCredential(_ credential: GitHubCredential) throws {
        let data = try Self.encodeCredential(credential)
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

    func removeCredential() throws {
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

    static func decodeStoredCredentialData(
        _ data: Data,
        legacySavedAt: Date = Date()
    ) throws -> GitHubCredential {
        if let credential = try? decoder.decode(GitHubCredential.self, from: data) {
            return credential
        }

        guard let token = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !token.isEmpty else {
            throw CredentialStoreError.invalidData
        }

        return GitHubCredential(
            accessToken: token,
            source: .personalAccessToken,
            login: nil,
            grantedScopes: [],
            savedAt: legacySavedAt
        )
    }

    static func encodeCredential(_ credential: GitHubCredential) throws -> Data {
        try encoder.encode(credential)
    }
}

struct DemoCredentialStore: CredentialStore {
    func loadCredential() throws -> GitHubCredential? {
        nil
    }

    func saveCredential(_ credential: GitHubCredential) throws {
        throw CredentialStoreError.disabledInDemoMode
    }

    func removeCredential() throws {
        throw CredentialStoreError.disabledInDemoMode
    }
}
#else
struct KeychainCredentialStore: CredentialStore {
    func loadCredential() throws -> GitHubCredential? {
        guard let token = ProcessInfo.processInfo.environment["GITHUB_TOKEN"],
              !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        return GitHubCredential(
            accessToken: token,
            source: .personalAccessToken,
            login: nil,
            grantedScopes: [],
            savedAt: Date()
        )
    }

    func saveCredential(_ credential: GitHubCredential) throws {
        throw CredentialStoreError.unsupportedPlatform
    }

    func removeCredential() throws {
        throw CredentialStoreError.unsupportedPlatform
    }
}

struct DemoCredentialStore: CredentialStore {
    func loadCredential() throws -> GitHubCredential? {
        nil
    }

    func saveCredential(_ credential: GitHubCredential) throws {
        throw CredentialStoreError.disabledInDemoMode
    }

    func removeCredential() throws {
        throw CredentialStoreError.disabledInDemoMode
    }
}
#endif
