import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

protocol WorkflowRunFetching: Sendable {
    func fetchLatestRun(for workflow: MonitoredWorkflow, token: String?) async throws -> WorkflowRun?
}

protocol GitHubDataFetching: WorkflowRunFetching {
    func fetchViewer(accessToken: String) async throws -> GitHubUserProfile
    func fetchInstallations(accessToken: String) async throws -> [GitHubInstallationSummary]
    func fetchRepositories(
        for installationID: Int64,
        accessToken: String
    ) async throws -> [GitHubAccessibleRepositorySummary]
    func fetchWorkflows(
        owner: String,
        repo: String,
        accessToken: String
    ) async throws -> [GitHubWorkflowSummary]
    func fetchJobs(
        owner: String,
        repo: String,
        runID: Int64,
        accessToken: String
    ) async throws -> [GitHubWorkflowJob]
    func fetchJob(
        owner: String,
        repo: String,
        jobID: Int64,
        accessToken: String
    ) async throws -> GitHubWorkflowJob
}

enum GitHubClientError: LocalizedError {
    case invalidResponse
    case unauthorized
    case rateLimited(resetAt: Date?)
    case unexpectedStatus(code: Int, message: String?)
    case decodingFailed
    case network(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "GitHub returned an invalid response."
        case .unauthorized:
            return "GitHub rejected the saved session. Connect GitHub again in Settings."
        case .rateLimited(let resetAt):
            if let resetAt {
                return "GitHub rate limit reached until \(resetAt.formatted(date: .omitted, time: .shortened))."
            }

            return "GitHub rate limit reached."
        case .unexpectedStatus(let code, let message):
            if let message, !message.isEmpty {
                return "GitHub request failed (\(code)): \(message)"
            }

            return "GitHub request failed with status \(code)."
        case .decodingFailed:
            return "GitHub returned data in an unexpected format."
        case .network(let message):
            return "Network error: \(message)"
        }
    }
}

struct GitHubWorkflowSummary: Decodable, Equatable, Identifiable, Sendable {
    let id: Int64
    let name: String
    let path: String
    let state: String
}

struct WorkflowRun: Decodable, Equatable, Sendable {
    let id: Int64?
    let htmlURL: URL?
    let status: String
    let conclusion: String?
    let headSHA: String?
    let createdAt: Date?
    let updatedAt: Date?
    let runStartedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case htmlURL = "html_url"
        case status
        case conclusion
        case headSHA = "head_sha"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case runStartedAt = "run_started_at"
    }

    init(
        id: Int64? = nil,
        htmlURL: URL?,
        status: String,
        conclusion: String?,
        headSHA: String?,
        createdAt: Date?,
        updatedAt: Date?,
        runStartedAt: Date?
    ) {
        self.id = id
        self.htmlURL = htmlURL
        self.status = status
        self.conclusion = conclusion
        self.headSHA = headSHA
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.runStartedAt = runStartedAt
    }

    func deployState(for workflow: MonitoredWorkflow) -> DeployState {
        let normalizedStatus = normalizedDeployStatus
        let statusText: String

        switch normalizedStatus {
        case .running:
            statusText = "Deploy running"
        case .success:
            statusText = "Deploy succeeded"
        case .failed:
            statusText = "Deploy \(humanizedConclusion ?? "failed")"
        case .unknown:
            statusText = "Status unavailable"
        }

        return DeployState(
            workflow: workflow,
            status: normalizedStatus,
            statusText: statusText,
            runURL: htmlURL,
            commitSHA: headSHA,
            startedAt: runStartedAt ?? createdAt,
            completedAt: normalizedStatus == .running ? nil : updatedAt,
            errorMessage: nil
        )
    }

    var normalizedDeployStatus: DeployStatus {
        if status.lowercased() != "completed" {
            return .running
        }

        if conclusion?.lowercased() == "success" {
            return .success
        }

        return .failed
    }

    private var humanizedConclusion: String? {
        guard let conclusion else {
            return nil
        }

        return conclusion
            .replacingOccurrences(of: "_", with: " ")
            .lowercased()
    }
}

