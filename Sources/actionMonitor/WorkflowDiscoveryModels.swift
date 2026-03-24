import Foundation

struct DiscoveredWorkflowSuggestion: Identifiable, Equatable, Sendable {
    let owner: String
    let repo: String
    let repoFullName: String
    let branch: String
    let workflowID: Int64?
    let workflowName: String
    let workflowFile: String
    let workflowState: String
    var isSelected: Bool
    var isAlreadyMonitored: Bool

    var id: String {
        monitorIdentity.stableIdentifier
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

    var displayName: String {
        let trimmedName = workflowName.trimmedWorkflowValue
        return trimmedName.isEmpty ? workflowFile.workflowFileDisplayName : trimmedName
    }

    var isActive: Bool {
        workflowState.normalizedWorkflowValue == "active"
    }

    var isSelectable: Bool {
        !isAlreadyMonitored
    }

    var statusLabel: String? {
        if isAlreadyMonitored {
            return "Already added"
        }

        if !isActive {
            return "Not active on GitHub"
        }

        return nil
    }

    func asMonitoredWorkflow() -> MonitoredWorkflow {
        MonitoredWorkflow(
            displayName: displayName,
            owner: owner,
            repo: repo,
            branch: branch,
            workflowID: workflowID,
            workflowFile: workflowFile,
            siteURL: nil
        )
    }
}

extension WorkflowIdentity {
    var stableIdentifier: String {
        [
            owner,
            repo,
            workflowID.map(String.init) ?? workflowFile,
        ].joined(separator: "|")
    }
}

extension MonitorIdentity {
    var stableIdentifier: String {
        [
            workflowIdentity.stableIdentifier,
            branch,
        ].joined(separator: "|")
    }
}
