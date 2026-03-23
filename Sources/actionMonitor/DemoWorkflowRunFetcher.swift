import Foundation

struct DemoWorkflowRunFetcher: WorkflowRunFetching {
    func fetchLatestRun(for workflow: MonitoredWorkflow, token: String?) async throws -> WorkflowRun? {
        let now = Date()

        if workflow.repo.contains("marketing") {
            return WorkflowRun(
                htmlURL: workflow.workflowURL,
                status: "completed",
                conclusion: "success",
                headSHA: "0123456789abcdef",
                createdAt: now.addingTimeInterval(-900),
                updatedAt: now.addingTimeInterval(-600),
                runStartedAt: now.addingTimeInterval(-870)
            )
        }

        return WorkflowRun(
            htmlURL: workflow.workflowURL,
            status: "in_progress",
            conclusion: nil,
            headSHA: "fedcba9876543210",
            createdAt: now.addingTimeInterval(-480),
            updatedAt: now.addingTimeInterval(-120),
            runStartedAt: now.addingTimeInterval(-450)
        )
    }
}
