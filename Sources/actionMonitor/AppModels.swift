import Foundation

struct MonitoredWorkflow: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    let displayName: String
    let owner: String
    let repo: String
    let branch: String
    let workflowFile: String
    let siteURL: URL?

    init(
        id: UUID = UUID(),
        displayName: String,
        owner: String,
        repo: String,
        branch: String,
        workflowFile: String,
        siteURL: URL?
    ) {
        self.id = id
        self.displayName = displayName
        self.owner = owner
        self.repo = repo
        self.branch = branch
        self.workflowFile = workflowFile
        self.siteURL = siteURL
    }

    var workflowURL: URL {
        URL(string: "https://github.com/\(owner)/\(repo)/actions/workflows/\(workflowFile)")!
    }

    fileprivate var duplicateKey: MonitoredWorkflowDuplicateKey {
        MonitoredWorkflowDuplicateKey(
            owner: owner,
            repo: repo,
            branch: branch,
            workflowFile: workflowFile
        )
    }

    static let demoWorkflows: [MonitoredWorkflow] = [
        MonitoredWorkflow(
            id: UUID(uuidString: "55B01DF4-6656-4613-BF68-29BD5EB6E0E7")!,
            displayName: "Example Marketing Site",
            owner: "octo-org",
            repo: "marketing-site",
            branch: "main",
            workflowFile: "deploy.yml",
            siteURL: URL(string: "https://example.com")
        ),
        MonitoredWorkflow(
            id: UUID(uuidString: "2E24C247-66D0-4E72-AE0A-38315CA55B44")!,
            displayName: "Customer Dashboard",
            owner: "octo-org",
            repo: "dashboard",
            branch: "release",
            workflowFile: ".github/workflows/release.yml",
            siteURL: URL(string: "https://dashboard.example.com")
        ),
    ]
}

private struct MonitoredWorkflowDuplicateKey: Hashable {
    let owner: String
    let repo: String
    let branch: String
    let workflowFile: String

    init(owner: String, repo: String, branch: String, workflowFile: String) {
        self.owner = owner.normalizedWorkflowValue
        self.repo = repo.normalizedWorkflowValue
        self.branch = branch.normalizedWorkflowValue
        self.workflowFile = workflowFile.normalizedWorkflowValue
    }
}

struct MonitoredWorkflowDraft: Equatable, Sendable {
    var displayName: String = ""
    var owner: String = ""
    var repo: String = ""
    var branch: String = "main"
    var workflowFile: String = ""
    var siteURLText: String = ""

    init() {}

    init(
        displayName: String,
        owner: String,
        repo: String,
        branch: String,
        workflowFile: String,
        siteURLText: String
    ) {
        self.displayName = displayName
        self.owner = owner
        self.repo = repo
        self.branch = branch
        self.workflowFile = workflowFile
        self.siteURLText = siteURLText
    }

    init(workflow: MonitoredWorkflow) {
        displayName = workflow.displayName
        owner = workflow.owner
        repo = workflow.repo
        branch = workflow.branch
        workflowFile = workflow.workflowFile
        siteURLText = workflow.siteURL?.absoluteString ?? ""
    }