struct GitHubWorkflowJob: Decodable, Equatable, Identifiable, Sendable {
    let id: Int64
    let runID: Int64
    let htmlURL: URL?
    let status: String
    let conclusion: String?
    let startedAt: Date?
    let completedAt: Date?
    let name: String
    let workflowName: String?
    let headBranch: String?

    enum CodingKeys: String, CodingKey {
        case id
        case runID = "run_id"
        case htmlURL = "html_url"
        case status
        case conclusion
        case startedAt = "started_at"
        case completedAt = "completed_at"
        case name
        case workflowName = "workflow_name"
        case headBranch = "head_branch"
    }
}

struct GitHubClient: GitHubDataFetching {
    static let apiVersion = "2026-03-10"
    static let userAgent = "actionMonitor"

    let session: URLSession
    let baseURL: URL
    private let decoder: JSONDecoder

    init(
        session: URLSession = .shared,
        baseURL: URL = URL(string: "https://api.github.com")!
    ) {
        self.session = session
        self.baseURL = baseURL

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    func fetchViewer(accessToken: String) async throws -> GitHubUserProfile {
        let request = try authorizedRequest(path: "/user", accessToken: accessToken)
        return try await decode(request, as: GitHubUserProfile.self)
    }

    func fetchInstallations(accessToken: String) async throws -> [GitHubInstallationSummary] {
        let request = try authorizedRequest(path: "/user/installations", accessToken: accessToken)
        let response = try await decode(request, as: GitHubInstallationsResponse.self)
        return response.installations.map(\.summary)
    }

    func fetchRepositories(
        for installationID: Int64,
        accessToken: String
    ) async throws -> [GitHubAccessibleRepositorySummary] {
        let request = try authorizedRequest(
            path: "/user/installations/\(installationID)/repositories",
            accessToken: accessToken
        )
        let response = try await decode(request, as: GitHubInstallationRepositoriesResponse.self)
        return response.repositories.map { $0.summary(installationID: installationID) }
    }

    func fetchWorkflows(
        owner: String,
        repo: String,
        accessToken: String
    ) async throws -> [GitHubWorkflowSummary] {
        let request = try authorizedRequest(
            path: "/repos/\(owner)/\(repo)/actions/workflows",
            accessToken: accessToken
        )
        let response = try await decode(request, as: GitHubWorkflowsResponse.self)
        return response.workflows
    }

    func fetchLatestRun(for workflow: MonitoredWorkflow, token: String?) async throws -> WorkflowRun? {
        do {
            let request = try latestRunRequest(for: workflow, token: token)
            let response = try await decode(request, as: WorkflowRunsResponse.self)
            return response.workflowRuns.first
        } catch let error as GitHubClientError {
            throw error
        } catch {
            throw GitHubClientError.network(error.localizedDescription)
        }
    }

    func fetchJobs(
        owner: String,
        repo: String,
        runID: Int64,
        accessToken: String
    ) async throws -> [GitHubWorkflowJob] {
        let request = try authorizedRequest(
            path: "/repos/\(owner)/\(repo)/actions/runs/\(runID)/jobs",
            accessToken: accessToken
        )
        let response = try await decode(request, as: GitHubWorkflowJobsResponse.self)
        return response.jobs
    }

    func fetchJob(
        owner: String,
        repo: String,
        jobID: Int64,
        accessToken: String
    ) async throws -> GitHubWorkflowJob {
        let request = try authorizedRequest(
            path: "/repos/\(owner)/\(repo)/actions/jobs/\(jobID)",
            accessToken: accessToken
        )
        return try await decode(request, as: GitHubWorkflowJob.self)
    }

    func latestRunRequest(for workflow: MonitoredWorkflow, token: String?) throws -> URLRequest {
        var components = URLComponents(
            url: baseURL.appending(path: "/repos/\(workflow.owner)/\(workflow.repo)/actions/workflows/\(workflow.workflowFile)/runs"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "branch", value: workflow.branch),
            URLQueryItem(name: "event", value: "push"),
            URLQueryItem(name: "per_page", value: "1"),
        ]

        guard let url = components?.url else {
            throw GitHubClientError.invalidResponse
        }

        return makeRequest(url: url, accessToken: token)
    }

    private func authorizedRequest(path: String, accessToken: String) throws -> URLRequest {
        let url = baseURL.appending(path: path)
        return makeRequest(url: url, accessToken: accessToken)
    }

    private func makeRequest(url: URL, accessToken: String?) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue(GitHubClient.apiVersion, forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue(GitHubClient.userAgent, forHTTPHeaderField: "User-Agent")

        if let accessToken,
           !accessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        }

        return request
    }

