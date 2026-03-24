import AppKit
import SwiftUI

@main
struct ActionMonitorApp: App {
    @StateObject private var statusStore: StatusStore
    @StateObject private var menuBarController: MenuBarStatusItemController
    private let settingsWindowController: SettingsWindowController

    init() {
        NSWindow.allowsAutomaticWindowTabbing = false
        NSApplication.shared.setActivationPolicy(.accessory)

        let settingsWindowController = SettingsWindowController()
        let launchMode = AppLaunchMode()
        let store: StatusStore
        let credentialStore = CredentialStoreFactory.makeDefault()

        switch launchMode {
        case .live:
            store = StatusStore(
                settingsPresenter: settingsWindowController,
                authManager: GitHubAuthManager(credentialStore: credentialStore)
            )
        case .demo:
            let demoStore = InMemoryMonitoredWorkflowStore(initialWorkflows: MonitoredWorkflow.demoWorkflows)
            store = StatusStore(
                workflows: MonitoredWorkflow.demoWorkflows,
                workflowStore: demoStore,
                client: DemoWorkflowRunFetcher(),
                appSetupStore: DemoAppSetupStore(),
                settingsPresenter: settingsWindowController,
                authManager: GitHubAuthManager(
                    credentialStore: DemoCredentialStore(),
                    configuration: nil
                ),
                promptsForIncompleteSetup: false,
                showsMissingCredentialBanner: false
            )
        }

        settingsWindowController.store = store
        self.settingsWindowController = settingsWindowController
        _statusStore = StateObject(wrappedValue: store)
        _menuBarController = StateObject(wrappedValue: MenuBarStatusItemController(store: store))

        DispatchQueue.main.async {
            store.start()
        }
    }

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
