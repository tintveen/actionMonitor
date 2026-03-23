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
            .frame(minWidth: 620, minHeight: 560)
        let hostingController = NSHostingController(rootView: rootView)

        if NSApp.activationPolicy() != .regular {
            NSApp.setActivationPolicy(.regular)
        }

        window.contentViewController = hostingController
        NSApp.unhide(nil)
        NSApp.activate(ignoringOtherApps: true)
        NSRunningApplication.current.activate(options: [.activateAllWindows])
        window.makeKeyAndOrderFront(nil)
        window.makeMain()
        window.orderFrontRegardless()

        if let initialFirstResponder = firstEditableView(in: hostingController.view) {
            DispatchQueue.main.async {
                window.makeFirstResponder(initialFirstResponder)
            }
        }
    }

    private func makeWindowIfNeeded(with store: StatusStore) -> NSWindow {
        if let window {
            return window
        }

        let rootView = SettingsView(store: store)
            .frame(minWidth: 620, minHeight: 560)
        let hostingController = NSHostingController(rootView: rootView)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 620),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )

        window.title = "Settings"
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.center()
        window.setContentSize(NSSize(width: 680, height: 620))
        window.contentMinSize = NSSize(width: 620, height: 560)
        window.contentViewController = hostingController

        self.window = window
        return window
    }
}

private extension SettingsWindowController {
    func firstEditableView(in view: NSView) -> NSView? {
        if view is NSTextField {
            return view
        }

        for subview in view.subviews {
            if let editableSubview = firstEditableView(in: subview) {
                return editableSubview
            }
        }

        return nil
    }
}

extension SettingsWindowController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        guard NSApp.activationPolicy() != .accessory else {
            return
        }

        NSApp.setActivationPolicy(.accessory)
    }
}
#endif
