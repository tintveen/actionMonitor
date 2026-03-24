import Foundation

@MainActor
protocol SettingsPresenting: Sendable {
    func showSettings()
    func showOnboarding(startingAt step: OnboardingStep)
    func dismissOnboarding()
    func openExternalURL(_ url: URL)
}

struct NoOpSettingsPresenter: SettingsPresenting {
    func showSettings() {}
    func showOnboarding(startingAt step: OnboardingStep) {}
    func dismissOnboarding() {}
    func openExternalURL(_ url: URL) {}
}

#if canImport(AppKit) && canImport(SwiftUI)
import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSObject, SettingsPresenting {
    weak var store: StatusStore?

    private var settingsWindow: NSWindow?
    private var onboardingWindow: NSWindow?

    func showSettings() {
        guard let store else {
            return
        }

        if store.shouldRouteSettingsToOnboarding {
            showOnboarding(startingAt: store.onboardingStep ?? .welcome)
            return
        }

        dismissOnboarding()
        let window = makeSettingsWindowIfNeeded(with: store)
        let rootView = SettingsView(store: store)
            .frame(minWidth: 620, minHeight: 560)
        let hostingController = NSHostingController(rootView: rootView)
        window.contentViewController = hostingController
        show(window: window, focusing: hostingController.view)
    }

    func showOnboarding(startingAt step: OnboardingStep) {
        guard let store else {
            return
        }

        let window = makeOnboardingWindowIfNeeded(with: store)
        let rootView = OnboardingView(store: store)
            .frame(minWidth: 720, minHeight: 620)
        let hostingController = NSHostingController(rootView: rootView)
        window.contentViewController = hostingController
        show(window: window, focusing: hostingController.view)
    }

    func dismissOnboarding() {
        onboardingWindow?.orderOut(nil)
    }

    func openExternalURL(_ url: URL) {
        AuthDebugLogger.logExternalURLOpen(url)
        NSWorkspace.shared.open(url)
    }

    private func show(window: NSWindow, focusing view: NSView) {
        if NSApp.activationPolicy() != .regular {
            NSApp.setActivationPolicy(.regular)
        }

        NSApp.unhide(nil)
        NSApp.activate(ignoringOtherApps: true)
        NSRunningApplication.current.activate(options: [.activateAllWindows])
        window.makeKeyAndOrderFront(nil)
        window.makeMain()
        window.orderFrontRegardless()

        if let initialFirstResponder = firstEditableView(in: view) {
            DispatchQueue.main.async {
                window.makeFirstResponder(initialFirstResponder)
            }
        }
    }

    private func makeSettingsWindowIfNeeded(with store: StatusStore) -> NSWindow {
        if let settingsWindow {
            return settingsWindow
        }

        let rootView = SettingsView(store: store)
            .frame(minWidth: 620, minHeight: 560)
        let hostingController = NSHostingController(rootView: rootView)
        let window = baseWindow(
            title: "Settings",
            size: NSSize(width: 680, height: 620),
            minimumSize: NSSize(width: 620, height: 560),
            contentViewController: hostingController
        )

        settingsWindow = window
        return window
    }

    private func makeOnboardingWindowIfNeeded(with store: StatusStore) -> NSWindow {
        if let onboardingWindow {
            return onboardingWindow
        }

        let rootView = OnboardingView(store: store)
            .frame(minWidth: 720, minHeight: 620)
        let hostingController = NSHostingController(rootView: rootView)
        let window = baseWindow(
            title: "Set Up actionMonitor",
            size: NSSize(width: 780, height: 680),
            minimumSize: NSSize(width: 720, height: 620),
            contentViewController: hostingController
        )

        onboardingWindow = window
        return window
    }

    private func baseWindow(
        title: String,
        size: NSSize,
        minimumSize: NSSize,
        contentViewController: NSViewController
    ) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: size.width, height: size.height),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )

        window.title = title
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.center()
        window.setContentSize(size)
        window.contentMinSize = minimumSize
        window.contentViewController = contentViewController
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
