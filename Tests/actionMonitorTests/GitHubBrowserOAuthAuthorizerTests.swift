import CryptoKit
import Foundation
import XCTest
@testable import actionMonitor

final class GitHubBrowserOAuthAuthorizerTests: XCTestCase {
    override func tearDown() {
        super.tearDown()
        URLProtocolStub.reset()
    }

    func testPrepareAuthorizationBuildsBrowserURLWithLoopbackRedirectAndPKCE() async throws {
        let receiver = TestCallbackReceiver(
            redirectURI: URL(string: "http://127.0.0.1:8123/callback")!,
            callbackResult: .failure(GitHubBrowserOAuthError.callbackTimedOut)
        )
        let authorizer = GitHubBrowserOAuthAuthorizer(
            session: makeSession(),
            callbackReceiverFactory: TestCallbackReceiverFactory(receiver: receiver),
            randomData: { count in
                Data(repeating: 0x61, count: count)
            }
        )

        let context = try await authorizer.prepareAuthorization(using: configuredOAuth())
        let components = URLComponents(url: context.authorizationURL, resolvingAgainstBaseURL: false)
        let queryItems = Dictionary(uniqueKeysWithValues: (components?.queryItems ?? []).map { ($0.name, $0.value ?? "") })

        XCTAssertEqual(components?.scheme, "https")
        XCTAssertEqual(components?.host, "github.com")
        XCTAssertEqual(components?.path, "/login/oauth/authorize")
        XCTAssertEqual(queryItems["client_id"], "client-id")
        XCTAssertEqual(queryItems["redirect_uri"], "http://127.0.0.1:8123/callback")
        XCTAssertEqual(
            queryItems["scope"],
            GitHubOAuthAppConfiguration.requestedScopes.joined(separator: " ")
        )
        XCTAssertEqual(queryItems["prompt"], "select_account")
        XCTAssertEqual(queryItems["allow_signup"], "true")
        XCTAssertEqual(queryItems["state"], context.state)
        XCTAssertEqual(queryItems["code_challenge_method"], "S256")
        XCTAssertEqual(queryItems["code_challenge"], pkceChallenge(for: context.codeVerifier))
        XCTAssertEqual(receiver.startedPaths, ["/callback"])
        XCTAssertEqual(receiver.recordedHosts, ["127.0.0.1"])
    }

    func testWaitForAuthorizationExchangesCodeAndFetchesViewer() async throws {
        let receiver = TestCallbackReceiver(
            redirectURI: URL(string: "http://127.0.0.1:8123/callback")!,
            callbackResult: .failure(GitHubBrowserOAuthError.callbackTimedOut)
        )
        let authorizer = GitHubBrowserOAuthAuthorizer(
            session: makeSession(),
            callbackReceiverFactory: TestCallbackReceiverFactory(receiver: receiver),
            now: { Date(timeIntervalSince1970: 1_712_000_000) },
            randomData: { count in
                Data(repeating: 0x62, count: count)
            }
        )

        let requests = Locked<[URLRequest]>([])
        URLProtocolStub.setResponseProvider { request in
            requests.withLock { $0.append(request) }

            switch request.url?.path {
            case "/login/oauth/access_token":
                return stubResponse(
                    statusCode: 200,
                    body: """
                    {
                      "access_token": "oauth-token",
                      "scope": "\(GitHubOAuthAppConfiguration.requestedScopes.joined(separator: " "))"
                    }
                    """
                )
            case "/user":
                return stubResponse(
                    statusCode: 200,
                    body: """
                    {
                      "id": 42,
                      "login": "octocat"
                    }
                    """
                )
            default:
                throw NSError(domain: "URLProtocolStub", code: 1)
            }
        }

        let context = try await authorizer.prepareAuthorization(using: configuredOAuth())
        receiver.callbackResult = .success(
            URL(string: "http://127.0.0.1:8123/callback?code=temp-code&state=\(context.state)")!
        )

        let credential = try await authorizer.waitForAuthorization(
            using: context,
            configuration: configuredOAuth()
        )

        XCTAssertEqual(
            credential,
            GitHubOAuthAuthorizationResult(
                accessToken: "oauth-token",
                grantedScopes: GitHubOAuthAppConfiguration.requestedScopes,
                userID: 42,
                login: "octocat",
            )
        )
        XCTAssertEqual(requests.value.count, 2)
        XCTAssertEqual(requests.value.first?.url?.path, "/login/oauth/access_token")
        XCTAssertEqual(requests.value.last?.url?.path, "/user")
        XCTAssertEqual(receiver.cancelCallCount, 1)
    }

