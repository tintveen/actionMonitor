#if canImport(AppKit) && canImport(SwiftUI)
import AppKit
import SwiftUI

struct MenuBarContentView: View {
    @ObservedObject var store: StatusStore
    @Environment(\.openURL) private var openURL
    let showSettingsWindow: () -> Void

    var body: some View {
        Group {
            if store.showsFreshInstallAuthenticationCTA {
                freshInstallAuthenticationView
            } else if store.workflows.isEmpty {
                emptyStateMenuView
            } else {
                monitoringMenuView
            }
        }
        .padding(16)
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

    private var monitoringMenuView: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Action Monitor")
                    .font(menuBarTitleFont)

                Text(statusSubtitle)
                    .font(menuBarBodyFont)
                    .foregroundStyle(.secondary)
            }

            if let bannerMessage = store.bannerMessage {
                BannerView(message: bannerMessage)
            }

            if let resetMessage = store.resetMessage {
                BannerView(message: resetMessage)
            }

            ForEach(store.states) { state in
                SiteStatusCard(state: state, openURL: openURL)
            }

            Divider()

            HStack(spacing: 10) {
                Button("Refresh now") {
                    store.refreshNow()
                }
                .keyboardShortcut("r")
                .font(menuBarBodyFont)

                Button {
                    showSettingsWindow()
                } label: {
                    Label("Settings", systemImage: "gearshape.fill")
                }
                .font(menuBarBodyFont)
            }

            HStack {
                Spacer(minLength: 0)

                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .font(menuBarBodyFont)
                .buttonStyle(.bordered)
            }

            if let credentialMessage = store.credentialMessage {
                Text(credentialMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var emptyStateMenuView: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Action Monitor")
                .font(menuBarTitleFont)

            VStack(alignment: .leading, spacing: 14) {
                Button {
                    showSettingsWindow()
                    store.discoverWorkflows()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "sparkles.rectangle.stack.fill")
                            .font(.system(size: 14, weight: .semibold))

                        Text(store.isDiscoveringWorkflows ? "Discovering Workflows..." : "Discover Workflows")
                            .font(menuBarButtonFont)

                        Spacer(minLength: 12)

                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.82))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(MenuBarPrimaryButtonStyle())
                .disabled(!store.canDiscoverWorkflows || store.isDiscoveringWorkflows)

                if let connectionStatus = connectionStatus {
                    MenuBarConnectionStatusView(
                        status: connectionStatus.text,
                        iconName: connectionStatus.iconName,
                        tintColor: connectionStatus.tintColor
                    )
                }

                HStack {
                    Spacer(minLength: 0)

                    Button("Quit") {
                        NSApplication.shared.terminate(nil)
                    }
                    .font(menuBarBodyFont)
                    .buttonStyle(.bordered)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(nsColor: .controlBackgroundColor),
                                Color(nsColor: .underPageBackgroundColor).opacity(0.92),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
            )
        }
    }

    private var freshInstallAuthenticationView: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Action Monitor")
                .font(menuBarTitleFont)

            Button {
                store.beginGitHubSignIn()
            } label: {
                HStack(spacing: 10) {
                    GitHubLogoView()
                        .frame(width: 16, height: 16)

                    Text("Authenticate with GitHub")
                        .font(menuBarButtonFont)
                }
                .fixedSize(horizontal: true, vertical: false)
                .contentShape(Rectangle())
            }
            .buttonStyle(MenuBarPrimaryButtonStyle())
            .disabled(!store.gitHubSignInIsAvailable || store.isGitHubSignInBusy || store.isResetting)

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .font(menuBarBodyFont)
            .buttonStyle(.bordered)
        }
    }

    private var statusSubtitle: String {
        if store.workflows.isEmpty {
            return "Add a workflow to start monitoring GitHub Actions"
        }

        return store.isRefreshing ? "Refreshing GitHub Actions…" : "Watching your deploy workflows"
    }

    private var connectionStatus: (text: String, iconName: String, tintColor: Color)? {
        switch store.authState {
        case .signedInOAuthApp(let summary), .signedInPersonalAccessToken(let summary):
            let loginText = summary.login.map { "@\($0)" } ?? "GitHub"
            return (
                text: "Connected GitHub as \(loginText).",
                iconName: "checkmark.circle.fill",
                tintColor: .green
            )
        case .signingInBrowser:
            return (
                text: "Connecting GitHub...",
                iconName: "ellipsis.circle.fill",
                tintColor: .blue
            )
        case .authError(let message):
            return (
                text: message,
                iconName: "exclamationmark.triangle.fill",
                tintColor: .orange
            )
        case .signedOut:
            guard let credentialMessage = store.credentialMessage else {
                return nil
            }

            return (
                text: credentialMessage,
                iconName: "bolt.horizontal.circle.fill",
                tintColor: .secondary
            )
        }
    }

    private var menuBarTitleFont: Font {
        .system(size: 13, weight: .semibold, design: .default)
    }

    private var menuBarBodyFont: Font {
        .system(size: 13, weight: .regular, design: .default)
    }

    private var menuBarButtonFont: Font {
        .system(size: 13, weight: .semibold, design: .default)
    }
}

