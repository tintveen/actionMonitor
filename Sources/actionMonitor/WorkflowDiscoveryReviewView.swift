#if canImport(AppKit) && canImport(SwiftUI)
import AppKit
import SwiftUI

struct WorkflowDiscoveryReviewView: View {
    @ObservedObject var store: StatusStore
    let addButtonTitle: String
    let onAddSelected: () -> Void
    let manualActionTitle: String?
    let manualAction: (() -> Void)?
    let zeroSelectionActionTitle: String?
    let zeroSelectionAction: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let workflowDiscoveryMessage = store.workflowDiscoveryMessage {
                DiscoveryInlineMessageView(
                    systemImage: "info.circle.fill",
                    message: workflowDiscoveryMessage,
                    tint: .blue
                )
            }

            if store.isDiscoveringWorkflows && store.discoveredWorkflowSuggestions.isEmpty {
                ProgressView("Discovering workflows…")
            } else if !store.canDiscoverWorkflows {
                discoveryEmptyState(
                    title: "Workflow discovery needs GitHub browser sign-in",
                    description: "Connect GitHub with the browser flow to scan accessible repositories for workflows."
                )
            } else if store.isLoadingGitHubAccess && store.accessibleRepositories.isEmpty {
                ProgressView("Loading accessible repositories…")
            } else if store.accessibleRepositories.isEmpty {
                discoveryEmptyState(
                    title: "No accessible repositories found",
                    description: "Install the GitHub App on an account or organization, then reload GitHub access and try discovery again."
                )
            } else if !store.hasSelectedAccessibleRepositories {
                discoveryEmptyState(
                    title: "Select repositories first",
                    description: "Choose at least one repository in GitHub Access before scanning for workflows.",
                    actionTitle: zeroSelectionActionTitle,
                    action: zeroSelectionAction
                )
            } else if store.discoveredWorkflowSuggestions.isEmpty {
                discoveryEmptyState(
                    title: "No workflows found",
                    description: "No GitHub Actions workflows were found in the currently selected repositories."
                )
            } else {
                VStack(spacing: 10) {
                    ForEach(store.discoveredWorkflowSuggestions) { suggestion in
                        DiscoveredWorkflowRow(store: store, suggestion: suggestion)
                    }
                }
            }

            HStack(spacing: 12) {
                Button("Rescan GitHub Workflows") {
                    store.discoverWorkflows()
                }
                .disabled(!store.canDiscoverWorkflows || store.isDiscoveringWorkflows)

                if let manualActionTitle, let manualAction {
                    Button(manualActionTitle, action: manualAction)
                }

                Spacer()

                Button(addButtonTitle, action: onAddSelected)
                    .disabled(!store.hasSelectedDiscoveredWorkflows)
            }
        }
    }

    private func discoveryEmptyState(
        title: String,
        description: String,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)

            Text(description)
                .foregroundStyle(.secondary)

            if let actionTitle, let action {
                Button(actionTitle, action: action)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.72))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.5), lineWidth: 1)
        )
    }
}

private struct DiscoveredWorkflowRow: View {
    @ObservedObject var store: StatusStore
    let suggestion: DiscoveredWorkflowSuggestion

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Toggle(
                "",
                isOn: Binding(
                    get: { suggestion.isSelected },
                    set: { isSelected in
                        store.setDiscoveredWorkflowSelection(suggestion.id, isSelected: isSelected)
                    }
                )
            )
            .labelsHidden()
            .toggleStyle(.checkbox)
            .disabled(!suggestion.isSelectable)

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .center, spacing: 8) {
                    Text(suggestion.displayName)
                        .font(.subheadline.weight(.semibold))

                    if let statusLabel = suggestion.statusLabel {
                        Text(statusLabel)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(suggestion.isAlreadyMonitored ? Color.green.opacity(0.18) : Color.orange.opacity(0.18))
                            )
                    }
                }

                Text(suggestion.repoFullName)
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    Label(suggestion.branch, systemImage: "arrow.triangle.branch")
                    Label(suggestion.workflowFile, systemImage: "gearshape.2")
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.72))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.5), lineWidth: 1)
        )
    }
}

private struct DiscoveryInlineMessageView: View {
    let systemImage: String
    let message: String
    let tint: Color

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(tint)

            Text(message)
                .font(.footnote)
                .foregroundStyle(.primary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(tint.opacity(0.12))
        )
    }
}
#endif
