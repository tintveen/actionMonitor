import SwiftUI

@main
struct DeployBarApp: App {
    @StateObject private var statusStore: StatusStore

    init() {
        let store = StatusStore()
        _statusStore = StateObject(wrappedValue: store)

        DispatchQueue.main.async {
            store.start()
        }
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView(store: statusStore)
                .frame(width: 360)
                .onAppear {
                    statusStore.refreshNow()
                }
        } label: {
            MenuBarIconView(status: statusStore.combinedStatus)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(store: statusStore)
                .frame(width: 420)
        }
    }
}