private struct MenuBarPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white.opacity(isEnabled ? 1 : 0.55))
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(nsColor: .controlAccentColor).opacity(isEnabled ? (configuration.isPressed ? 0.82 : 1.0) : 0.45))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.white.opacity(isEnabled ? 0.16 : 0.08), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(isEnabled ? (configuration.isPressed ? 0.06 : 0.12) : 0.03), radius: configuration.isPressed ? 1 : 2, x: 0, y: configuration.isPressed ? 0 : 1)
            .scaleEffect(isEnabled && configuration.isPressed ? 0.99 : 1)
    }
}

private struct GitHubLogoView: View {
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

private struct BannerView: View {
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(.blue)

            Text(message)
                .font(.footnote)
                .foregroundStyle(.primary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlAccentColor).opacity(0.16))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.35), lineWidth: 1)
        )
    }
}

private struct MenuBarConnectionStatusView: View {
    let status: String
    let iconName: String
    let tintColor: Color

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: iconName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tintColor)

            Text(status)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.035))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
        )
    }
}

private struct SiteStatusCard: View {
    let state: DeployState
    let openURL: OpenURLAction

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: state.status.symbolName)
                    .foregroundStyle(state.status.color)
                    .font(.system(size: 20, weight: .semibold))

                VStack(alignment: .leading, spacing: 2) {
                    Text(state.workflow.displayName)
                        .font(.system(size: 13, weight: .semibold, design: .default))

                    Text(state.statusText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            HStack(spacing: 12) {
                if let relativeTimestamp = relativeTimestampText {
                    Label(relativeTimestamp, systemImage: "clock")
                }

                if let shortCommitSHA = state.shortCommitSHA {
                    Label(shortCommitSHA, systemImage: "number")
                }
            }
            .font(.footnote)
            .foregroundStyle(.secondary)

            if let errorMessage = state.errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 10) {
                if let siteURL = state.workflow.siteURL {
                    Button("Open site") {
                        openURL(siteURL)
                    }
                }

                if let runURL = state.runURL {
                    Button(state.detailsLinkTitle) {
                        openURL(runURL)
                    }
                }
            }
            .buttonStyle(.link)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
        )
    }

    private var relativeTimestampText: String? {
        guard let timestamp = state.relevantTimestamp else {
            return nil
        }

        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short

        switch state.status {
        case .running:
            return "Started \(formatter.localizedString(for: timestamp, relativeTo: .now))"
        case .success, .failed, .unknown:
            return "Updated \(formatter.localizedString(for: timestamp, relativeTo: .now))"
        }
    }
}

struct MenuBarIconView: View {
    let status: DeployStatus
    private static let iconSideLength: CGFloat = 13

    var body: some View {
        Image(systemName: status.symbolName)
            .renderingMode(.template)
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(.primary)
            .font(.system(size: Self.iconSideLength, weight: .semibold))
            .frame(width: Self.iconSideLength, height: Self.iconSideLength, alignment: .center)
            .fixedSize()
            .help(status.accessibilityLabel)
    }
}

extension DeployStatus {
    var symbolName: String {
        switch self {
        case .running:
            return "arrow.triangle.2.circlepath.circle.fill"
        case .failed:
            return "exclamationmark.circle.fill"
        case .success:
            return "checkmark.circle.fill"
        case .unknown:
            return "questionmark.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .running:
            return .orange
        case .failed:
            return .red
        case .success:
            return .green
        case .unknown:
            return .gray
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .running:
            return "A deploy is currently running"
        case .failed:
            return "At least one recent deploy failed"
        case .success:
            return "Recent deploys succeeded"
        case .unknown:
            return "Deploy status unavailable"
        }
    }
}
#endif
