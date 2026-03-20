import Foundation

@MainActor
protocol SettingsPresenting: Sendable {
    func showSettings()
}

struct NoOpSettingsPresenter: SettingsPresenting {
    func showSettings() {}
}

#if canImport(AppKit) && canImport(SwiftUI)
import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSObject, SettingsPresenting {
    weak var store: StatusStore?

    private var window: NSWindow?

    func showSettings() {
        guard let store else {
            return
        }

        let window = makeWindowIfNeeded(with: store)
        let rootView = SettingsView(store: store)
            .frame(width: 420, height: 280)
        let hostingController = NSHostingController(rootView: rootView)

        window.contentViewController = hostingController
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    private func makeWindowIfNeeded(with store: StatusStore) -> NSWindow {
        if let window {
            return window
        }

        let rootView = SettingsView(store: store)
            .frame(width: 420, height: 280)
        let hostingController = NSHostingController(rootView: rootView)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 280),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )

        window.title = "GitHub Settings"
        window.isReleasedWhenClosed = false
        window.center()
        window.setContentSize(NSSize(width: 420, height: 280))
        window.contentMinSize = NSSize(width: 420, height: 280)
        window.contentMaxSize = NSSize(width: 420, height: 280)
        window.contentViewController = hostingController

        self.window = window
        return window
    }
}
#endif
