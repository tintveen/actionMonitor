import AppKit
import Combine
import SwiftUI

@MainActor
final class MenuBarStatusItemController: NSObject, ObservableObject {
    private enum Layout {
        static let iconSideLength: CGFloat = 18
        static let standardPopoverWidth: CGFloat = 360
    }

    private let store: StatusStore
    private let statusItem: NSStatusItem
    private let popover: NSPopover
    private let hostingController: NSHostingController<AnyView>
    private var cancellables: Set<AnyCancellable> = []

    init(store: StatusStore) {
        self.store = store
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        popover = NSPopover()
        hostingController = NSHostingController(rootView: Self.makeRootView(store: store, dismissPopover: nil))

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
        popover.contentViewController = hostingController
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

        let usesBrandedFallback = status == .unknown && store.showsFreshInstallAuthenticationCTA
        let image: NSImage?

        if usesBrandedFallback {
            image = Self.actionMonitorIconImage
        } else {
            let configuration = NSImage.SymbolConfiguration(
                pointSize: Layout.iconSideLength,
                weight: .semibold
            )

            image = NSImage(
                systemSymbolName: status.symbolName,
                accessibilityDescription: status.accessibilityLabel
            )?.withSymbolConfiguration(configuration)
            image?.isTemplate = true
            image?.size = NSSize(width: Layout.iconSideLength, height: Layout.iconSideLength)
        }

        button.image = image
        button.toolTip = usesBrandedFallback ? "Set up actionMonitor" : status.accessibilityLabel
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

        if store.showsFreshInstallAuthenticationCTA {
            DispatchQueue.main.async { [weak self] in
                self?.resizePopoverToFreshInstallContent()
            }
        }
    }

    private func dismissPopover() {
        popover.performClose(nil)
    }

    private func resizePopoverToFreshInstallContent() {
        guard popover.isShown, store.showsFreshInstallAuthenticationCTA else {
            return
        }

        hostingController.rootView = Self.makeRootView(store: store, dismissPopover: { [weak self] in
            self?.dismissPopover()
        })

        let fittingSize = hostingController.view.fittingSize
        let width = max(ceil(fittingSize.width), 10)
        let height = max(ceil(fittingSize.height), 10)
        popover.contentSize = NSSize(width: width, height: height)
    }

    private static func makeRootView(
        store: StatusStore,
        dismissPopover: (@MainActor @Sendable () -> Void)?
    ) -> AnyView {
        AnyView(
            MenuBarContentView(
                store: store,
                showSettingsWindow: {
                    dismissPopover?()
                    store.showSettings()
                }
            )
        )
    }

    private static var actionMonitorIconImage: NSImage {
        let size = NSSize(width: Layout.iconSideLength, height: Layout.iconSideLength)

        let image = NSImage(size: size, flipped: false) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else {
                return false
            }

            drawActionMonitorIcon(in: rect, context: context)
            return true
        }

        image.size = size
        image.isTemplate = false
        return image
    }

    private static func drawActionMonitorIcon(in rect: CGRect, context: CGContext) {
        let artBounds = CGRect(x: 250, y: 276, width: 524, height: 472)
        let scale = min(rect.width / artBounds.width, rect.height / artBounds.height)

        context.saveGState()
        context.translateBy(x: rect.midX, y: rect.midY)
        context.scaleBy(x: scale, y: scale)
        context.scaleBy(x: 1, y: -1)
        context.translateBy(x: -artBounds.midX, y: -artBounds.midY)
        context.setAllowsAntialiasing(true)
        context.setShouldAntialias(true)

        let ringColors = [
            NSColor(red: 0.12, green: 0.71, blue: 1.00, alpha: 1.0).cgColor,
            NSColor(red: 0.49, green: 1.00, blue: 0.31, alpha: 1.0).cgColor,
        ] as CFArray
        let checkColors = [
            NSColor(red: 0.12, green: 0.71, blue: 1.00, alpha: 1.0).cgColor,
            NSColor(red: 0.49, green: 1.00, blue: 0.31, alpha: 1.0).cgColor,
        ] as CFArray
        let gradientSpace = CGColorSpaceCreateDeviceRGB()

        context.saveGState()
        context.setShadow(offset: .zero, blur: 18, color: NSColor(calibratedWhite: 0, alpha: 0.22).cgColor)
        let ringPath = CGPath(ellipseIn: CGRect(x: 276, y: 276, width: 472, height: 472), transform: nil)
        context.addPath(ringPath)
        context.setLineWidth(34)
        context.setLineCap(.round)
        context.replacePathWithStrokedPath()
        context.clip()
        if let gradient = CGGradient(colorsSpace: gradientSpace, colors: ringColors, locations: [0, 1]) {
            context.drawLinearGradient(
                gradient,
                start: CGPoint(x: 250, y: 320),
                end: CGPoint(x: 774, y: 704),
                options: []
            )
        }
        context.restoreGState()

        context.saveGState()
        context.setShadow(offset: .zero, blur: 14, color: NSColor(calibratedWhite: 0, alpha: 0.18).cgColor)
        let checkPath = CGMutablePath()
        checkPath.move(to: CGPoint(x: 427, y: 510))
        checkPath.addLine(to: CGPoint(x: 493, y: 576))
        checkPath.addLine(to: CGPoint(x: 635, y: 434))
        context.addPath(checkPath)
        context.setLineWidth(38)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.replacePathWithStrokedPath()
        context.clip()
        if let gradient = CGGradient(colorsSpace: gradientSpace, colors: checkColors, locations: [0, 1]) {
            context.drawLinearGradient(
                gradient,
                start: CGPoint(x: 412, y: 470),
                end: CGPoint(x: 665, y: 625),
                options: []
            )
        }
        context.restoreGState()

        context.restoreGState()
    }
}
