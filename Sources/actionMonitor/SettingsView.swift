#if canImport(AppKit) && canImport(SwiftUI)
import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: StatusStore
    @State private var tokenInput = ""
    @State private var editorDraft = MonitoredWorkflowDraft()
    @State private var editingWorkflowID: UUID?
    @State private var isEditorPresented = false
    @State private var workflowActionMessage: String?
    @State private var workflowEditorMessage: String?

    init(store: StatusStore) {
        self.store = store
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                workflowsSection
                authSection
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            LinearGradient(
                colors: [
                    Color(nsColor: .windowBackgroundColor),
                    Color(nsColor: .underPageBackgroundColor),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
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
    }

    private var workflowsSection: some View {
        SettingsSectionCard {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Monitored Workflows")
                        .font(.system(size: 22, weight: .semibold, design: .rounded))

                    Text("Add one GitHub Actions workflow per item. actionMonitor watches these in the saved order and keeps the list on this Mac.")
                        .foregroundStyle(.secondary)
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

                if store.workflows.isEmpty {
                    EmptySettingsState(openEditor: openAddWorkflowEditor)
                } else {
                    VStack(spacing: 12) {
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

                HStack {
                    Button {
                        openAddWorkflowEditor()
                    } label: {
                        Label("Add Workflow", systemImage: "plus")
                    }
                    .keyboardShortcut("n")

                    Spacer()
                }
            }
        }
    }

    private var authSection: some View {
        SettingsSectionCard {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("GitHub Access")
                        .font(.system(size: 22, weight: .semibold, design: .rounded))

                    Text("Sign in with GitHub in your browser to monitor private repositories without managing a personal access token. The token fallback stays available for advanced cases.")
                        .foregroundStyle(.secondary)
                }

                if let configurationMessage = store.gitHubSignInConfigurationMessage {
                    InlineMessageView(
                        systemImage: "gear.badge.xmark",
                        message: configurationMessage,
                        tint: .orange
                    )
                }

                authCard

                Divider()

                personalAccessTokenSection

                if let credentialMessage = store.credentialMessage {
                    InlineMessageView(
                        systemImage: "info.circle.fill",
                        message: credentialMessage,
                        tint: .blue
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
                title: "No GitHub credential saved",
                description: "Browser sign-in is the easiest way to connect private repositories and improve GitHub API reliability."
            )
        case .authError(let message):
            VStack(alignment: .leading, spacing: 12) {
                InlineMessageView(
                    systemImage: "exclamationmark.circle.fill",
                    message: message,
                    tint: .red
                )

                authCallToActionCard(
                    title: "GitHub sign-in needs attention",
                    description: "Start browser sign-in again, or save a personal access token below as a fallback."
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
        case .signedInOAuth(let summary):
            CredentialSummaryCard(
                summary: summary,
                title: summary.login.map { "@\($0)" } ?? "GitHub connected",
                subtitle: "Signed in with GitHub browser OAuth.",
                primaryButtonTitle: "Sign In Again",
                primaryAction: {
                    store.beginGitHubSignIn()
                },
                primaryActionDisabled: !store.gitHubSignInIsAvailable || store.isGitHubSignInBusy,
                secondaryButtonTitle: "Sign Out",
                secondaryAction: {
                    tokenInput = ""
                    store.signOut()
                }
            )
        case .signedInPersonalAccessToken(let summary):
            CredentialSummaryCard(
                summary: summary,
                title: "Personal access token saved",
                subtitle: "GitHub requests are authenticated with a token stored in Keychain.",
                primaryButtonTitle: "Switch to Browser Sign-In",
                primaryAction: {
                    store.beginGitHubSignIn()
                },
                primaryActionDisabled: !store.gitHubSignInIsAvailable || store.isGitHubSignInBusy,
                secondaryButtonTitle: "Remove Token",
                secondaryAction: {
                    tokenInput = ""
                    store.signOut()
                }
            )
        }
    }

    private func authCallToActionCard(title: String, description: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)

            Text(description)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Button {
                    store.beginGitHubSignIn()
                } label: {
                    Label("Continue in Browser", systemImage: "safari")
                }
                .disabled(!store.gitHubSignInIsAvailable || store.isGitHubSignInBusy)

                Spacer()
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.72))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.5), lineWidth: 1)
        )
    }

    private var personalAccessTokenSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Personal Access Token Fallback")
                .font(.headline)

            Text("Use this only if you want manual token management or browser sign-in is unavailable. Saving a token here replaces the current saved credential.")
                .foregroundStyle(.secondary)

            SecureField("GitHub personal access token", text: $tokenInput)
                .textFieldStyle(.roundedBorder)

            Text(store.hasStoredPersonalAccessToken
                 ? "A personal access token is currently saved in Keychain."
                 : "Public repositories can work without authentication, but private repositories and better rate-limit behavior need GitHub sign-in or a token.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Button(store.hasStoredPersonalAccessToken ? "Save New Token" : "Save Token") {
                    let token = tokenInput
                    tokenInput = ""
                    store.savePersonalAccessToken(token)
                }
                .disabled(tokenInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button("Remove Saved Token") {
                    tokenInput = ""
                    store.signOut()
                }
                .disabled(!store.hasStoredPersonalAccessToken)

                Spacer()
            }
        }
    }

    private func openAddWorkflowEditor() {
        editorDraft = MonitoredWorkflowDraft()
        editingWorkflowID = nil
        workflowEditorMessage = nil
        workflowActionMessage = nil
        isEditorPresented = true
    }

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

