import Foundation

struct DemoWorkflowRunFetcher: WorkflowRunFetching {
    func fetchLatestRun(for site: SiteConfig, token: String?) async throws -> WorkflowRun? {
        let now = Date()

        if site.repo.contains("betreuung") {
            return WorkflowRun(
                htmlURL: site.workflowURL,
                status: "completed",
                conclusion: "success",
                headSHA: "0123456789abcdef",
                createdAt: now.addingTimeInterval(-900),
                updatedAt: now.addingTimeInterval(-600),
                runStartedAt: now.addingTimeInterval(-870)
            )
        }

        return WorkflowRun(
            htmlURL: site.workflowURL,
            status: "completed",
            conclusion: "success",
            headSHA: "fedcba9876543210",
            createdAt: now.addingTimeInterval(-480),
            updatedAt: now.addingTimeInterval(-360),
            runStartedAt: now.addingTimeInterval(-450)
        )
    }
}
