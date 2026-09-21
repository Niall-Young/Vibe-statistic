import AppKit

/// An arrowless menu-bar panel that dismisses when focus moves elsewhere.
@MainActor final class SummaryPanel: NSPanel {
    private var outsideClickMonitor: Any?

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 370, height: 630),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .popUpMenu
        collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        isReleasedWhenClosed = false
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    func show(below button: NSStatusBarButton) {
        guard let anchorWindow = button.window, let screen = anchorWindow.screen else { return }
        let anchor = anchorWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let visible = screen.visibleFrame.insetBy(dx: 8, dy: 8)
        let x = min(max(anchor.midX - frame.width / 2, visible.minX), visible.maxX - frame.width)
        let y = max(visible.minY, anchor.minY - frame.height - 6)
        setFrameOrigin(NSPoint(x: x, y: y))
        makeKeyAndOrderFront(nil)
        if outsideClickMonitor == nil {
            outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                self?.orderOut(nil)
            }
        }
    }

    override func resignKey() {
        super.resignKey()
        orderOut(nil)
    }

    override func cancelOperation(_ sender: Any?) { orderOut(sender) }

    override func orderOut(_ sender: Any?) {
        if let monitor = outsideClickMonitor {
            NSEvent.removeMonitor(monitor)
            outsideClickMonitor = nil
        }
        super.orderOut(sender)
    }
}
