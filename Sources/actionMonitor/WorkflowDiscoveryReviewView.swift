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
        VStack(alignment: .leading, spacing: 12) {
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
                    title: "GitHub sign-in required",
                    description: "Connect GitHub to scan repositories."
                )
            } else if store.isLoadingGitHubAccess && store.visibleAccessibleRepositories.isEmpty {
                ProgressView("Loading accessible repositories…")
            } else if store.visibleAccessibleRepositories.isEmpty {
                discoveryEmptyState(
                    title: "No repositories found",
                    description: "Nothing is available to scan yet."
                )
            } else if !store.hasSelectedAccessibleRepositories {
                discoveryEmptyState(
                    title: "Select repositories first",
                    description: "Choose at least one repository above.",
                    actionTitle: zeroSelectionActionTitle,
                    action: zeroSelectionAction
                )
            } else if store.discoveredWorkflowSuggestions.isEmpty {
                discoveryEmptyState(
                    title: "No workflows found",
                    description: "Nothing matched in the selected repositories."
                )
            } else {
                VStack(spacing: 8) {
                    ForEach(store.discoveredWorkflowSuggestions) { suggestion in
                        DiscoveredWorkflowRow(store: store, suggestion: suggestion)
                    }
                }
            }

            HStack(spacing: 12) {
                Button("Find Workflows") {
                    store.discoverWorkflows()
                }
                .disabled(!store.canDiscoverWorkflows || store.isDiscoveringWorkflows)

                if let helpTitle = store.workflowDiscoveryHelpTitle {
                    Button(helpTitle) {
                        store.openWorkflowDiscoveryHelp()
                    }
                }

                if let manualActionTitle, let manualAction {
                    Button(manualActionTitle, action: manualAction)
                }

                Spacer()

                Button("Select All") {
                    store.selectAllDiscoveredWorkflows()
                }
                .disabled(store.selectableDiscoveredWorkflowCount == 0)

                Button("Clear") {
                    store.clearDiscoveredWorkflowSelection()
                }
                .disabled(!store.hasSelectedDiscoveredWorkflows)

                Button(addButtonTitle, action: onAddSelected)
                    .disabled(!store.hasSelectedDiscoveredWorkflows)
            }
            .font(.footnote)
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
                .font(.footnote)
                .foregroundStyle(.secondary)

            if let actionTitle, let action {
                Button(actionTitle, action: action)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.45), lineWidth: 1)
        )
    }
}

private struct DiscoveredWorkflowRow: View {
    @ObservedObject var store: StatusStore
    let suggestion: DiscoveredWorkflowSuggestion

    var body: some View {
        Button {
            store.toggleDiscoveredWorkflowSelection(suggestion.id)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                DiscoverySelectionIndicator(
                    isSelected: suggestion.isSelected,
                    isEnabled: suggestion.isSelectable
                )

                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .center, spacing: 8) {
                        Text(suggestion.displayName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(suggestion.isSelectable ? .primary : .secondary)

                        if let statusLabel = suggestion.statusLabel {
                            DiscoveryStatusPill(
                                text: statusLabel,
                                tint: suggestion.isAlreadyMonitored ? .green : .orange
                            )
                        }
                    }

                    Text(suggestion.repoFullName)
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        DiscoveryMetaPill(text: suggestion.branch)
                        DiscoveryMetaPill(text: suggestion.workflowFile.workflowFileDisplayName)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(backgroundColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(!suggestion.isSelectable)
    }

    private var backgroundColor: Color {
        if suggestion.isSelected && suggestion.isSelectable {
            return Color.accentColor.opacity(0.10)
        }

        return Color(nsColor: .windowBackgroundColor)
    }

    private var borderColor: Color {
        if suggestion.isSelected && suggestion.isSelectable {
            return Color.accentColor.opacity(0.4)
        }

        return Color(nsColor: .separatorColor).opacity(0.45)
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

private struct DiscoveryMetaPill: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule(style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
    }
}

private struct DiscoveryStatusPill: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule(style: .continuous)
                    .fill(tint.opacity(0.14))
            )
    }
}

private struct DiscoverySelectionIndicator: View {
    let isSelected: Bool
    let isEnabled: Bool

    var body: some View {
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(indicatorColor)
    }

    private var indicatorColor: Color {
        if !isEnabled {
            return .secondary.opacity(0.45)
        }

        return isSelected ? .accentColor : .secondary.opacity(0.7)
    }
}
#endif
