#if canImport(AppKit) && canImport(SwiftUI)
import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: StatusStore
    @State fileprivate var editorDraft = MonitoredWorkflowDraft()
    @State fileprivate var editingWorkflowID: UUID?
    @State fileprivate var isEditorPresented = false
    @State fileprivate var isResetConfirmationPresented = false
    @State fileprivate var isRepositoryAccessExpanded = false
    @State fileprivate var isWorkflowsExpanded = false
    @State fileprivate var workflowActionMessage: String?
    @State fileprivate var workflowEditorMessage: String?

    init(store: StatusStore) {
        self.store = store
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                workflowsSection
                if store.supportsRepositorySelection {
                    repositoryAccessSection
                }
                workflowsDiscoverySection
                controlsSection
            }
            .disabled(store.isResetting)
            .padding(20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .underPageBackgroundColor))
        .sheet(isPresented: $isEditorPresented) {
            WorkflowEditorSheet(
                title: editingWorkflowID == nil ? "Add Workflow" : "Edit Workflow",
                draft: $editorDraft,
                errorMessage: workflowEditorMessage,
                onCancel: {
                    isEditorPresented = false
                },
                onSave: saveWorkflow
            )
        }
        .alert("Reset App?", isPresented: $isResetConfirmationPresented) {
            Button("Cancel", role: .cancel) {}
            Button("Reset App", role: .destructive) {
                store.resetApp()
            }
        } message: {
            Text("This will remove monitored workflows on this Mac, clear saved GitHub credentials, and reset onboarding/setup progress.")
        }
    }

    private var workflowsSection: some View {
        SettingsSectionCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    SettingsSectionHeader(
                        title: "Actions",
                        detail: store.workflows.isEmpty ? "None added" : "\(store.workflows.count) added"
                    )

                    Spacer()

                    refreshFrequencyButton
                }

                if let workflowConfigurationMessage = store.workflowConfigurationMessage {
                    InlineMessageView(
                        systemImage: "exclamationmark.triangle.fill",
                        message: workflowConfigurationMessage,
                        tint: .orange
                    )
                }

                if store.workflows.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("No workflows added yet.")
                            .font(.headline)

                        Text("Use the discovery section below to scan your selected GitHub repositories.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    VStack(spacing: 8) {
                        ForEach(Array(store.workflows.enumerated()), id: \.element.id) { index, workflow in
                            WorkflowRow(
                                workflow: workflow,
                                canMoveUp: index > 0,
                                canMoveDown: index < store.workflows.count - 1,
                                onEdit: { openEditWorkflowEditor(workflow) },
                                onDelete: { deleteWorkflow(workflow.id) },
                                onMoveUp: { moveWorkflowUp(workflow.id) },
                                onMoveDown: { moveWorkflowDown(workflow.id) }
                            )
                        }
                    }
                }

                if let workflowActionMessage {
                    InlineMessageView(
                        systemImage: "exclamationmark.circle.fill",
                        message: workflowActionMessage,
                        tint: .red
                    )
                }
            }
        }
    }

    private var controlsSection: some View {
        SettingsSectionCard {
            VStack(alignment: .center, spacing: 12) {
                githubActionButton(
                    title: store.authState.signedInSummary == nil ? "Sign In" : "Sign Out",
                    isEnabled: store.authState.signedInSummary == nil
                        ? (store.gitHubSignInIsAvailable && !store.isGitHubSignInBusy)
                        : true,
                    action: {
                        if store.authState.signedInSummary == nil {
                            store.beginGitHubSignIn()
                        } else {
                            store.signOut()
                        }
                    }
                )
                .frame(maxWidth: .infinity, minHeight: 36, alignment: .center)

                Button(role: .destructive) {
                    isResetConfirmationPresented = true
                } label: {
                    SettingsDangerButtonLabel(title: "Reset App", systemImage: "trash")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(.red)
                .disabled(store.isResetting)
                .frame(maxWidth: .infinity, minHeight: 36, alignment: .center)

                if let resetMessage = store.resetMessage {
                    InlineMessageView(
                        systemImage: "exclamationmark.circle.fill",
                        message: resetMessage,
                        tint: .red
                    )
                }
            }
        }
    }

    private var repositoryAccessSection: some View {
        SettingsCollapsibleSection(
            title: "Repositories",
            detail: repositoryDetailText,
            isExpanded: $isRepositoryAccessExpanded
        ) {
            VStack(alignment: .leading, spacing: 10) {
                if store.accessibleRepositories.isEmpty {
                    Text(store.isLoadingGitHubAccess ? "Loading repositories…" : "No repositories available.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.top, 2)
                } else {
                    HStack(spacing: 8) {
                        Button("Select All") {
                            store.selectAllAccessibleRepositories()
                        }
                        .buttonStyle(.bordered)

                        Button("Clear") {
                            store.clearAccessibleRepositorySelection()
                        }
                        .buttonStyle(.bordered)

                        Button("Reload") {
                            store.reloadGitHubAccess()
                        }
                        .buttonStyle(.bordered)

                        Spacer()
                    }
                    .font(.footnote)

                    VStack(spacing: 6) {
                        ForEach(store.accessibleRepositories) { repository in
                            RepositorySelectionRow(
                                repository: repository,
                                isSelected: store.isRepositorySelected(repository.id),
                                action: {
                                    store.toggleRepositorySelection(repository.id)
                                }
                            )
                        }
                    }
                }
            }
        }
    }

    private var refreshFrequencyButton: some View {
        Menu {
            ForEach(WorkflowRefreshInterval.allCases) { interval in
                Button {
                    store.setWorkflowRefreshInterval(interval)
                } label: {
                    if interval == store.workflowRefreshInterval {
                        Label(interval.menuSubtitle, systemImage: "checkmark")
                    } else {
                        Text(interval.menuSubtitle)
                    }
                }
            }
        } label: {
            SettingsClockActionButtonLabel(title: "Refresh: \(store.workflowRefreshInterval.shortLabel)")
        }
        .menuStyle(.borderedButton)
        .controlSize(.large)
    }

    private var workflowDiscoverySummary: String {
        if store.isDiscoveringWorkflows {
            return "Scanning…"
        }

        if store.discoveredWorkflowSuggestions.isEmpty {
            return "Choose from GitHub"
        }

        return "\(store.selectedDiscoveredWorkflowCount) of \(store.selectableDiscoveredWorkflowCount) selected"
    }

    private var repositoryDetailText: String {
        if store.accessibleRepositories.isEmpty {
            return store.isLoadingGitHubAccess ? "Loading…" : "None loaded"
        }

        return "\(store.selectedAccessibleRepositories.count) of \(store.accessibleRepositories.count) selected"
    }

    private var workflowsDiscoveryDetailText: String {
        workflowDiscoverySummary
    }

    private var workflowsDiscoveryShouldShow: Bool {
        store.canDiscoverWorkflows ||
            store.isDiscoveringWorkflows ||
            store.workflowDiscoveryMessage != nil ||
            !store.discoveredWorkflowSuggestions.isEmpty
    }

    @ViewBuilder
    private var workflowsDiscoverySection: some View {
        if workflowsDiscoveryShouldShow {
            SettingsCollapsibleSection(
                title: "Workflows",
                detail: workflowsDiscoveryDetailText,
                isExpanded: $isWorkflowsExpanded
            ) {
                WorkflowDiscoveryReviewView(
                    store: store,
                    addButtonTitle: store.selectedDiscoveredWorkflowCount == 1
                        ? "Add 1"
                        : "Add Selected",
                    onAddSelected: addDiscoveredWorkflows,
                    manualActionTitle: nil,
                    manualAction: nil,
                    zeroSelectionActionTitle: "Open Repositories",
                    zeroSelectionAction: {
                        isRepositoryAccessExpanded = true
                    }
                )
                .padding(.top, 2)
            }
        }
    }

    private func githubActionButton(
        title: String,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            GitHubActionButtonLabel(title: title)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .tint(.black)
        .disabled(!isEnabled)
        .frame(maxWidth: .infinity)
    }
}

private struct SettingsSectionCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.7), lineWidth: 1)
        )
    }
}

