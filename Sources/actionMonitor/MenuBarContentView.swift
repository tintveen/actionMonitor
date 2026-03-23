#if canImport(AppKit) && canImport(SwiftUI)
import AppKit
import SwiftUI

struct MenuBarContentView: View {
    @ObservedObject var store: StatusStore
    @Environment(\.openURL) private var openURL
    let showSettingsWindow: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Deploy Monitor")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))

                Text(store.isRefreshing ? "Refreshing GitHub Actions…" : "Watching your deploy workflows")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if let bannerMessage = store.bannerMessage {
                BannerView(message: bannerMessage)
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

                Button {
                    showSettingsWindow()
                } label: {
                    Label("GitHub Settings", systemImage: "key.fill")
                }

                Spacer(minLength: 0)

                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
            }

            if let credentialMessage = store.credentialMessage {
                Text(credentialMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
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
                    Text(state.site.displayName)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))

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
                Button("Open site") {
                    openURL(state.site.siteURL)
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

    var body: some View {
        Image(systemName: status.symbolName)
            .symbolRenderingMode(.palette)
            .foregroundStyle(status.color, status.color.opacity(0.3))
            .font(.system(size: 17, weight: .semibold))
            .help(status.accessibilityLabel)
    }
}

private extension DeployStatus {
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
