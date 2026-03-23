import XCTest
@testable import actionMonitor

final class CredentialStoreTests: XCTestCase {
    func testStructuredCredentialEncodingRoundTrips() throws {
        let credential = GitHubCredential(
            accessToken: "oauth-token",
            source: .oauthBrowser,
            login: "octocat",
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
                source: .personalAccessToken,
                login: nil,
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
}