private struct SettingsSectionHeader: View {
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(title)
                .font(.system(size: 20, weight: .semibold, design: .rounded))

            Text(detail)
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)

            Spacer()
        }
    }
}

private struct SettingsSubsectionHeader: View {
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(title)
                .font(.headline)

            Text(detail)
                .font(.footnote)
                .foregroundStyle(.secondary)

            Spacer()
        }
    }
}

private struct SettingsCollapsibleSection<Content: View>: View {
    let title: String
    let detail: String
    @Binding var isExpanded: Bool
    @ViewBuilder let content: Content

    var body: some View {
        SettingsSectionCard {
            VStack(alignment: .leading, spacing: 0) {
                Button {
                    isExpanded.toggle()
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        SettingsSubsectionHeader(title: title, detail: detail)

                        Spacer()

                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if isExpanded {
                    Divider()
                        .padding(.top, 10)

                    content
                        .padding(.top, 10)
                }
            }
        }
    }
}

private struct GitHubActionButtonLabel: View {
    let title: String

    var body: some View {
        HStack(spacing: 10) {
            SettingsGitHubLogoView()
                .frame(width: 16, height: 16)

            Text(title)
                .font(.headline)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }
}

private struct SettingsClockActionButtonLabel: View {
    let title: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "clock")
                .font(.system(size: 14, weight: .semibold))

            Text(title)
                .font(.headline)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SettingsDangerButtonLabel: View {
    let title: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))

            Text(title)
                .font(.headline)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }
}

private struct SettingsGitHubLogoView: View {
    var body: some View {
        Image(nsImage: Self.logoImage)
            .resizable()
            .scaledToFit()
            .accessibilityHidden(true)
    }

