import Foundation

enum AuthDebugLogger {
    private static let isEnabled: Bool = {
        #if DEBUG
        return true
        #else
        return ProcessInfo.processInfo.environment["ACTIONMONITOR_DEBUG_AUTH"] == "1"
        #endif
    }()

    static func logConfigurationLoad(
        clientID: String?,
        clientSecret: String?,
        callbackRegistrationURL: URL,
        bundleIdentifier: String?
    ) {
        guard isEnabled else {
            return
        }

        emit(
            "config load: callback=\(callbackRegistrationURL.absoluteString) " +
            "client_id_present=\(isPresent(clientID)) " +
            "client_secret_present=\(isPresent(clientSecret)) " +
            "bundle_id=\(bundleIdentifier ?? "nil")"
        )
    }

    static func logAuthorizationPrepared(
        authorizationURL: URL,
        redirectURI: URL
    ) {
        guard isEnabled else {
            return
        }

        let components = URLComponents(url: authorizationURL, resolvingAgainstBaseURL: false)
        let clientID = components?.queryItems?.first(where: { $0.name == "client_id" })?.value ?? "missing"

        emit(
            "auth prepared: redirect_uri=\(redirectURI.absoluteString) " +
            "auth_url=\(authorizationURL.absoluteString) " +
            "client_id=\(clientID)"
        )
    }

    static func logExternalURLOpen(_ url: URL) {
        guard isEnabled else {
            return
        }

        emit("opening external url: \(url.absoluteString)")
    }

    private static func isPresent(_ value: String?) -> Bool {
        guard let value else {
            return false
        }

        return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private static func emit(_ message: String) {
        guard let data = "[AuthDebug] \(message)\n".data(using: .utf8) else {
            return
        }

        FileHandle.standardError.write(data)
    }
}