    private func decode<T: Decodable>(_ request: URLRequest, as type: T.Type) async throws -> T {
        let data = try await perform(request)

        do {
            return try decoder.decode(type, from: data)
        } catch {
            throw GitHubClientError.decodingFailed
        }
    }

    private func perform(_ request: URLRequest) async throws -> Data {
        do {
            let (data, response) = try await session.data(for: request)

            guard let response = response as? HTTPURLResponse else {
                throw GitHubClientError.invalidResponse
            }

            switch response.statusCode {
            case 200:
                return data
            case 401:
                throw GitHubClientError.unauthorized
            case 403:
                if response.value(forHTTPHeaderField: "x-ratelimit-remaining") == "0" {
                    let resetAt = response.value(forHTTPHeaderField: "x-ratelimit-reset")
                        .flatMap(TimeInterval.init)
                        .map(Date.init(timeIntervalSince1970:))
                    throw GitHubClientError.rateLimited(resetAt: resetAt)
                }

                let message = try? decoder.decode(GitHubAPIError.self, from: data).message
                throw GitHubClientError.unexpectedStatus(code: 403, message: message)
            default:
                let message = try? decoder.decode(GitHubAPIError.self, from: data).message
                throw GitHubClientError.unexpectedStatus(code: response.statusCode, message: message)
            }
        } catch let error as GitHubClientError {
            throw error
        } catch {
            throw GitHubClientError.network(error.localizedDescription)
        }
    }
}

private struct GitHubInstallationsResponse: Decodable {
    let installations: [GitHubInstallationPayload]
}

private struct GitHubInstallationPayload: Decodable {
    let id: Int64
    let account: GitHubAccountPayload
    let targetType: String?
    let repositorySelection: String?

    enum CodingKeys: String, CodingKey {
        case id
        case account
        case targetType = "target_type"
        case repositorySelection = "repository_selection"
    }

    var summary: GitHubInstallationSummary {
        GitHubInstallationSummary(
            id: id,
            accountLogin: account.login,
            accountType: account.type,
            targetType: targetType ?? account.type,
            repositorySelection: repositorySelection ?? "selected"
        )
    }
}

private struct GitHubInstallationRepositoriesResponse: Decodable {
    let repositories: [GitHubRepositoryPayload]
}

private struct GitHubRepositoryPayload: Decodable {
    let id: Int64
    let name: String
    let fullName: String
    let owner: GitHubAccountPayload
    let isPrivate: Bool
    let defaultBranch: String?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case fullName = "full_name"
        case owner
        case isPrivate = "private"
        case defaultBranch = "default_branch"
    }

    func summary(installationID: Int64) -> GitHubAccessibleRepositorySummary {
        GitHubAccessibleRepositorySummary(
            id: id,
            installationID: installationID,
            ownerLogin: owner.login,
            name: name,
            fullName: fullName,
            isPrivate: isPrivate,
            defaultBranch: defaultBranch
        )
    }
}

private struct GitHubAccountPayload: Decodable {
    let login: String
    let type: String
}

private struct GitHubWorkflowsResponse: Decodable {
    let workflows: [GitHubWorkflowSummary]
}

private struct WorkflowRunsResponse: Decodable, Sendable {
    let workflowRuns: [WorkflowRun]

    enum CodingKeys: String, CodingKey {
        case workflowRuns = "workflow_runs"
    }
}

private struct GitHubWorkflowJobsResponse: Decodable {
    let jobs: [GitHubWorkflowJob]
}

struct GitHubAPIError: Decodable {
    let message: String
}