    private static let logoImage: NSImage = {
        guard let url = Bundle.module.url(forResource: "GitHub_Invertocat_White", withExtension: "svg"),
              let image = NSImage(contentsOf: url) else {
            return NSImage()
        }

        image.isTemplate = true
        return image
    }()
}

extension SettingsView {
    private func openEditWorkflowEditor(_ workflow: MonitoredWorkflow) {
        editorDraft = MonitoredWorkflowDraft(workflow: workflow)
        editingWorkflowID = workflow.id
        workflowEditorMessage = nil
        workflowActionMessage = nil
        isEditorPresented = true
    }

    private func saveWorkflow() {
        do {
            if let editingWorkflowID {
                try store.updateWorkflow(id: editingWorkflowID, from: editorDraft)
            } else {
                try store.addWorkflow(from: editorDraft)
            }

            workflowActionMessage = nil
            workflowEditorMessage = nil
            isEditorPresented = false
        } catch {
            workflowEditorMessage = error.localizedDescription
        }
    }

    private func addDiscoveredWorkflows() {
        do {
            try store.addSelectedDiscoveredWorkflows()
            workflowActionMessage = nil
        } catch {
            workflowActionMessage = error.localizedDescription
        }
    }

    private func deleteWorkflow(_ id: UUID) {
        do {
            try store.deleteWorkflow(id: id)
            workflowActionMessage = nil
        } catch {
            workflowActionMessage = error.localizedDescription
        }
    }

    private func moveWorkflowUp(_ id: UUID) {
        do {
            try store.moveWorkflowUp(id: id)
            workflowActionMessage = nil
        } catch {
            workflowActionMessage = error.localizedDescription
        }
    }

    private func moveWorkflowDown(_ id: UUID) {
        do {
            try store.moveWorkflowDown(id: id)
            workflowActionMessage = nil
        } catch {
            workflowActionMessage = error.localizedDescription
        }
    }
}

private struct WorkflowRow: View {
    let workflow: MonitoredWorkflow
    let canMoveUp: Bool
    let canMoveDown: Bool
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(workflow.displayName)
                        .font(.system(size: 14.5, weight: .semibold, design: .rounded))

                    Text("\(workflow.owner)/\(workflow.repo)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                HStack(spacing: 6) {
                    Button(action: onMoveUp) {
                        Image(systemName: "arrow.up")
                    }
                    .disabled(!canMoveUp)
                    .help("Move up")

                    Button(action: onMoveDown) {
                        Image(systemName: "arrow.down")
                    }
                    .disabled(!canMoveDown)
                    .help("Move down")

                    Button(action: onEdit) {
                        Image(systemName: "pencil")
                    }
                    .help("Edit")

                    Button(role: .destructive, action: onDelete) {
                        Image(systemName: "trash")
                    }
                    .help("Delete")
                }
                .buttonStyle(.borderless)
            }

            HStack(spacing: 8) {
                WorkflowMetaPill(text: workflow.branch)
                WorkflowMetaPill(text: workflow.workflowFile.workflowFileDisplayName)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.45), lineWidth: 1)
        )
    }
}

private struct WorkflowEditorSheet: View {
    let title: String
    @Binding var draft: MonitoredWorkflowDraft
    let errorMessage: String?
    let onCancel: () -> Void
    let onSave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.system(size: 22, weight: .semibold, design: .rounded))

            Text("Display name is optional.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            WorkflowTextField(title: "Display Name", placeholder: "Customer Dashboard", text: $draft.displayName)
            WorkflowTextField(title: "Owner or Organization", placeholder: "octo-org", text: $draft.owner)
            WorkflowTextField(title: "Repository", placeholder: "dashboard", text: $draft.repo)
            WorkflowTextField(title: "Branch", placeholder: "main", text: $draft.branch)
            WorkflowTextField(title: "Workflow File", placeholder: "deploy.yml", text: $draft.workflowFile)
            WorkflowTextField(title: "Site URL (Optional)", placeholder: "https://dashboard.example.com", text: $draft.siteURLText)

            if let errorMessage {
                InlineMessageView(
                    systemImage: "exclamationmark.circle.fill",
                    message: errorMessage,
                    tint: .red
                )
            }

            HStack {
                Button("Cancel", action: onCancel)

                Spacer()

                Button("Save Workflow", action: onSave)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 520)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct WorkflowTextField: View {
    let title: String
    let placeholder: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.semibold))

            TextField(placeholder, text: $text)
                .textFieldStyle(.roundedBorder)
        }
    }
}

private struct RepositorySelectionRow: View {
    let repository: GitHubAccessibleRepositorySummary
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                SettingsSelectionIndicator(isSelected: isSelected, isEnabled: true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(repository.fullName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(repository.defaultBranch ?? "No default branch")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected
                          ? Color.accentColor.opacity(0.10)
                          : Color(nsColor: .windowBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(
                        isSelected
                            ? Color.accentColor.opacity(0.4)
                            : Color(nsColor: .separatorColor).opacity(0.45),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

private struct WorkflowMetaPill: View {
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

private struct SettingsSelectionIndicator: View {
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

private struct InlineMessageView: View {
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
