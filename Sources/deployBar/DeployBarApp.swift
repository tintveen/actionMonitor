#if canImport(AppKit) && canImport(SwiftUI)
import AppKit
import SwiftUI

@main
struct DeployBarApp: App {
    @StateObject private var statusStore: StatusStore
    private let settingsWindowController: SettingsWindowController

    init() {
        NSWindow.allowsAutomaticWindowTabbing = false

        let settingsWindowController = SettingsWindowController()
        let store = StatusStore(settingsPresenter: settingsWindowController)

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
struct DeployBarCLI {
    static func main() async {
        let arguments = Array(CommandLine.arguments.dropFirst())

        if arguments.contains("--help") {
            print("""
            deployBar cloud test runner

            Usage:
              swift run deployBar --demo     # run with deterministic sample data
              swift run deployBar --live     # fetch GitHub Actions data using GITHUB_TOKEN if set
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
        print("deployBar cloud test run")
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

private struct DemoWorkflowRunFetcher: WorkflowRunFetching {
    func fetchLatestRun(for site: SiteConfig, token: String?) async throws -> WorkflowRun? {
        let now = Date()

        if site.repo.contains("betreuung") {
            return WorkflowRun(
                htmlURL: URL(string: "https://github.com/\(site.owner)/\(site.repo)/actions/runs/1"),
                status: "completed",
                conclusion: "success",
                headSHA: "0123456789abcdef",
                createdAt: now.addingTimeInterval(-900),
                updatedAt: now.addingTimeInterval(-600),
                runStartedAt: now.addingTimeInterval(-870)
            )
        }

        return WorkflowRun(
            htmlURL: URL(string: "https://github.com/\(site.owner)/\(site.repo)/actions/runs/2"),
            status: "in_progress",
            conclusion: nil,
            headSHA: "fedcba9876543210",
            createdAt: now.addingTimeInterval(-300),
            updatedAt: now.addingTimeInterval(-120),
            runStartedAt: now.addingTimeInterval(-240)
        )
    }
}
#endif
