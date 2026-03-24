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
                actionsSection
                dangerZoneSection
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

    private var actionsSection: some View {
        SettingsSectionCard {
            VStack(alignment: .leading, spacing: 14) {
                SettingsSectionHeader(
                    title: "Actions",
                    detail: store.workflows.isEmpty ? "None added" : "\(store.workflows.count) added"
                )

                VStack(alignment: .leading, spacing: 10) {
                    authCard

                    refreshFrequencyButton
                }

                if let configurationMessage = store.gitHubSignInConfigurationMessage {
                    InlineMessageView(
                        systemImage: "gear.badge.xmark",
                        message: configurationMessage,
                        tint: .orange
                    )
                } else if let visibleCredentialMessage {
                    InlineMessageView(
                        systemImage: "info.circle.fill",
                        message: visibleCredentialMessage,
                        tint: .blue
                    )
                }

                Divider()

                if store.workflows.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("No workflows added yet.")
                            .font(.headline)

                        Text("Use the discovery section below to scan your selected GitHub repositories.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    VStack(spacing: 10) {
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

                if store.supportsRepositorySelection {
                    repositoryAccessSection
                }

                if store.canDiscoverWorkflows ||
                    store.isDiscoveringWorkflows ||
                    store.workflowDiscoveryMessage != nil ||
                    !store.discoveredWorkflowSuggestions.isEmpty {
                    Divider()

                    DisclosureGroup(isExpanded: $isWorkflowsExpanded) {
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
                        .padding(.top, 8)
                    } label: {
                        SettingsSubsectionHeader(
                            title: "Workflows",
                            detail: workflowDiscoverySummary
                        )
                    }
                    .buttonStyle(.plain)
                }

                if let workflowConfigurationMessage = store.workflowConfigurationMessage {
                    InlineMessageView(
                        systemImage: "exclamationmark.triangle.fill",
                        message: workflowConfigurationMessage,
                        tint: .orange
                    )
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

    private var dangerZoneSection: some View {
        SettingsSectionCard {
            VStack(alignment: .leading, spacing: 12) {
                Button(role: .destructive) {
                    isResetConfirmationPresented = true
                } label: {
                    Label("Reset App", systemImage: "trash")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(.red)
                .disabled(store.isResetting)

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

    @ViewBuilder
    private var authCard: some View {
        switch store.authState {
        case .signedOut:
            authCallToActionCard(
                title: "No GitHub session",
                description: "Browser sign-in is the simplest setup."
            )
        case .authError:
            VStack(alignment: .leading, spacing: 12) {
                if let authErrorMessage = visibleAuthErrorMessage {
                    InlineMessageView(
                        systemImage: "exclamationmark.circle.fill",
                        message: authErrorMessage,
                        tint: .red
                    )
                }

                authCallToActionCard(
                    title: "Sign-in needs attention",
                    description: "Start the browser flow again to restore access."
                )
            }
        case .signingInBrowser(let context):
            BrowserSignInCard(
                context: context,
                reopenBrowser: {
                    store.reopenBrowserSignIn()
                },
                cancelSignIn: {
                    store.cancelGitHubSignIn()
                }
            )
        case .signedInOAuthApp(let summary):
            CredentialSummaryCard(
                summary: summary,
                title: "GitHub connected",
                subtitle: "Connected with browser sign-in.",
                primaryButtonTitle: "Sign In Again",
                primaryAction: {
                    store.beginGitHubSignIn()
                },
                primaryActionDisabled: !store.gitHubSignInIsAvailable || store.isGitHubSignInBusy,
                secondaryButtonTitle: "Sign Out",
                secondaryAction: {
                    store.signOut()
                }
            )
        case .signedInPersonalAccessToken(let summary):
            CredentialSummaryCard(
                summary: summary,
                title: "Token saved",
                subtitle: "Requests are authenticated with a personal access token.",
                primaryButtonTitle: "Use Browser Sign-In",
                primaryAction: {
                    store.beginGitHubSignIn()
                },
                primaryActionDisabled: !store.gitHubSignInIsAvailable || store.isGitHubSignInBusy,
                secondaryButtonTitle: "Remove Token",
                secondaryAction: {
                    store.signOut()
                }
            )
        }
    }

    private var repositoryAccessSection: some View {
        DisclosureGroup(isExpanded: $isRepositoryAccessExpanded) {
            VStack(alignment: .leading, spacing: 10) {
                if store.accessibleRepositories.isEmpty {
                    Text(store.isLoadingGitHubAccess ? "Loading repositories…" : "No repositories available.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.top, 8)
                } else {
                    HStack(spacing: 8) {
                        Button("All") {
                            store.selectAllAccessibleRepositories()
                        }

                        Button("Clear") {
                            store.clearAccessibleRepositorySelection()
                        }

                        Button("Reload") {
                            store.reloadGitHubAccess()
                        }

                        Spacer()
                    }
                    .font(.footnote)
                    .buttonStyle(.borderless)

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
            .padding(.top, 10)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Repositories")
                        .font(.headline)

                    Text(store.accessibleRepositories.isEmpty
                         ? (store.isLoadingGitHubAccess ? "Loading…" : "None loaded")
                         : "\(store.selectedAccessibleRepositories.count) of \(store.accessibleRepositories.count) selected")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if store.isLoadingGitHubAccess {
                    ProgressView()
                        .controlSize(.small)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func authCallToActionCard(title: String, description: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)

            Text(description)
                .font(.footnote)
                .foregroundStyle(.secondary)

            Button {
                store.beginGitHubSignIn()
            } label: {
                GitHubActionButtonLabel(title: "Continue in Browser")
            }
            .disabled(!store.gitHubSignInIsAvailable || store.isGitHubSignInBusy)
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .frame(maxWidth: .infinity)
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
            HStack(spacing: 10) {
                Image(systemName: "clock")
                    .font(.system(size: 14, weight: .semibold))

                Text("Refresh: \(store.workflowRefreshInterval.shortLabel)")
                    .font(.headline)

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .menuStyle(.borderedButton)
        .controlSize(.large)
    }

    private var visibleCredentialMessage: String? {
        guard let credentialMessage = store.credentialMessage else {
            return nil
        }

        if credentialMessage == store.gitHubSignInConfigurationMessage {
            return nil
        }

        if case .authError(let message) = store.authState, credentialMessage == message {
            return nil
        }

        return credentialMessage
    }

    private var visibleAuthErrorMessage: String? {
        guard case .authError(let message) = store.authState else {
            return nil
        }

        if message == visibleCredentialMessage || message == store.gitHubSignInConfigurationMessage {
            return nil
        }

        return message
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

private struct GitHubActionButtonLabel: View {
    let title: String

    var body: some View {
        HStack(spacing: 10) {
            SettingsGitHubLogoView()
                .frame(width: 16, height: 16)

            Text(title)
                .font(.headline)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

private struct CredentialSummaryCard: View {
    let summary: GitHubAuthSessionSummary
    let title: String
    let subtitle: String
    let primaryButtonTitle: String
    let primaryAction: () -> Void
    let primaryActionDisabled: Bool
    let secondaryButtonTitle: String
    let secondaryAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)

            Text(subtitle)
                .font(.footnote)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                WorkflowMetaPill(text: summary.source.displayName)

                if summary.selectedRepositoryCount > 0 {
                    WorkflowMetaPill(text: "\(summary.selectedRepositoryCount) repos")
                }

                if !summary.grantedScopes.isEmpty {
                    WorkflowMetaPill(text: summary.grantedScopes.joined(separator: ", "))
                }

                WorkflowMetaPill(text: summary.savedAt.formatted(date: .abbreviated, time: .shortened))
            }

            VStack(alignment: .leading, spacing: 8) {
                Button {
                    primaryAction()
                } label: {
                    GitHubActionButtonLabel(title: primaryButtonTitle)
                }
                .disabled(primaryActionDisabled)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .frame(maxWidth: .infinity)

                Button {
                    secondaryAction()
                } label: {
                    GitHubActionButtonLabel(title: secondaryButtonTitle)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(.secondary)
                .frame(maxWidth: .infinity)
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

private struct BrowserSignInCard: View {
    let context: GitHubBrowserAuthorizationContext
    let reopenBrowser: () -> Void
    let cancelSignIn: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Finish GitHub sign-in in your browser")
                .font(.headline)

            Text("The browser is already open. actionMonitor will finish setup when GitHub redirects back.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Text(context.authorizationURL.absoluteString)
                .font(.footnote.monospaced())
                .textSelection(.enabled)
                .foregroundStyle(.secondary)

            Text("Waiting until \(context.expiresAt.formatted(date: .omitted, time: .shortened)).")
                .font(.footnote)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Button("Open Browser Again", action: reopenBrowser)
                Button("Cancel", action: cancelSignIn)
                Spacer()
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

private struct WorkflowRow: View {
    let workflow: MonitoredWorkflow
    let canMoveUp: Bool
    let canMoveDown: Bool
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(workflow.displayName)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))

                    Text("\(workflow.owner)/\(workflow.repo)")
                        .font(.subheadline)
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
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
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
