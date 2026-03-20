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
