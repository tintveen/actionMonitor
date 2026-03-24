#if canImport(AppKit) && canImport(SwiftUI)
import AppKit
import SwiftUI

struct OnboardingView: View {
    @ObservedObject var store: StatusStore
    @State private var tokenInput = ""
    @State private var workflowDraft = MonitoredWorkflowDraft()
    @State private var showTokenFallback = false
    @State private var workflowError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            header

            if let step = store.onboardingStep {
                progress(step)
                currentStepView(step)
            } else {
                progress(.welcome)
                currentStepView(.welcome)
            }

            Spacer(minLength: 0)
        }
        .padding(28)
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
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Set Up actionMonitor")
                .font(.system(size: 30, weight: .bold, design: .rounded))

            Text("We’ll connect GitHub, confirm repository access, add your first workflow, and leave the app ready to watch your deploys.")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
    }

    private func progress(_ step: OnboardingStep) -> some View {
        HStack(spacing: 12) {
            ForEach(OnboardingStep.allCases, id: \.self) { candidate in
                HStack(spacing: 8) {
                    Circle()
                        .fill(color(for: candidate, current: step))
                        .frame(width: 10, height: 10)

                    Text(title(for: candidate))
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(candidate == step ? .primary : .secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    @ViewBuilder
    private func currentStepView(_ step: OnboardingStep) -> some View {
        switch step {
        case .welcome:
            welcomeStep
        case .githubSignIn:
            signInStep
        case .firstWorkflow:
            workflowStep
        case .finish:
            finishStep
        }
    }

    private var welcomeStep: some View {
        OnboardingCard {
            VStack(alignment: .leading, spacing: 18) {
                Text("Welcome")
                    .font(.system(size: 24, weight: .semibold, design: .rounded))

                Text("actionMonitor watches the GitHub Actions workflows you care about from your menu bar. First we’ll connect the GitHub App in your browser, then we’ll add the first workflow you want to monitor.")
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 10) {
                    WelcomeBullet(systemImage: "person.crop.circle.badge.checkmark", text: "Sign in with GitHub in your browser")
                    WelcomeBullet(systemImage: "checklist", text: "Confirm which accessible repositories this Mac can monitor")
                    WelcomeBullet(systemImage: "gearshape.2.fill", text: "Pick the repository workflow you want to watch")
                    WelcomeBullet(systemImage: "menubar.rectangle", text: "Start monitoring right from the menu bar")
                }

                HStack(spacing: 12) {
                    Button("Get Started") {
                        store.continueFromWelcome()
                    }
                    .keyboardShortcut(.defaultAction)

                    Button("Skip for now") {
                        store.skipOnboarding()
                    }

                    Spacer()
                }
            }
        }
    }

    private var signInStep: some View {
        OnboardingCard {
            VStack(alignment: .leading, spacing: 18) {
                Text("Connect GitHub")
                    .font(.system(size: 24, weight: .semibold, design: .rounded))

                Text("The smoothest setup is GitHub browser sign-in. We’ll open your browser, GitHub will authorize the app, and actionMonitor will return automatically once access is granted.")
                    .foregroundStyle(.secondary)

                if let configurationMessage = store.gitHubSignInConfigurationMessage {
                    WizardMessage(systemImage: "gear.badge.xmark", message: configurationMessage, tint: .orange)
                }

                if let credentialMessage = store.credentialMessage {
                    WizardMessage(systemImage: "info.circle.fill", message: credentialMessage, tint: .blue)
                }

                switch store.authState {
                case .signedInGitHubApp(let summary):
                    authSummary(summary: summary, description: "GitHub browser sign-in is ready. Repository access will be loaded automatically after sign-in.")
                case .signedInPersonalAccessToken(let summary):
                    authSummary(summary: summary, description: "A personal access token is saved. You can continue setup or switch to browser sign-in.")
                case .signingInBrowser(let context):
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Waiting for GitHub to finish sign-in in your browser", systemImage: "safari")
                            .font(.headline)

                        Text(context.authorizationURL.absoluteString)
                            .font(.footnote.monospaced())
                            .textSelection(.enabled)
                            .foregroundStyle(.secondary)

                        Text("If the browser did not open, you can reopen it. The sign-in window stays active until GitHub redirects back to actionMonitor.")
                            .foregroundStyle(.secondary)

                        HStack(spacing: 12) {
                            Button("Open Browser Again") {
                                store.reopenBrowserSignIn()
                            }

                            Button("Cancel") {
                                store.cancelGitHubSignIn()
                            }

                            Spacer()
                        }
                    }
                case .authError(let message):
                    WizardMessage(systemImage: "exclamationmark.circle.fill", message: message, tint: .red)
                    browserSignInActions
                case .signedOut:
                    browserSignInActions
                }

                if store.showsPersonalAccessTokenFallback {
                    Divider()

                    DisclosureGroup(
                        showTokenFallback ? "Hide token fallback" : "Use personal access token instead",
                        isExpanded: $showTokenFallback
                    ) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("If you prefer manual token management for a local build, you can save a personal access token and continue onboarding without browser sign-in.")
                                .foregroundStyle(.secondary)

                            SecureField("GitHub personal access token", text: $tokenInput)
                                .textFieldStyle(.roundedBorder)

                            HStack(spacing: 12) {
                                Button("Save Token") {
                                    let token = tokenInput
                                    tokenInput = ""
                                    store.savePersonalAccessToken(token)
                                }
                                .disabled(tokenInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                                Spacer()
                            }
                        }
                        .padding(.top, 12)
                    }
                }

                HStack(spacing: 12) {
                    Button("Back") {
                        store.moveBackInOnboarding()
                    }

                    Spacer()

                    Button("Continue") {
                        store.continueFromSignInStep()
                    }
                    .disabled(!store.hasStoredCredential)
                }
            }
        }
    }

    private var workflowStep: some View {
        OnboardingCard {
            VStack(alignment: .leading, spacing: 18) {
                Text("Add Your First Workflow")
                    .font(.system(size: 24, weight: .semibold, design: .rounded))

                Text("Use the workflow file name or path exactly as it appears in your repository. You can add more workflows later in Settings.")
                    .foregroundStyle(.secondary)

                if !store.workflows.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Already added")
                            .font(.headline)

                        ForEach(store.workflows.prefix(3)) { workflow in
                            Text("• \(workflow.displayName) (\(workflow.owner)/\(workflow.repo))")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                OnboardingTextField(title: "Display Name", placeholder: "Customer Dashboard", text: $workflowDraft.displayName)
                OnboardingTextField(title: "Owner or Organization", placeholder: "octo-org", text: $workflowDraft.owner)
                OnboardingTextField(title: "Repository", placeholder: "dashboard", text: $workflowDraft.repo)
                OnboardingTextField(title: "Branch", placeholder: "main", text: $workflowDraft.branch)
                OnboardingTextField(title: "Workflow File", placeholder: ".github/workflows/deploy.yml", text: $workflowDraft.workflowFile)
                OnboardingTextField(title: "Site URL (Optional)", placeholder: "https://dashboard.example.com", text: $workflowDraft.siteURLText)

                if let workflowError {
                    WizardMessage(systemImage: "exclamationmark.circle.fill", message: workflowError, tint: .red)
                }

                HStack(spacing: 12) {
                    Button("Back") {
                        store.moveBackInOnboarding()
                    }

                    Button("Skip for now") {
                        store.skipOnboarding()
                    }

                    Spacer()

                    Button(store.workflows.isEmpty ? "Save Workflow" : "Save Another Workflow") {
                        saveWorkflow()
                    }
                    .keyboardShortcut(.defaultAction)

                    Button("Continue") {
                        store.continueFromWorkflowStep()
                    }
                    .disabled(store.workflows.isEmpty)
                }
            }
        }
    }

    private var finishStep: some View {
        OnboardingCard {
            VStack(alignment: .leading, spacing: 18) {
                Text("You’re Ready")
                    .font(.system(size: 24, weight: .semibold, design: .rounded))

                Text(store.onboardingSummaryText)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 10) {
                    if let summary = store.authState.signedInSummary {
                        Label(summary.login.map { "Signed in as @\($0)" } ?? "GitHub access saved", systemImage: "person.crop.circle.badge.checkmark")
                    }

                    Label("\(store.workflows.count) workflow\(store.workflows.count == 1 ? "" : "s") configured", systemImage: "gearshape.2.fill")
                    Label("You can add or edit workflows later in Settings", systemImage: "slider.horizontal.3")
                }
                .font(.headline)

                if let credentialMessage = store.credentialMessage {
                    WizardMessage(systemImage: "info.circle.fill", message: credentialMessage, tint: .blue)
                }

                HStack(spacing: 12) {
                    Button("Back") {
                        store.moveBackInOnboarding()
                    }

                    Spacer()

                    Button("Start Monitoring") {
                        do {
                            try store.finishOnboarding()
                        } catch {
                            workflowError = error.localizedDescription
                        }
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!store.canFinishOnboarding)
                }
            }
        }
    }

    private var browserSignInActions: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Use browser sign-in so the app can access your repositories through the GitHub App session without asking you to manage tokens by hand.")
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
    }

    private func authSummary(summary: GitHubAuthSessionSummary, description: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(summary.login.map { "Signed in as @\($0)" } ?? "GitHub sign-in saved", systemImage: "person.crop.circle.badge.checkmark")
                .font(.headline)

            Text(description)
                .foregroundStyle(.secondary)

            HStack(spacing: 14) {
                Label(summary.source.displayName, systemImage: summary.source == .githubAppBrowser ? "safari" : "key.fill")

                if summary.selectedRepositoryCount > 0 {
                    Label("\(summary.selectedRepositoryCount) repos selected", systemImage: "checklist")
                }
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
    }

    private func saveWorkflow() {
        do {
            try store.addWorkflow(from: workflowDraft)
            workflowDraft = MonitoredWorkflowDraft()
            workflowError = nil
        } catch {
            workflowError = error.localizedDescription
        }
    }

    private func color(for candidate: OnboardingStep, current: OnboardingStep) -> Color {
        if candidate == current {
            return .accentColor
        }

        let allCases = OnboardingStep.allCases
        guard let currentIndex = allCases.firstIndex(of: current),
              let candidateIndex = allCases.firstIndex(of: candidate) else {
            return .secondary.opacity(0.4)
        }

        return candidateIndex < currentIndex ? .green : .secondary.opacity(0.4)
    }

    private func title(for step: OnboardingStep) -> String {
        switch step {
        case .welcome:
            return "Welcome"
        case .githubSignIn:
            return "GitHub"
        case .firstWorkflow:
            return "Workflow"
        case .finish:
            return "Finish"
        }
    }
}

private struct OnboardingCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
        )
    }
}

private struct WelcomeBullet: View {
    let systemImage: String
    let text: String

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.headline)
    }
}

private struct OnboardingTextField: View {
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

private struct WizardMessage: View {
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