    func testWaitForAuthorizationRejectsStateMismatch() async throws {
        let receiver = TestCallbackReceiver(
            redirectURI: URL(string: "http://127.0.0.1:8123/callback")!,
            callbackResult: .failure(GitHubBrowserOAuthError.callbackTimedOut)
        )
        let authorizer = GitHubBrowserOAuthAuthorizer(
            session: makeSession(),
            callbackReceiverFactory: TestCallbackReceiverFactory(receiver: receiver)
        )

        let context = try await authorizer.prepareAuthorization(using: configuredOAuth())
        receiver.callbackResult = .success(
            URL(string: "http://127.0.0.1:8123/callback?code=temp-code&state=wrong-state")!
        )

        await XCTAssertThrowsErrorAsync(
            try await authorizer.waitForAuthorization(
                using: context,
                configuration: configuredOAuth()
            )
        ) { error in
            XCTAssertEqual(error as? GitHubBrowserOAuthError, .invalidState)
        }
    }

    func testWaitForAuthorizationMapsCallbackAccessDenied() async throws {
        let receiver = TestCallbackReceiver(
            redirectURI: URL(string: "http://127.0.0.1:8123/callback")!,
            callbackResult: .failure(GitHubBrowserOAuthError.callbackTimedOut)
        )
        let authorizer = GitHubBrowserOAuthAuthorizer(
            session: makeSession(),
            callbackReceiverFactory: TestCallbackReceiverFactory(receiver: receiver)
        )

        let context = try await authorizer.prepareAuthorization(using: configuredOAuth())
        receiver.callbackResult = .success(
            URL(string: "http://127.0.0.1:8123/callback?error=access_denied&error_description=User%20cancelled")!
        )

        await XCTAssertThrowsErrorAsync(
            try await authorizer.waitForAuthorization(
                using: context,
                configuration: configuredOAuth()
            )
        ) { error in
            XCTAssertEqual(error as? GitHubBrowserOAuthError, .accessDenied("User cancelled"))
        }
    }
}

private func configuredOAuth() -> GitHubOAuthConfiguration {
    GitHubOAuthConfiguration(
        clientID: "client-id",
        clientSecret: "client-secret"
    )!
}

private func pkceChallenge(for verifier: String) -> String {
    Data(SHA256.hash(data: Data(verifier.utf8))).base64URLString
}

private func makeSession() -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [URLProtocolStub.self]
    return URLSession(configuration: configuration)
}

private func stubResponse(statusCode: Int, body: String) -> URLProtocolStub.Response {
    URLProtocolStub.Response(
        statusCode: statusCode,
        headers: ["Content-Type": "application/json"],
        body: Data(body.utf8)
    )
}

private final class TestCallbackReceiverFactory: GitHubOAuthCallbackReceiverFactory, @unchecked Sendable {
    let receiver: TestCallbackReceiver

    init(receiver: TestCallbackReceiver) {
        self.receiver = receiver
    }

    func makeReceiver(host: String) -> any GitHubOAuthCallbackReceiving {
        receiver.recordedHosts.append(host)
        return receiver
    }
}

private final class TestCallbackReceiver: GitHubOAuthCallbackReceiving, @unchecked Sendable {
    let redirectURI: URL
    var callbackResult: Result<URL, Error>
    var startedPaths: [String] = []
    var recordedHosts: [String] = []
    private(set) var cancelCallCount = 0

    init(
        redirectURI: URL,
        callbackResult: Result<URL, Error>
    ) {
        self.redirectURI = redirectURI
        self.callbackResult = callbackResult
    }

    func start(path: String) async throws -> URL {
        startedPaths.append(path)
        return redirectURI
    }

    func waitForCallback(timeout: TimeInterval) async throws -> URL {
        try callbackResult.get()
    }

    func cancel() {
        cancelCallCount += 1
    }
}

private final class URLProtocolStub: URLProtocol, @unchecked Sendable {
    struct Response {
        let statusCode: Int
        let headers: [String: String]
        let body: Data
    }

    private static let responseProviderBox = Locked<(@Sendable (URLRequest) throws -> Response)?>(nil)

    static func setResponseProvider(_ provider: @escaping @Sendable (URLRequest) throws -> Response) {
        responseProviderBox.withLock { $0 = provider }
    }

    static func reset() {
        responseProviderBox.withLock { $0 = nil }
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let responseProvider = Self.responseProviderBox.value else {
            client?.urlProtocol(self, didFailWithError: NSError(domain: "URLProtocolStub", code: 0))
            return
        }

        do {
            let stub = try responseProvider(request)
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: stub.statusCode,
                httpVersion: nil,
                headerFields: stub.headers
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: stub.body)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private final class Locked<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: Value

    init(_ value: Value) {
        storage = value
    }

    var value: Value {
        withLock { $0 }
    }

    func withLock<T>(_ body: (inout Value) throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body(&storage)
    }
}

private func XCTAssertThrowsErrorAsync<T>(
    _ expression: @autoclosure () async throws -> T,
    _ errorHandler: (Error) -> Void
) async {
    do {
        _ = try await expression()
        XCTFail("Expected error to be thrown.")
    } catch {
        errorHandler(error)
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
