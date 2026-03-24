import CryptoKit
import Foundation
import Network
#if canImport(Security)
import Security
#endif
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

protocol GitHubBrowserOAuthAuthorizing: Sendable {
    func prepareAuthorization(using configuration: GitHubAppConfiguration) async throws -> GitHubBrowserAuthorizationContext
    func waitForAuthorization(
        using context: GitHubBrowserAuthorizationContext,
        configuration: GitHubAppConfiguration
    ) async throws -> GitHubAppAuthorizationResult
    func refreshSession(
        _ session: GitHubAppSession,
        configuration: GitHubAppConfiguration
    ) async throws -> GitHubAppSession
    func cancelAuthorization()
}

enum GitHubBrowserOAuthError: LocalizedError, Equatable {
    case accessDenied(String?)
    case callbackCancelled
    case callbackTimedOut
    case invalidCallback
    case invalidConfiguration
    case invalidResponse
    case invalidState
    case loopbackListenerFailed(String)
    case refreshTokenUnavailable
    case unexpectedOAuthError(String)
    case unexpectedStatus(code: Int, message: String?)
    case network(String)

    var errorDescription: String? {
        switch self {
        case .accessDenied(let message):
            return message?.isEmpty == false ? message : "GitHub sign-in was cancelled."
        case .callbackCancelled:
            return "GitHub sign-in was cancelled."
        case .callbackTimedOut:
            return "GitHub sign-in timed out. Start sign-in again."
        case .invalidCallback:
            return "GitHub sign-in returned an invalid callback."
        case .invalidConfiguration:
            return "GitHub sign-in is misconfigured for this build."
        case .invalidResponse:
            return "GitHub sign-in returned an invalid response."
        case .invalidState:
            return "GitHub sign-in could not be verified safely. Start sign-in again."
        case .loopbackListenerFailed(let message):
            return "Could not start the GitHub callback listener: \(message)"
        case .refreshTokenUnavailable:
            return "GitHub sign-in needs to be started again."
        case .unexpectedOAuthError(let message):
            return "GitHub sign-in failed: \(message)"
        case .unexpectedStatus(let code, let message):
            if let message, !message.isEmpty {
                return "GitHub sign-in failed (\(code)): \(message)"
            }

            return "GitHub sign-in failed with status \(code)."
        case .network(let message):
            return "Network error: \(message)"
        }
    }
}

protocol GitHubOAuthCallbackReceiverFactory: Sendable {
    func makeReceiver(host: String) -> any GitHubOAuthCallbackReceiving
}

protocol GitHubOAuthCallbackReceiving: Sendable {
    func start(path: String) async throws -> URL
    func waitForCallback(timeout: TimeInterval) async throws -> URL
    func cancel()
}

final class GitHubBrowserOAuthAuthorizer: GitHubBrowserOAuthAuthorizing, @unchecked Sendable {
    let session: URLSession
    let gitHubURL: URL
    let apiBaseURL: URL
    let callbackReceiverFactory: any GitHubOAuthCallbackReceiverFactory
    private let now: @Sendable () -> Date
    private let randomData: @Sendable (Int) -> Data

    private let stateLock = NSLock()
    private var activeReceiver: (any GitHubOAuthCallbackReceiving)?

    init(
        session: URLSession = .shared,
        gitHubURL: URL = URL(string: "https://github.com")!,
        apiBaseURL: URL = URL(string: "https://api.github.com")!,
        callbackReceiverFactory: any GitHubOAuthCallbackReceiverFactory = GitHubLoopbackCallbackReceiverFactory(),
        now: @escaping @Sendable () -> Date = Date.init,
        randomData: @escaping @Sendable (Int) -> Data = { count in
            var bytes = [UInt8](repeating: 0, count: count)
            let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
            guard status == errSecSuccess else {
                return Data(UUID().uuidString.utf8)
            }

            return Data(bytes)
        }
    ) {
        self.session = session
        self.gitHubURL = gitHubURL
        self.apiBaseURL = apiBaseURL
        self.callbackReceiverFactory = callbackReceiverFactory
        self.now = now
        self.randomData = randomData
    }

