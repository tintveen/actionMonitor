import XCTest
@testable import actionMonitor

final class DemoWorkflowRunFetcherTests: XCTestCase {
    func testDemoRunUsesWorkflowURLInsteadOfFakeRunURL() async throws {
        let fetcher = DemoWorkflowRunFetcher()
        let workflow = MonitoredWorkflow.demoWorkflows[0]

        let run = try await fetcher.fetchLatestRun(for: workflow, token: nil)

        XCTAssertEqual(run?.normalizedDeployStatus, .success)
        XCTAssertEqual(run?.htmlURL, workflow.workflowURL)
    }

    func testSecondDemoWorkflowShowsRunningState() async throws {
        let fetcher = DemoWorkflowRunFetcher()
        let workflow = MonitoredWorkflow.demoWorkflows[1]

        let run = try await fetcher.fetchLatestRun(for: workflow, token: nil)

        XCTAssertEqual(run?.normalizedDeployStatus, .running)
        XCTAssertEqual(run?.htmlURL, workflow.workflowURL)
    }
}