private struct SettingsSectionCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
        )
    }
}

private struct CredentialSummaryCard: View {
    let summary: GitHubAuthAccountSummary
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
                .foregroundStyle(.secondary)

            HStack(spacing: 14) {
                Label(summary.source.displayName, systemImage: iconName)

                if !summary.grantedScopes.isEmpty {
                    Label(summary.grantedScopes.joined(separator: ", "), systemImage: "checklist")
                }

                Label("Saved \(summary.savedAt.formatted(date: .abbreviated, time: .shortened))", systemImage: "clock")
            }
            .font(.footnote)
            .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Button(primaryButtonTitle, action: primaryAction)
                    .disabled(primaryActionDisabled)

                Button(secondaryButtonTitle, action: secondaryAction)

                Spacer()
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.72))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.5), lineWidth: 1)
        )
    }

    private var iconName: String {
        switch summary.source {
        case .oauthBrowser:
            return "safari"
        case .personalAccessToken:
            return "key.fill"
        }
    }
}

private struct BrowserSignInCard: View {
    let context: GitHubBrowserAuthorizationContext
    let reopenBrowser: () -> Void
    let cancelSignIn: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Finish GitHub sign-in in your browser")
                .font(.headline)

            Text("actionMonitor already opened the browser. Once GitHub redirects back, the app will save your access automatically.")
                .foregroundStyle(.secondary)

            Text(context.authorizationURL.absoluteString)
                .font(.footnote.monospaced())
                .textSelection(.enabled)
                .foregroundStyle(.secondary)

            Text("Waiting until \(context.expiresAt.formatted(date: .omitted, time: .shortened)).")
                .font(.footnote)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Button("Open Browser Again", action: reopenBrowser)
                Button("Cancel", action: cancelSignIn)
                Spacer()
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.72))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.5), lineWidth: 1)
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

            HStack(spacing: 14) {
                Label(workflow.branch, systemImage: "arrow.triangle.branch")
                Label(workflow.workflowFile, systemImage: "gearshape.2")
            }
            .font(.footnote)
            .foregroundStyle(.secondary)

            if let siteURL = workflow.siteURL {
                Text(siteURL.absoluteString)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
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

private struct EmptySettingsState: View {
    let openEditor: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("No workflows configured yet.")
                .font(.headline)

            Text("Add your first workflow to start monitoring GitHub Actions from the menu bar.")
                .foregroundStyle(.secondary)

            Button {
                openEditor()
            } label: {
                Label("Add Your First Workflow", systemImage: "plus.circle.fill")
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.72))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.5), lineWidth: 1)
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
                .font(.system(size: 24, weight: .semibold, design: .rounded))

            Text("Use the workflow file name or path exactly as it appears in the repository. Display name is optional; if left blank, the repository name will be used.")
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
        .background(
            LinearGradient(
                colors: [
                    Color(nsColor: .windowBackgroundColor),
                    Color(nsColor: .underPageBackgroundColor),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
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
