import XCTest
@testable import deployBar

final class DemoWorkflowRunFetcherTests: XCTestCase {
    func testDemoRunForTintveenDotComUsesWorkflowURLInsteadOfFakeRunURL() async throws {
        let fetcher = DemoWorkflowRunFetcher()
        let site = SiteConfig(
            displayName: "tintveen.com",
            owner: "tintveen",
            repo: "tintveen.com",
            branch: "master",
            workflowFile: "deploy.yml",
            siteURL: URL(string: "https://tintveen.com")!
        )

        let run = try await fetcher.fetchLatestRun(for: site, token: nil)

        XCTAssertEqual(run?.normalizedDeployStatus, .success)
        XCTAssertEqual(run?.htmlURL, site.workflowURL)
    }
}