    func prepareAuthorization(using configuration: GitHubAppConfiguration) async throws -> GitHubBrowserAuthorizationContext {
        cancelAuthorization()

        let receiver = callbackReceiverFactory.makeReceiver(host: configuration.callbackHost)
        storeActiveReceiver(receiver)

        do {
            let redirectURI = try await receiver.start(path: configuration.callbackPath)
            let state = randomData(24).base64URLString
            let codeVerifier = randomData(32).base64URLString
            let codeChallenge = codeVerifier.pkceCodeChallenge

            var components = URLComponents(
                url: gitHubURL.appending(path: "/login/oauth/authorize"),
                resolvingAgainstBaseURL: false
            )
            components?.queryItems = [
                URLQueryItem(name: "client_id", value: configuration.clientID),
                URLQueryItem(name: "redirect_uri", value: redirectURI.absoluteString),
                URLQueryItem(name: "state", value: state),
                URLQueryItem(name: "code_challenge", value: codeChallenge),
                URLQueryItem(name: "code_challenge_method", value: "S256"),
                URLQueryItem(name: "allow_signup", value: "true"),
                URLQueryItem(name: "prompt", value: "select_account"),
            ]

            guard let authorizationURL = components?.url else {
                throw GitHubBrowserOAuthError.invalidResponse
            }

            AuthDebugLogger.logAuthorizationPrepared(
                authorizationURL: authorizationURL,
                redirectURI: redirectURI
            )

            return GitHubBrowserAuthorizationContext(
                authorizationURL: authorizationURL,
                redirectURI: redirectURI,
                state: state,
                codeVerifier: codeVerifier,
                expiresAt: now().addingTimeInterval(configuration.callbackTimeout)
            )
        } catch {
            receiver.cancel()
            clearActiveReceiver(receiver)

            if let error = error as? GitHubBrowserOAuthError {
                throw error
            }

            throw GitHubBrowserOAuthError.loopbackListenerFailed(error.localizedDescription)
        }
    }

    func waitForAuthorization(
        using context: GitHubBrowserAuthorizationContext,
        configuration: GitHubAppConfiguration
    ) async throws -> GitHubAppAuthorizationResult {
        guard let receiver = currentActiveReceiver else {
            throw GitHubBrowserOAuthError.callbackCancelled
        }

        do {
            let callbackURL = try await receiver.waitForCallback(timeout: configuration.callbackTimeout)
            let callback = try parseCallbackURL(callbackURL)

            if let error = callback.error {
                throw GitHubBrowserOAuthError.accessDenied(callback.errorDescription ?? error)
            }

            guard callback.state == context.state else {
                throw GitHubBrowserOAuthError.invalidState
            }

            guard let code = callback.code, !code.isEmpty else {
                throw GitHubBrowserOAuthError.invalidCallback
            }

            let token = try await exchangeCodeForToken(
                code: code,
                redirectURI: context.redirectURI,
                codeVerifier: context.codeVerifier,
                configuration: configuration
            )
            let profile = try await fetchViewer(accessToken: token.accessToken)

            receiver.cancel()
            clearActiveReceiver(receiver)

            return GitHubAppAuthorizationResult(
                accessToken: token.accessToken,
                accessTokenExpiresAt: token.accessTokenExpiresAt(from: now()),
                refreshToken: token.refreshToken,
                refreshTokenExpiresAt: token.refreshTokenExpiresAt(from: now()),
                userID: profile?.id,
                login: profile?.login
            )
        } catch is CancellationError {
            receiver.cancel()
            clearActiveReceiver(receiver)
            throw GitHubBrowserOAuthError.callbackCancelled
        } catch let error as GitHubBrowserOAuthError {
            receiver.cancel()
            clearActiveReceiver(receiver)
            throw error
        } catch {
            receiver.cancel()
            clearActiveReceiver(receiver)
            throw GitHubBrowserOAuthError.network(error.localizedDescription)
        }
    }

