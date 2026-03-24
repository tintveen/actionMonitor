import Foundation

struct DemoWorkflowRunFetcher: GitHubDataFetching {
    func fetchViewer(accessToken: String) async throws -> GitHubUserProfile {
        GitHubUserProfile(id: 1, login: "octocat")
    }

    func fetchInstallations(accessToken: String) async throws -> [GitHubInstallationSummary] {
        [
            GitHubInstallationSummary(
                id: 1,
                accountLogin: "octo-org",
                accountType: "Organization",
                targetType: "Organization",
                repositorySelection: "selected"
            )
        ]
    }

    func fetchRepositories(
        for installationID: Int64,
        accessToken: String
    ) async throws -> [GitHubAccessibleRepositorySummary] {
        [
            GitHubAccessibleRepositorySummary(
                id: 101,
                installationID: installationID,
                ownerLogin: "octo-org",
                name: "marketing-site",
                fullName: "octo-org/marketing-site",
                isPrivate: true,
                defaultBranch: "main"
            ),
            GitHubAccessibleRepositorySummary(
                id: 102,
                installationID: installationID,
                ownerLogin: "octo-org",
                name: "dashboard",
                fullName: "octo-org/dashboard",
                isPrivate: true,
                defaultBranch: "release"
            ),
        ]
    }

    func fetchWorkflows(
        owner: String,
        repo: String,
        accessToken: String
    ) async throws -> [GitHubWorkflowSummary] {
        [
            GitHubWorkflowSummary(id: 201, name: "Deploy", path: ".github/workflows/deploy.yml", state: "active")
        ]
    }

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

    func fetchJobs(
        owner: String,
        repo: String,
        runID: Int64,
        accessToken: String
    ) async throws -> [GitHubWorkflowJob] {
        []
    }

    func fetchJob(
        owner: String,
        repo: String,
        jobID: Int64,
        accessToken: String
    ) async throws -> GitHubWorkflowJob {
        GitHubWorkflowJob(
            id: jobID,
            runID: 1,
            htmlURL: nil,
            status: "completed",
            conclusion: "success",
            startedAt: Date(),
            completedAt: Date(),
            name: "deploy",
            workflowName: "Deploy",
            headBranch: "main"
        )
    }
}
