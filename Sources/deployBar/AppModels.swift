import Foundation

struct SiteConfig: Identifiable, Hashable, Sendable {
    let id: String
    let displayName: String
    let owner: String
    let repo: String
    let branch: String
    let workflowFile: String
    let siteURL: URL

    init(
        displayName: String,
        owner: String,
        repo: String,
        branch: String,
        workflowFile: String,
        siteURL: URL
    ) {
        self.id = "\(owner)/\(repo)"
        self.displayName = displayName
        self.owner = owner
        self.repo = repo
        self.branch = branch
        self.workflowFile = workflowFile
        self.siteURL = siteURL
    }

    static let monitoredSites: [SiteConfig] = [
        SiteConfig(
            displayName: "betreuung-uebach.de",
            owner: "tintveen",
            repo: "betreuung-uebach.de",
            branch: "main",
            workflowFile: "deploy.yml",
            siteURL: URL(string: "https://betreuung-uebach.de")!
        ),
        SiteConfig(
            displayName: "tintveen.com",
            owner: "tintveen",
            repo: "tintveen.com",
            branch: "master",
            workflowFile: "deploy.yml",
            siteURL: URL(string: "https://tintveen.com")!
        ),
    ]
}

enum DeployStatus: String, CaseIterable, Equatable, Sendable {
    case running
    case failed
    case success
    case unknown
}

struct DeployState: Identifiable, Equatable, Sendable {
    let site: SiteConfig
    var status: DeployStatus
    var statusText: String
    var runURL: URL?
    var commitSHA: String?
    var startedAt: Date?
    var completedAt: Date?
    var errorMessage: String?

    var id: String {
        site.id
    }

    var shortCommitSHA: String? {
        guard let commitSHA else {
            return nil
        }

        return String(commitSHA.prefix(7))
    }

    var relevantTimestamp: Date? {
        completedAt ?? startedAt
    }

    static func placeholder(for site: SiteConfig) -> DeployState {
        DeployState(
            site: site,
            status: .unknown,
            statusText: "Checking deploy status",
            runURL: nil,
            commitSHA: nil,
            startedAt: nil,
            completedAt: nil,
            errorMessage: nil
        )
    }

    static func unknown(for site: SiteConfig, message: String) -> DeployState {
        DeployState(
            site: site,
            status: .unknown,
            statusText: "Status unavailable",
            runURL: nil,
            commitSHA: nil,
            startedAt: nil,
            completedAt: nil,
            errorMessage: message
        )
    }
}

enum CombinedStatus {
    static func reduce(_ states: [DeployState]) -> DeployStatus {
        if states.contains(where: { $0.status == .running }) {
            return .running
        }

        if states.contains(where: { $0.status == .failed }) {
            return .failed
        }

        if states.contains(where: { $0.status == .success }) {
            return .success
        }

        return .unknown
    }
}