    func cancelAuthorization() {
        guard let receiver = currentActiveReceiver else {
            return
        }

        receiver.cancel()
        clearActiveReceiver(receiver)
    }

    func authorizationURL(for context: GitHubBrowserAuthorizationContext) -> URL {
        context.authorizationURL
    }

    func refreshSession(
        _ session: GitHubAppSession,
        configuration: GitHubAppConfiguration
    ) async throws -> GitHubAppSession {
        guard let refreshToken = session.refreshToken,
              !refreshToken.isEmpty else {
            throw GitHubBrowserOAuthError.refreshTokenUnavailable
        }

        let token = try await refreshUserAccessToken(
            refreshToken: refreshToken,
            configuration: configuration
        )

        return session.updatingTokens(
            accessToken: token.accessToken,
            accessTokenExpiresAt: token.accessTokenExpiresAt(from: now()),
            refreshToken: token.refreshToken,
            refreshTokenExpiresAt: token.refreshTokenExpiresAt(from: now()),
            savedAt: now()
        )
    }

    private var currentActiveReceiver: (any GitHubOAuthCallbackReceiving)? {
        stateLock.lock()
        defer { stateLock.unlock() }
        return activeReceiver
    }

    private func storeActiveReceiver(_ receiver: any GitHubOAuthCallbackReceiving) {
        stateLock.lock()
        activeReceiver = receiver
        stateLock.unlock()
    }

    private func clearActiveReceiver(_ receiver: any GitHubOAuthCallbackReceiving) {
        stateLock.lock()
        defer { stateLock.unlock() }

        if let activeReceiver,
           ObjectIdentifier(activeReceiver as AnyObject) == ObjectIdentifier(receiver as AnyObject) {
            self.activeReceiver = nil
        }
    }

    private func exchangeCodeForToken(
        code: String,
        redirectURI: URL,
        codeVerifier: String,
        configuration: GitHubAppConfiguration
    ) async throws -> GitHubOAuthToken {
        do {
            var request = URLRequest(url: gitHubURL.appending(path: "/login/oauth/access_token"))
            request.httpMethod = "POST"
            request.httpBody = formEncodedBody([
                "client_id": configuration.clientID,
                "client_secret": configuration.clientSecret,
                "code": code,
                "redirect_uri": redirectURI.absoluteString,
                "code_verifier": codeVerifier,
            ])
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.setValue(GitHubClient.userAgent, forHTTPHeaderField: "User-Agent")

            let (data, response) = try await session.data(for: request)
            let httpResponse = try validatedHTTPResponse(response)

            guard httpResponse.statusCode == 200 else {
                throw decodeHTTPError(data: data, statusCode: httpResponse.statusCode)
            }

            let tokenResponse = try JSONDecoder().decode(GitHubOAuthTokenResponse.self, from: data)
            if let error = tokenResponse.error {
                throw GitHubBrowserOAuthError.unexpectedOAuthError(
                    tokenResponse.errorDescription ?? error
                )
            }

            guard let accessToken = tokenResponse.accessToken, !accessToken.isEmpty else {
                throw GitHubBrowserOAuthError.invalidResponse
            }

            return GitHubOAuthToken(
                accessToken: accessToken,
                expiresIn: tokenResponse.expiresIn,
                refreshToken: tokenResponse.refreshToken,
                refreshTokenExpiresIn: tokenResponse.refreshTokenExpiresIn
            )
        } catch let error as GitHubBrowserOAuthError {
            throw error
        } catch {
            throw GitHubBrowserOAuthError.network(error.localizedDescription)
        }
    }

