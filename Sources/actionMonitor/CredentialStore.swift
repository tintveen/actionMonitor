import Foundation

protocol CredentialStore: Sendable {
    func loadSession() throws -> GitHubOAuthSession?
    func saveSession(_ session: GitHubOAuthSession) throws
    func removeSession() throws
}

enum CredentialStoreFactory {
    static func makeDefault(executablePath: String? = CommandLine.arguments.first) -> any CredentialStore {
        #if canImport(Security)
        if usesKeychainPersistence(executablePath: executablePath) {
            return KeychainCredentialStore()
        }

        return FileBackedCredentialStore()
        #else
        return FileBackedCredentialStore()
        #endif
    }

    static func usesKeychainPersistence(executablePath: String? = CommandLine.arguments.first) -> Bool {
        guard let executablePath else {
            return false
        }

        return executablePath.contains(".app/Contents/MacOS/")
    }
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

enum FileBackedCredentialStoreError: LocalizedError {
    case corruptedFile(URL)
    case failedToLoad(URL, String)
    case failedToCreateDirectory(URL, String)
    case failedToSave(URL, String)

    var errorDescription: String? {
        switch self {
        case .corruptedFile(let url):
            return "The saved GitHub session at \(url.lastPathComponent) is invalid."
        case .failedToLoad(let url, let message):
            return "Could not load GitHub session from \(url.lastPathComponent): \(message)"
        case .failedToCreateDirectory(let url, let message):
            return "Could not create the GitHub session folder at \(url.path): \(message)"
        case .failedToSave(let url, let message):
            return "Could not save GitHub session to \(url.lastPathComponent): \(message)"
        }
    }
}

struct FileBackedCredentialStore: CredentialStore {
    let fileURL: URL

    init(fileURL: URL = Self.defaultFileURL()) {
        self.fileURL = fileURL
    }

    static func defaultFileURL(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        homeDirectory
            .appending(path: "Library", directoryHint: .isDirectory)
            .appending(path: "Application Support", directoryHint: .isDirectory)
            .appending(path: "actionMonitor", directoryHint: .isDirectory)
            .appending(path: "github-oauth-session.json", directoryHint: .notDirectory)
    }

    func loadSession() throws -> GitHubOAuthSession? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }

        do {
            let data = try Data(contentsOf: fileURL)
            return try GitHubOAuthSessionCodec.decode(data)
        } catch is DecodingError {
            throw FileBackedCredentialStoreError.corruptedFile(fileURL)
        } catch {
            throw FileBackedCredentialStoreError.failedToLoad(fileURL, error.localizedDescription)
        }
    }

    func saveSession(_ session: GitHubOAuthSession) throws {
        let directoryURL = fileURL.deletingLastPathComponent()

        do {
            try FileManager.default.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true
            )
        } catch {
            throw FileBackedCredentialStoreError.failedToCreateDirectory(
                directoryURL,
                error.localizedDescription
            )
        }

        do {
            let data = try GitHubOAuthSessionCodec.encode(session)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            throw FileBackedCredentialStoreError.failedToSave(fileURL, error.localizedDescription)
        }
    }

    func removeSession() throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return
        }

        do {
            try FileManager.default.removeItem(at: fileURL)
        } catch {
            throw FileBackedCredentialStoreError.failedToSave(fileURL, error.localizedDescription)
        }
    }
}

#if canImport(Security)
import Security

struct KeychainCredentialStore: CredentialStore {
    private let service = "actionMonitor.github.oauth-session"
    private let legacyService = "actionMonitor.github.session"
    private let account = "github.com"

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
        if let session = try? GitHubOAuthSessionCodec.decode(data, as: GitHubOAuthSession.self) {
            return session
        }

        if let legacySession = try? GitHubOAuthSessionCodec.decode(data, as: LegacyGitHubAppSession.self),
           legacySession.requiresReconnect {
            throw CredentialStoreError.migrationRequired
        }

        if let credential = try? GitHubOAuthSessionCodec.decode(data, as: LegacyGitHubCredential.self) {
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
        try GitHubOAuthSessionCodec.encode(session)
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

private enum GitHubOAuthSessionCodec {
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

    static func encode<T: Encodable>(_ value: T) throws -> Data {
        try encoder.encode(value)
    }

    static func decode<T: Decodable>(_ data: Data, as type: T.Type = T.self) throws -> T {
        try decoder.decode(type, from: data)
    }
}

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
