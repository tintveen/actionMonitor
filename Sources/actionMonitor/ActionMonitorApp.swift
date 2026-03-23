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
            let demoStore = InMemoryMonitoredWorkflowStore(initialWorkflows: MonitoredWorkflow.demoWorkflows)
            store = StatusStore(
                workflows: MonitoredWorkflow.demoWorkflows,
                workflowStore: demoStore,
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