    private func refreshUserAccessToken(
        refreshToken: String,
        configuration: GitHubAppConfiguration
    ) async throws -> GitHubOAuthToken {
        do {
            var request = URLRequest(url: gitHubURL.appending(path: "/login/oauth/access_token"))
            request.httpMethod = "POST"
            request.httpBody = formEncodedBody([
                "client_id": configuration.clientID,
                "client_secret": configuration.clientSecret,
                "grant_type": "refresh_token",
                "refresh_token": refreshToken,
            ])
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.setValue(GitHubClient.userAgent, forHTTPHeaderField: "User-Agent")

            let (data, response) = try await session.data(for: request)
            let httpResponse = try validatedHTTPResponse(response)

            guard httpResponse.statusCode == 200 else {
                throw decodeHTTPError(data: data, statusCode: httpResponse.statusCode)
            }

            let tokenResponse = try JSONDecoder().decode(GitHubOAuthTokenResponse.self, from: data)
            if let error = tokenResponse.error {
                throw GitHubBrowserOAuthError.unexpectedOAuthError(
                    tokenResponse.errorDescription ?? error
                )
            }

            guard let accessToken = tokenResponse.accessToken, !accessToken.isEmpty else {
                throw GitHubBrowserOAuthError.invalidResponse
            }

            return GitHubOAuthToken(
                accessToken: accessToken,
                expiresIn: tokenResponse.expiresIn,
                refreshToken: tokenResponse.refreshToken,
                refreshTokenExpiresIn: tokenResponse.refreshTokenExpiresIn
            )
        } catch let error as GitHubBrowserOAuthError {
            throw error
        } catch {
            throw GitHubBrowserOAuthError.network(error.localizedDescription)
        }
    }

    private func fetchViewer(accessToken: String) async throws -> GitHubUserProfile? {
        do {
            var request = URLRequest(url: apiBaseURL.appending(path: "/user"))
            request.httpMethod = "GET"
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue(GitHubClient.apiVersion, forHTTPHeaderField: "X-GitHub-Api-Version")
            request.setValue(GitHubClient.userAgent, forHTTPHeaderField: "User-Agent")
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

            let (data, response) = try await session.data(for: request)
            let httpResponse = try validatedHTTPResponse(response)

            guard httpResponse.statusCode == 200 else {
                throw decodeHTTPError(data: data, statusCode: httpResponse.statusCode)
            }

            return try JSONDecoder().decode(GitHubViewerResponse.self, from: data).profile
        } catch let error as GitHubBrowserOAuthError {
            throw error
        } catch {
            throw GitHubBrowserOAuthError.network(error.localizedDescription)
        }
    }

    private func parseCallbackURL(_ callbackURL: URL) throws -> GitHubOAuthCallback {
        guard let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
              components.path == callbackURL.path else {
            throw GitHubBrowserOAuthError.invalidCallback
        }

        let items = Dictionary(
            uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") }
        )

        return GitHubOAuthCallback(
            code: items["code"],
            state: items["state"],
            error: items["error"],
            errorDescription: items["error_description"]
        )
    }

    private func validatedHTTPResponse(_ response: URLResponse) throws -> HTTPURLResponse {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GitHubBrowserOAuthError.invalidResponse
        }

        return httpResponse
    }

    private func decodeHTTPError(data: Data, statusCode: Int) -> GitHubBrowserOAuthError {
        let decoder = JSONDecoder()

        if let oauthError = try? decoder.decode(GitHubOAuthTokenResponse.self, from: data),
           let error = oauthError.error {
            return .unexpectedOAuthError(oauthError.errorDescription ?? error)
        }

        let message = (try? decoder.decode(GitHubAPIError.self, from: data).message)
            ?? String(data: data, encoding: .utf8)

        return .unexpectedStatus(code: statusCode, message: message)
    }

    private func formEncodedBody(_ parameters: [String: String]) -> Data {
        let body = parameters
            .sorted { $0.key < $1.key }
            .map { key, value in
                "\(key.formEncoded)=\(value.formEncoded)"
            }
            .joined(separator: "&")

        return Data(body.utf8)
    }
}

private struct GitHubOAuthCallback: Equatable {
    let code: String?
    let state: String?
    let error: String?
    let errorDescription: String?
}

