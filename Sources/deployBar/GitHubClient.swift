import Foundation

protocol WorkflowRunFetching: Sendable {
    func fetchLatestRun(for site: SiteConfig, token: String?) async throws -> WorkflowRun?
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
            return "GitHub rejected the request. Update the token in Settings."
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

struct WorkflowRunsResponse: Decodable, Sendable {
    let workflowRuns: [WorkflowRun]

    enum CodingKeys: String, CodingKey {
        case workflowRuns = "workflow_runs"
    }
}

struct WorkflowRun: Decodable, Equatable, Sendable {
    let htmlURL: URL?
    let status: String
    let conclusion: String?
    let headSHA: String?
    let createdAt: Date?
    let updatedAt: Date?
    let runStartedAt: Date?

    enum CodingKeys: String, CodingKey {
        case htmlURL = "html_url"
        case status
        case conclusion
        case headSHA = "head_sha"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case runStartedAt = "run_started_at"
    }

    func deployState(for site: SiteConfig) -> DeployState {
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
            site: site,
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

struct GitHubClient: WorkflowRunFetching {
    static let apiVersion = "2026-03-10"

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

    func latestRunRequest(for site: SiteConfig, token: String?) throws -> URLRequest {
        var components = URLComponents(
            url: baseURL.appending(path: "/repos/\(site.owner)/\(site.repo)/actions/workflows/\(site.workflowFile)/runs"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "branch", value: site.branch),
            URLQueryItem(name: "event", value: "push"),
            URLQueryItem(name: "per_page", value: "1"),
        ]

        guard let url = components?.url else {
            throw GitHubClientError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue(GitHubClient.apiVersion, forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("deployBar", forHTTPHeaderField: "User-Agent")

        if let token, !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        return request
    }

    func fetchLatestRun(for site: SiteConfig, token: String?) async throws -> WorkflowRun? {
        do {
            let request = try latestRunRequest(for: site, token: token)
            let (data, response) = try await session.data(for: request)

            guard let response = response as? HTTPURLResponse else {
                throw GitHubClientError.invalidResponse
            }

            switch response.statusCode {
            case 200:
                do {
                    return try decoder.decode(WorkflowRunsResponse.self, from: data).workflowRuns.first
                } catch {
                    throw GitHubClientError.decodingFailed
                }
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

private struct GitHubAPIError: Decodable {
    let message: String
}
