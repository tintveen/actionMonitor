import Foundation

protocol CredentialStore: Sendable {
    func loadToken() throws -> String?
    func saveToken(_ token: String) throws
    func removeToken() throws
}

enum CredentialStoreError: LocalizedError {
    case unexpectedStatus(Int)
    case invalidData
    case unsupportedPlatform

    var errorDescription: String? {
        switch self {
        case .unexpectedStatus(let status):
            return "Keychain access failed with status \(status)."
        case .invalidData:
            return "Keychain returned unreadable token data."
        case .unsupportedPlatform:
            return "Saving tokens is only supported by the macOS menu bar app."
        }
    }
}

#if canImport(Security)
import Security

struct KeychainCredentialStore: CredentialStore {
    private let service = "deployBar.github.token"
    private let account = "github.com"

    func loadToken() throws -> String? {
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
            guard let data = item as? Data,
                  let token = String(data: data, encoding: .utf8) else {
                throw CredentialStoreError.invalidData
            }

            return token
        case errSecItemNotFound:
            return nil
        default:
            throw CredentialStoreError.unexpectedStatus(Int(status))
        }
    }

    func saveToken(_ token: String) throws {
        let data = Data(token.utf8)
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

    func removeToken() throws {
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
#else
struct KeychainCredentialStore: CredentialStore {
    func loadToken() throws -> String? {
        ProcessInfo.processInfo.environment["GITHUB_TOKEN"]
    }

    func saveToken(_ token: String) throws {
        throw CredentialStoreError.unsupportedPlatform
    }

    func removeToken() throws {
        throw CredentialStoreError.unsupportedPlatform
    }
}
#endif
