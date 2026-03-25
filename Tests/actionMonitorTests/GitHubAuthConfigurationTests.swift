import Foundation
import XCTest
@testable import actionMonitor

final class GitHubAuthConfigurationTests: XCTestCase {
    override func tearDown() {
        unsetenv("ACTIONMONITOR_GITHUB_OAUTH_INFO_PLIST")
        unsetenv("ACTIONMONITOR_GITHUB_OAUTH_APP_CLIENT_ID")
        unsetenv("ACTIONMONITOR_GITHUB_OAUTH_APP_CLIENT_SECRET")
        super.tearDown()
    }

    func testLoadUsesLocalOverridePlistWhenBundleConfigurationIsBlank() throws {
        let plistURL = try makeLocalOverridePlist(
            clientID: "local-client-id",
            clientSecret: "local-client-secret"
        )
        setenv("ACTIONMONITOR_GITHUB_OAUTH_INFO_PLIST", plistURL.path, 1)

        let configuration = GitHubOAuthAppConfiguration.load(from: .main)

        XCTAssertEqual(
            configuration,
            GitHubOAuthAppConfiguration(
                clientID: "local-client-id",
                clientSecret: "local-client-secret"
            )
        )
    }

    func testEnvironmentVariablesOverrideLocalOverridePlist() throws {
        let plistURL = try makeLocalOverridePlist(
            clientID: "local-client-id",
            clientSecret: "local-client-secret"
        )
        setenv("ACTIONMONITOR_GITHUB_OAUTH_INFO_PLIST", plistURL.path, 1)
        setenv("ACTIONMONITOR_GITHUB_OAUTH_APP_CLIENT_ID", "env-client-id", 1)
        setenv("ACTIONMONITOR_GITHUB_OAUTH_APP_CLIENT_SECRET", "env-client-secret", 1)

        let configuration = GitHubOAuthAppConfiguration.load(from: .main)

        XCTAssertEqual(
            configuration,
            GitHubOAuthAppConfiguration(
                clientID: "env-client-id",
                clientSecret: "env-client-secret"
            )
        )
    }

    private func makeLocalOverridePlist(
        clientID: String,
        clientSecret: String
    ) throws -> URL {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )

        let plistURL = directoryURL.appendingPathComponent("Info.local.plist")
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "https://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>GitHubOAuthAppClientID</key>
            <string>\(clientID)</string>
            <key>GitHubOAuthAppClientSecret</key>
            <string>\(clientSecret)</string>
        </dict>
        </plist>
        """
        try Data(plist.utf8).write(to: plistURL)
        return plistURL
    }
}