private struct GitHubOAuthTokenResponse: Decodable {
    let accessToken: String?
    let expiresIn: Int?
    let refreshToken: String?
    let refreshTokenExpiresIn: Int?
    let error: String?
    let errorDescription: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case expiresIn = "expires_in"
        case refreshToken = "refresh_token"
        case refreshTokenExpiresIn = "refresh_token_expires_in"
        case error
        case errorDescription = "error_description"
    }
}

private struct GitHubOAuthToken {
    let accessToken: String
    let expiresIn: Int?
    let refreshToken: String?
    let refreshTokenExpiresIn: Int?

    func accessTokenExpiresAt(from now: Date) -> Date? {
        expiresIn.map { now.addingTimeInterval(TimeInterval($0)) }
    }

    func refreshTokenExpiresAt(from now: Date) -> Date? {
        refreshTokenExpiresIn.map { now.addingTimeInterval(TimeInterval($0)) }
    }
}

private struct GitHubViewerResponse: Decodable {
    let id: Int64
    let login: String

    var profile: GitHubUserProfile {
        GitHubUserProfile(id: id, login: login)
    }
}

struct GitHubLoopbackCallbackReceiverFactory: GitHubOAuthCallbackReceiverFactory {
    func makeReceiver(host: String) -> any GitHubOAuthCallbackReceiving {
        GitHubLoopbackCallbackReceiver(host: host)
    }
}

