#if canImport(AppKit) && canImport(SwiftUI)
import AppKit
import SwiftUI

@main
struct ActionMonitorApp: App {
    @StateObject private var statusStore: StatusStore
    private let settingsWindowController: SettingsWindowController

    init() {
        NSWindow.allowsAutomaticWindowTabbing = false

        let settingsWindowController = SettingsWindowController()
        let launchMode = AppLaunchMode()
        let store: StatusStore

        switch launchMode {
        case .live:
            store = StatusStore(settingsPresenter: settingsWindowController)
        case .demo:
            store = StatusStore(
                client: DemoWorkflowRunFetcher(),
                credentialStore: DemoCredentialStore(),
                settingsPresenter: settingsWindowController,
                promptsForMissingToken: false,
                showsMissingTokenBanner: false
            )
        }

        settingsWindowController.store = store
        self.settingsWindowController = settingsWindowController
        _statusStore = StateObject(wrappedValue: store)

        DispatchQueue.main.async {
            store.start()
        }
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView(
                store: statusStore,
                showSettingsWindow: settingsWindowController.showSettings
            )
                .frame(width: 360)
                .onAppear {
                    statusStore.refreshNow()
                }
        } label: {
            MenuBarIconView(status: statusStore.combinedStatus)
        }
        .menuBarExtraStyle(.window)
    }
}
#else
import Foundation

@main
struct ActionMonitorCLI {
    static func main() async {
        let arguments = Array(CommandLine.arguments.dropFirst())

        if arguments.contains("--help") {
            print("""
            actionMonitor cloud test runner

            Usage:
              swift run actionMonitor --demo     # run with deterministic sample data
              swift run actionMonitor --live     # fetch GitHub Actions data using GITHUB_TOKEN if set
            """)
            return
        }

        let runner = CloudTestRunner(
            sites: SiteConfig.monitoredSites,
            fetcher: arguments.contains("--live") ? GitHubClient() : DemoWorkflowRunFetcher(),
            token: ProcessInfo.processInfo.environment["GITHUB_TOKEN"]
        )

        await runner.run()
    }
}

private struct CloudTestRunner {
    let sites: [SiteConfig]
    let fetcher: any WorkflowRunFetching
    let token: String?

    func run() async {
        print("actionMonitor cloud test run")
        print("mode: \(fetcher is DemoWorkflowRunFetcher ? "demo" : "live")")

        for site in sites {
            do {
                if let run = try await fetcher.fetchLatestRun(for: site, token: token) {
                    let state = run.deployState(for: site)
                    let commit = state.shortCommitSHA ?? "n/a"
                    print("- \(site.displayName): \(state.statusText) [commit: \(commit)]")
                } else {
                    print("- \(site.displayName): No deploy runs found")
                }
            } catch {
                print("- \(site.displayName): ERROR - \(error.localizedDescription)")
            }
        }
    }
}

#endif
