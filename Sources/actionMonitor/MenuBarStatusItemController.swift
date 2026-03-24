import AppKit
import Combine
import SwiftUI

@MainActor
final class MenuBarStatusItemController: NSObject, ObservableObject {
    private enum Layout {
        static let iconSideLength: CGFloat = 13
        static let popoverWidth: CGFloat = 360
    }

    private let store: StatusStore
    private let statusItem: NSStatusItem
    private let popover: NSPopover
    private var cancellables: Set<AnyCancellable> = []

    init(store: StatusStore) {
        self.store = store
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        popover = NSPopover()

        super.init()

        configureStatusItem()
        configurePopover()
        bindStore()
        updateStatusItem(for: store.combinedStatus)
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else {
            return
        }

        button.target = self
        button.action = #selector(togglePopover(_:))
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        button.imageHugsTitle = true
        button.appearsDisabled = false
    }

    private func configurePopover() {
        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(width: Layout.popoverWidth, height: 10)
        popover.contentViewController = NSHostingController(
            rootView: MenuBarContentView(
                store: store,
                showSettingsWindow: { [weak self] in
                    self?.dismissPopover()
                    self?.store.showSettings()
                }
            )
            .frame(width: Layout.popoverWidth)
        )
    }

    private func bindStore() {
        store.$combinedStatus
            .receive(on: RunLoop.main)
            .sink { [weak self] status in
                self?.updateStatusItem(for: status)
            }
            .store(in: &cancellables)
    }

    private func updateStatusItem(for status: DeployStatus) {
        guard let button = statusItem.button else {
            return
        }

        let configuration = NSImage.SymbolConfiguration(
            pointSize: Layout.iconSideLength,
            weight: .semibold
        )

        let image = NSImage(
            systemSymbolName: status.symbolName,
            accessibilityDescription: status.accessibilityLabel
        )?.withSymbolConfiguration(configuration)

        image?.isTemplate = true
        image?.size = NSSize(width: Layout.iconSideLength, height: Layout.iconSideLength)

        button.image = image
        button.toolTip = status.accessibilityLabel
        button.contentTintColor = nil
    }

    @objc
    private func togglePopover(_ sender: AnyObject?) {
        if popover.isShown {
            dismissPopover()
        } else {
            showPopover(relativeTo: sender)
        }
    }

    private func showPopover(relativeTo sender: AnyObject?) {
        guard let button = statusItem.button else {
            return
        }

        store.refreshNow()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    private func dismissPopover() {
        popover.performClose(nil)
    }
}