@preconcurrency
actor GitHubLoopbackCallbackReceiver: GitHubOAuthCallbackReceiving {
    private let host: String
    private let queue = DispatchQueue(label: "actionMonitor.oauth.callback")
    private var listener: NWListener?
    private var callbackContinuation: CheckedContinuation<URL, Error>?
    private var callbackURL: URL?
    private var callbackError: Error?

    init(host: String) {
        self.host = host
    }

    func start(path: String) async throws -> URL {
        let listener = try NWListener(using: .tcp, on: 0)

        listener.newConnectionHandler = { [weak listener] connection in
            guard let listener else {
                connection.cancel()
                return
            }

            Task {
                await self.handleConnection(connection, listener: listener, expectedPath: path)
            }
        }

        let port = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<UInt16, Error>) in
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    guard let port = listener.port?.rawValue else {
                        continuation.resume(throwing: GitHubBrowserOAuthError.loopbackListenerFailed("No loopback port was assigned."))
                        return
                    }

                    continuation.resume(returning: port)
                case .failed(let error):
                    continuation.resume(throwing: GitHubBrowserOAuthError.loopbackListenerFailed(error.localizedDescription))
                default:
                    break
                }
            }

            listener.start(queue: self.queue)
        }

        self.listener = listener

        var components = URLComponents()
        components.scheme = "http"
        components.host = host
        components.port = Int(port)
        components.path = path

        guard let redirectURI = components.url else {
            throw GitHubBrowserOAuthError.invalidConfiguration
        }

        return redirectURI
    }

    func waitForCallback(timeout: TimeInterval) async throws -> URL {
        if let callbackURL {
            return callbackURL
        }

        if let callbackError {
            throw callbackError
        }

        return try await withThrowingTaskGroup(of: URL.self) { group in
            group.addTask {
                try await withCheckedThrowingContinuation { continuation in
                    Task {
                        await self.storeContinuation(continuation)
                    }
                }
            }

            group.addTask {
                try await Task.sleep(nanoseconds: UInt64((timeout * 1_000_000_000).rounded()))
                throw GitHubBrowserOAuthError.callbackTimedOut
            }

            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }

    nonisolated func cancel() {
        Task {
            await cancelInside()
        }
    }

    private func cancelInside() {
        listener?.cancel()
        listener = nil

        if let continuation = callbackContinuation {
            callbackContinuation = nil
            continuation.resume(throwing: CancellationError())
        }
    }

    private func storeContinuation(_ continuation: CheckedContinuation<URL, Error>) {
        if let callbackURL {
            continuation.resume(returning: callbackURL)
            return
        }

        if let callbackError {
            continuation.resume(throwing: callbackError)
            return
        }

        callbackContinuation = continuation
    }

    private func handleConnection(
        _ connection: NWConnection,
        listener: NWListener,
        expectedPath: String
    ) async {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8_192) { data, _, _, error in
            Task {
                await self.processConnectionData(
                    data,
                    error: error,
                    connection: connection,
                    listener: listener,
                    expectedPath: expectedPath
                )
            }
        }
    }

    private func processConnectionData(
        _ data: Data?,
        error: NWError?,
        connection: NWConnection,
        listener: NWListener,
        expectedPath: String
    ) async {
        defer {
            connection.cancel()
            listener.cancel()
            self.listener = nil
        }

        if let error {
            resolveCallback(with: .failure(GitHubBrowserOAuthError.loopbackListenerFailed(error.localizedDescription)))
            return
        }

        guard let data,
              let request = String(data: data, encoding: .utf8),
              let requestLine = request.components(separatedBy: "\r\n").first else {
            await sendResponse(
                to: connection,
                statusLine: "HTTP/1.1 400 Bad Request",
                body: "Invalid callback request."
            )
            resolveCallback(with: .failure(GitHubBrowserOAuthError.invalidCallback))
            return
        }

        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2 else {
            await sendResponse(
                to: connection,
                statusLine: "HTTP/1.1 400 Bad Request",
                body: "Invalid callback request."
            )
            resolveCallback(with: .failure(GitHubBrowserOAuthError.invalidCallback))
            return
        }

        let pathAndQuery = String(parts[1])
        var components = URLComponents()
        components.scheme = "http"
        components.host = host
        components.port = Int(listener.port?.rawValue ?? 0)

        if let separatorIndex = pathAndQuery.firstIndex(of: "?") {
            components.percentEncodedPath = String(pathAndQuery[..<separatorIndex])
            components.percentEncodedQuery = String(pathAndQuery[pathAndQuery.index(after: separatorIndex)...])
        } else {
            components.percentEncodedPath = pathAndQuery
        }

        guard let callbackURL = components.url,
              callbackURL.path == expectedPath else {
            await sendResponse(
                to: connection,
                statusLine: "HTTP/1.1 404 Not Found",
                body: "GitHub sign-in callback was not recognized."
            )
            resolveCallback(with: .failure(GitHubBrowserOAuthError.invalidCallback))
            return
        }

        await sendResponse(
            to: connection,
            statusLine: "HTTP/1.1 200 OK",
            body: GitHubLoopbackCallbackReceiver.successHTML
        )
        resolveCallback(with: .success(callbackURL))
    }

    private func resolveCallback(with result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            callbackURL = url
            callbackError = nil
            callbackContinuation?.resume(returning: url)
        case .failure(let error):
            callbackURL = nil
            callbackError = error
            callbackContinuation?.resume(throwing: error)
        }

        callbackContinuation = nil
    }

    private func sendResponse(
        to connection: NWConnection,
        statusLine: String,
        body: String
    ) async {
        let response = """
        \(statusLine)
        Content-Type: text/html; charset=utf-8
        Content-Length: \(body.utf8.count)
        Connection: close

        \(body)
        """

        await withCheckedContinuation { continuation in
            connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in
                continuation.resume()
            })
        }
    }

    private static let successHTML = """
    <!doctype html>
    <html>
      <head>
        <meta charset="utf-8" />
        <title>GitHub Sign-In Complete</title>
      </head>
      <body style="font-family:-apple-system, BlinkMacSystemFont, sans-serif; padding: 32px;">
        <h1>GitHub sign-in complete</h1>
        <p>You can return to actionMonitor now.</p>
      </body>
    </html>
    """
}

private extension String {
    var formEncoded: String {
        addingPercentEncoding(
            withAllowedCharacters: CharacterSet.urlQueryAllowed.subtracting(
                CharacterSet(charactersIn: "+&=")
            )
        ) ?? self
    }

    var pkceCodeChallenge: String {
        Data(SHA256.hash(data: Data(utf8))).base64URLString
    }
}

private extension Data {
    var base64URLString: String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
