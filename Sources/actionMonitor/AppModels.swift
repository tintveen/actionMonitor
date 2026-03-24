import Foundation

struct MonitoredWorkflow: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    let displayName: String
    let owner: String
    let repo: String
    let branch: String
    let workflowID: Int64?
    let workflowFile: String
    let siteURL: URL?

    init(
        id: UUID = UUID(),
        displayName: String,
        owner: String,
        repo: String,
        branch: String,
        workflowID: Int64? = nil,
        workflowFile: String,
        siteURL: URL?
    ) {
        self.id = id
        self.displayName = displayName
        self.owner = owner
        self.repo = repo
        self.branch = branch.normalizedMonitorBranchValue
        self.workflowID = workflowID
        self.workflowFile = workflowFile
        self.siteURL = siteURL
    }

    var workflowReference: String {
        workflowID.map(String.init) ?? workflowFile
    }

    var workflowURL: URL {
        URL(string: "https://github.com/\(owner)/\(repo)/actions/workflows/\(workflowReference)")!
    }

    var workflowIdentity: WorkflowIdentity {
        WorkflowIdentity(
            owner: owner,
            repo: repo,
            workflowID: workflowID,
            workflowFile: workflowFile
        )
    }

    var monitorIdentity: MonitorIdentity {
        MonitorIdentity(
            owner: owner,
            repo: repo,
            branch: branch,
            workflowID: workflowID,
            workflowFile: workflowFile
        )
    }

    func matchesMonitor(
        owner: String,
        repo: String,
        branch: String,
        workflowID: Int64?,
        workflowFile: String
    ) -> Bool {
        guard self.owner.normalizedWorkflowValue == owner.normalizedWorkflowValue,
              self.repo.normalizedWorkflowValue == repo.normalizedWorkflowValue,
              self.branch.normalizedMonitorBranchValue == branch.normalizedMonitorBranchValue else {
            return false
        }

        if let existingWorkflowID = self.workflowID,
           let workflowID {
            return existingWorkflowID == workflowID
        }

        return self.workflowFile.normalizedWorkflowValue == workflowFile.normalizedWorkflowValue
    }

    func preservingWorkflowID(
        displayName: String,
        owner: String,
        repo: String,
        branch: String,
        workflowFile: String,
        siteURL: URL?
    ) -> MonitoredWorkflow {
        let preservesWorkflowIdentity =
            self.owner.normalizedWorkflowValue == owner.normalizedWorkflowValue &&
            self.repo.normalizedWorkflowValue == repo.normalizedWorkflowValue &&
            self.workflowFile.normalizedWorkflowValue == workflowFile.normalizedWorkflowValue

        return MonitoredWorkflow(
            id: id,
            displayName: displayName,
            owner: owner,
            repo: repo,
            branch: branch,
            workflowID: preservesWorkflowIdentity ? workflowID : nil,
            workflowFile: workflowFile,
            siteURL: siteURL
        )
    }

    static let demoWorkflows: [MonitoredWorkflow] = [
        MonitoredWorkflow(
            id: UUID(uuidString: "55B01DF4-6656-4613-BF68-29BD5EB6E0E7")!,
            displayName: "Example Marketing Site",
            owner: "octo-org",
            repo: "marketing-site",
            branch: "main",
            workflowID: 201,
            workflowFile: "deploy.yml",
            siteURL: URL(string: "https://example.com")
        ),
        MonitoredWorkflow(
            id: UUID(uuidString: "2E24C247-66D0-4E72-AE0A-38315CA55B44")!,
            displayName: "Customer Dashboard",
            owner: "octo-org",
            repo: "dashboard",
            branch: "release",
            workflowID: 202,
            workflowFile: ".github/workflows/release.yml",
            siteURL: URL(string: "https://dashboard.example.com")
        ),
    ]
}

struct WorkflowIdentity: Hashable, Sendable {
    let owner: String
    let repo: String
    let workflowID: Int64?
    let workflowFile: String

    init(owner: String, repo: String, workflowID: Int64?, workflowFile: String) {
        self.owner = owner.normalizedWorkflowValue
        self.repo = repo.normalizedWorkflowValue
        self.workflowID = workflowID
        self.workflowFile = workflowID == nil ? workflowFile.normalizedWorkflowValue : ""
    }
}

struct MonitorIdentity: Hashable, Sendable {
    let workflowIdentity: WorkflowIdentity
    let branch: String

    init(owner: String, repo: String, branch: String, workflowID: Int64?, workflowFile: String) {
        workflowIdentity = WorkflowIdentity(
            owner: owner,
            repo: repo,
            workflowID: workflowID,
            workflowFile: workflowFile
        )
        self.branch = branch.normalizedMonitorBranchValue
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
        editingWorkflow: MonitoredWorkflow? = nil
    ) throws -> MonitoredWorkflow {
        let trimmedOwner = owner.trimmedWorkflowValue
        let trimmedRepo = repo.trimmedWorkflowValue
        let normalizedBranch = branch.normalizedMonitorBranchValue
        let trimmedWorkflowFile = workflowFile.trimmedWorkflowValue

        guard !trimmedOwner.isEmpty else {
            throw MonitoredWorkflowValidationError.ownerRequired
        }

        guard !trimmedRepo.isEmpty else {
            throw MonitoredWorkflowValidationError.repoRequired
        }

        guard !normalizedBranch.isEmpty else {
            throw MonitoredWorkflowValidationError.branchRequired
        }

        guard !trimmedWorkflowFile.isEmpty else {
            throw MonitoredWorkflowValidationError.workflowFileRequired
        }

        let preservedWorkflowID = editingWorkflow.flatMap { workflow in
            workflow.owner.normalizedWorkflowValue == trimmedOwner.normalizedWorkflowValue &&
            workflow.repo.normalizedWorkflowValue == trimmedRepo.normalizedWorkflowValue &&
            workflow.workflowFile.normalizedWorkflowValue == trimmedWorkflowFile.normalizedWorkflowValue
                ? workflow.workflowID
                : nil
        }

        if existingWorkflows.contains(where: { workflow in
            workflow.id != editingWorkflow?.id &&
            workflow.matchesMonitor(
                owner: trimmedOwner,
                repo: trimmedRepo,
                branch: normalizedBranch,
                workflowID: preservedWorkflowID,
                workflowFile: trimmedWorkflowFile
            )
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

        if let editingWorkflow {
            return editingWorkflow.preservingWorkflowID(
                displayName: trimmedDisplayName.isEmpty ? trimmedRepo : trimmedDisplayName,
                owner: trimmedOwner,
                repo: trimmedRepo,
                branch: normalizedBranch,
                workflowFile: trimmedWorkflowFile,
                siteURL: resolvedSiteURL
            )
        }

        return MonitoredWorkflow(
            displayName: trimmedDisplayName.isEmpty ? trimmedRepo : trimmedDisplayName,
            owner: trimmedOwner,
            repo: trimmedRepo,
            branch: normalizedBranch,
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

extension String {
    var trimmedWorkflowValue: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var normalizedWorkflowValue: String {
        trimmedWorkflowValue.lowercased()
    }

    var normalizedMonitorBranchValue: String {
        trimmedWorkflowValue.lowercased()
    }

    var workflowFileDisplayName: String {
        let trimmedValue = trimmedWorkflowValue
        guard !trimmedValue.isEmpty else {
            return trimmedValue
        }

        let lastPathComponent = (trimmedValue as NSString).lastPathComponent
        return lastPathComponent.isEmpty ? trimmedValue : lastPathComponent
    }
}