    func validated(
        existingWorkflows: [MonitoredWorkflow],
        editingID: UUID? = nil
    ) throws -> MonitoredWorkflow {
        let trimmedOwner = owner.trimmedWorkflowValue
        let trimmedRepo = repo.trimmedWorkflowValue
        let trimmedBranch = branch.trimmedWorkflowValue
        let trimmedWorkflowFile = workflowFile.trimmedWorkflowValue

        guard !trimmedOwner.isEmpty else {
            throw MonitoredWorkflowValidationError.ownerRequired
        }

        guard !trimmedRepo.isEmpty else {
            throw MonitoredWorkflowValidationError.repoRequired
        }

        guard !trimmedBranch.isEmpty else {
            throw MonitoredWorkflowValidationError.branchRequired
        }

        guard !trimmedWorkflowFile.isEmpty else {
            throw MonitoredWorkflowValidationError.workflowFileRequired
        }

        let duplicateKey = MonitoredWorkflowDuplicateKey(
            owner: trimmedOwner,
            repo: trimmedRepo,
            branch: trimmedBranch,
            workflowFile: trimmedWorkflowFile
        )

        if existingWorkflows.contains(where: { workflow in
            workflow.id != editingID && workflow.duplicateKey == duplicateKey
        }) {
            throw MonitoredWorkflowValidationError.duplicateWorkflow
        }

        let trimmedDisplayName = displayName.trimmedWorkflowValue
        let resolvedSiteURL: URL?
        let trimmedSiteURLText = siteURLText.trimmedWorkflowValue

        if trimmedSiteURLText.isEmpty {
            resolvedSiteURL = nil
        } else if let candidateURL = URL(string: trimmedSiteURLText),
                  candidateURL.scheme?.lowercased() == "https",
                  candidateURL.host?.isEmpty == false {
            resolvedSiteURL = candidateURL
        } else {
            throw MonitoredWorkflowValidationError.invalidSiteURL
        }

        return MonitoredWorkflow(
            id: editingID ?? UUID(),
            displayName: trimmedDisplayName.isEmpty ? trimmedRepo : trimmedDisplayName,
            owner: trimmedOwner,
            repo: trimmedRepo,
            branch: trimmedBranch,
            workflowFile: trimmedWorkflowFile,
            siteURL: resolvedSiteURL
        )
    }
}

enum MonitoredWorkflowValidationError: LocalizedError, Equatable {
    case ownerRequired
    case repoRequired
    case branchRequired
    case workflowFileRequired
    case invalidSiteURL
    case duplicateWorkflow

    var errorDescription: String? {
        switch self {
        case .ownerRequired:
            return "Enter the GitHub owner or organization."
        case .repoRequired:
            return "Enter the repository name."
        case .branchRequired:
            return "Enter the branch to monitor."
        case .workflowFileRequired:
            return "Enter the workflow file name or path."
        case .invalidSiteURL:
            return "Site URL must be a valid https URL."
        case .duplicateWorkflow:
            return "That workflow is already being monitored."
        }
    }
}

enum DeployStatus: String, CaseIterable, Equatable, Sendable {
    case running
    case failed
    case success
    case unknown
}

struct DeployState: Identifiable, Equatable, Sendable {
    let workflow: MonitoredWorkflow
    var status: DeployStatus
    var statusText: String
    var runURL: URL?
    var commitSHA: String?
    var startedAt: Date?
    var completedAt: Date?
    var errorMessage: String?

    var id: UUID {
        workflow.id
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

    var detailsLinkTitle: String {
        guard let runURL else {
            return "Open run"
        }

        return runURL.path.contains("/actions/workflows/") ? "Open workflow" : "Open run"
    }

    static func placeholder(for workflow: MonitoredWorkflow) -> DeployState {
        DeployState(
            workflow: workflow,
            status: .unknown,
            statusText: "Checking deploy status",
            runURL: nil,
            commitSHA: nil,
            startedAt: nil,
            completedAt: nil,
            errorMessage: nil
        )
    }

    static func unknown(for workflow: MonitoredWorkflow, message: String) -> DeployState {
        DeployState(
            workflow: workflow,
            status: .unknown,
            statusText: "Status unavailable",
            runURL: nil,
            commitSHA: nil,
            startedAt: nil,
            completedAt: nil,
            errorMessage: message
        )
    }

    func updatingWorkflow(_ workflow: MonitoredWorkflow) -> DeployState {
        DeployState(
            workflow: workflow,
            status: status,
            statusText: statusText,
            runURL: runURL,
            commitSHA: commitSHA,
            startedAt: startedAt,
            completedAt: completedAt,
            errorMessage: errorMessage
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

private extension String {
    var trimmedWorkflowValue: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var normalizedWorkflowValue: String {
        trimmedWorkflowValue.lowercased()
    }
}
