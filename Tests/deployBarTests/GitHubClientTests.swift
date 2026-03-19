import XCTest
@testable import deployBar

final class GitHubClientTests: XCTestCase {
    private let site = SiteConfig(
        displayName: "Example",
        owner: "tintveen",
        repo: "example.com",
        branch: "main",
        workflowFile: "deploy.yml",
        siteURL: URL(string: "https://example.com")!
    )

    func testLatestRunRequestIncludesWorkflowBranchAndEvent() throws {
        let client = GitHubClient(baseURL: URL(string: "https://api.github.com")!)

        let request = try client.latestRunRequest(for: site, token: "test-token")

        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.url?.absoluteString, "https://api.github.com/repos/tintveen/example.com/actions/workflows/deploy.yml/runs?branch=main&event=push&per_page=1")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/vnd.github+json")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-GitHub-Api-Version"), GitHubClient.apiVersion)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token")
    }

    func testRunningStatusesMapToRunning() {
        let statuses = ["queued", "in_progress", "requested", "pending", "waiting"]

        for status in statuses {
            let run = WorkflowRun(
                htmlURL: nil,
                status: status,
                conclusion: nil,
                headSHA: "1234567",
                createdAt: nil,
                updatedAt: nil,
                runStartedAt: nil
            )

            XCTAssertEqual(run.normalizedDeployStatus, .running)
            XCTAssertEqual(run.deployState(for: site).status, .running)
        }
    }

    func testCompletedSuccessMapsToSuccess() {
        let run = WorkflowRun(
            htmlURL: nil,
            status: "completed",
            conclusion: "success",
            headSHA: "1234567",
            createdAt: nil,
            updatedAt: Date(),
            runStartedAt: nil
        )

        XCTAssertEqual(run.normalizedDeployStatus, .success)
        XCTAssertEqual(run.deployState(for: site).status, .success)
    }

    func testCompletedFailureConclusionsMapToFailed() {
        let conclusions = ["failure", "cancelled", "timed_out", "action_required", "neutral"]

        for conclusion in conclusions {
            let run = WorkflowRun(
                htmlURL: nil,
                status: "completed",
                conclusion: conclusion,
                headSHA: "1234567",
                createdAt: nil,
                updatedAt: Date(),
                runStartedAt: nil
            )

            XCTAssertEqual(run.normalizedDeployStatus, .failed)
            XCTAssertEqual(run.deployState(for: site).status, .failed)
        }
    }

    func testCombinedStatusPrioritizesRunningThenFailedThenSuccess() {
        let running = DeployState(
            site: site,
            status: .running,
            statusText: "Deploy running",
            runURL: nil,
            commitSHA: nil,
            startedAt: nil,
            completedAt: nil,
            errorMessage: nil
        )
        let failed = DeployState(
            site: site,
            status: .failed,
            statusText: "Deploy failed",
            runURL: nil,
            commitSHA: nil,
            startedAt: nil,
            completedAt: nil,
            errorMessage: nil
        )
        let success = DeployState(
            site: site,
            status: .success,
            statusText: "Deploy succeeded",
            runURL: nil,
            commitSHA: nil,
            startedAt: nil,
            completedAt: nil,
            errorMessage: nil
        )
        let unknown = DeployState(
            site: site,
            status: .unknown,
            statusText: "Status unavailable",
            runURL: nil,
            commitSHA: nil,
            startedAt: nil,
            completedAt: nil,
            errorMessage: nil
        )

        XCTAssertEqual(CombinedStatus.reduce([running, failed]), .running)
        XCTAssertEqual(CombinedStatus.reduce([failed, success]), .failed)
        XCTAssertEqual(CombinedStatus.reduce([unknown, success]), .success)
        XCTAssertEqual(CombinedStatus.reduce([unknown]), .unknown)
    }
}
