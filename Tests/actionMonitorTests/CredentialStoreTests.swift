import XCTest
@testable import actionMonitor

final class CredentialStoreTests: XCTestCase {
    func testStructuredCredentialEncodingRoundTrips() throws {
        let credential = GitHubCredential(
            accessToken: "oauth-token",
            login: "octocat",
            source: .oauthBrowser,
            grantedScopes: ["repo", "repo"],
            savedAt: Date(timeIntervalSince1970: 1_712_000_000)
        )

        let data = try KeychainCredentialStore.encodeCredential(credential)
        let decodedCredential = try KeychainCredentialStore.decodeStoredCredentialData(data)

        XCTAssertEqual(decodedCredential, credential)
    }

    func testDecodeStoredCredentialDataMigratesLegacyPlainToken() throws {
        let savedAt = Date(timeIntervalSince1970: 1_712_000_100)

        let credential = try KeychainCredentialStore.decodeStoredCredentialData(
            Data("legacy-token".utf8),
            legacySavedAt: savedAt
        )

        XCTAssertEqual(
            credential,
            GitHubCredential(
                accessToken: "legacy-token",
                login: nil,
                source: .personalAccessToken,
                grantedScopes: [],
                savedAt: savedAt
            )
        )
    }

    func testDecodeStoredCredentialDataRejectsUnreadablePayload() {
        XCTAssertThrowsError(
            try KeychainCredentialStore.decodeStoredCredentialData(Data([0xFF, 0xFE, 0xFD]))
        ) { error in
            guard case CredentialStoreError.invalidData = error else {
                return XCTFail("Expected invalidData error, got \(error)")
            }
        }
    }

    func testDecodeStoredCredentialDataRequiresReconnectForLegacyGitHubAppSession() {
        let payload = """
        {
          "accessToken": "oauth-token",
          "refreshToken": "refresh-token",
          "source": "githubAppBrowser",
          "selectedInstallationIDs": [1],
          "selectedRepositoryIDs": [101]
        }
        """

        XCTAssertThrowsError(
            try KeychainCredentialStore.decodeStoredCredentialData(Data(payload.utf8))
        ) { error in
            guard case CredentialStoreError.migrationRequired = error else {
                return XCTFail("Expected migrationRequired error, got \(error)")
            }
        }
    }
}
