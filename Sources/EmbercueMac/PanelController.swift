import AppKit
import SwiftUI

private final class EmbercuePanel: NSPanel {
    var shortcutHandler: ((RailShortcut) -> Bool)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    private func handlesRailShortcut(_ event: NSEvent) -> Bool {
        if let shortcut = RailShortcutRouter.shortcut(characters: event.charactersIgnoringModifiers, modifiers: event.modifierFlags),
           RailShortcutRouter.acceptsRailShortcut(shortcut, firstResponder: firstResponder),
           shortcutHandler?(shortcut) == true {
            return true
        }
        return false
    }

    override func keyDown(with event: NSEvent) {
        if handlesRailShortcut(event) { return }
        super.keyDown(with: event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if handlesRailShortcut(event) { return true }
        return super.performKeyEquivalent(with: event)
    }
}

public enum BackgroundResidencyPolicy {
    public static let shouldTerminateAfterLastWindowClosed = false
    public static let shouldClosePanel = false
}

public enum RightEdgePlacement {
    public static let defaultPanelSize = NSSize(width: 364, height: 640)
    public static let minimumPanelSize = NSSize(width: 328, height: 520)
    public static let margin: CGFloat = 64

    public static func selectedScreenIndex(pointer: CGPoint, screenFrames: [CGRect], fallbackIndex: Int?) -> Int? {
        screenFrames.firstIndex(where: { $0.contains(pointer) }) ?? fallbackIndex.flatMap { screenFrames.indices.contains($0) ? $0 : nil } ?? screenFrames.indices.first
    }

    public static func effectiveMinimumPanelSize(for visibleFrame: CGRect) -> NSSize {
        NSSize(
            width: min(minimumPanelSize.width, max(0, visibleFrame.width)),
            height: min(minimumPanelSize.height, max(0, visibleFrame.height))
        )
    }

    public static func constrainedFrame(visibleFrame: CGRect, panelSize: CGSize, inset: CGFloat = RightEdgePlacement.margin) -> CGRect {
        let horizontal = constrainedDimension(
            visible: visibleFrame.width,
            requested: panelSize.width,
            minimum: minimumPanelSize.width,
            inset: inset
        )
        let vertical = constrainedDimension(
            visible: visibleFrame.height,
            requested: panelSize.height,
            minimum: minimumPanelSize.height,
            inset: inset
        )
        let size = CGSize(
            width: horizontal.size,
            height: vertical.size
        )
        let centeredY = visibleFrame.midY - size.height / 2
        let minimumY = visibleFrame.minY + vertical.inset
        let maximumY = visibleFrame.maxY - vertical.inset - size.height
        return CGRect(
            x: visibleFrame.maxX - horizontal.inset - size.width,
            y: min(max(centeredY, minimumY), maximumY),
            width: size.width,
            height: size.height
        )
    }

    private static func constrainedDimension(visible: CGFloat, requested: CGFloat, minimum: CGFloat, inset: CGFloat) -> (size: CGFloat, inset: CGFloat) {
        let extent = max(0, visible)
        let minimumSize = min(max(0, minimum), extent)
        let desiredInset = max(0, inset)
        let effectiveInset = min(desiredInset, max(0, (extent - minimumSize) / 2))
        let maximumSize = max(0, extent - effectiveInset * 2)
        return (min(max(max(0, requested), minimumSize), maximumSize), effectiveInset)
    }
}

@MainActor
public final class PanelController: NSObject, NSWindowDelegate {
    private let panel: NSPanel
    private let tracker: ForegroundApplicationTracker
    private let onShow: () -> Void
    private let onHide: () -> Void

    public init<Content: View>(rootView: Content, tracker: ForegroundApplicationTracker, appearance: NSAppearance? = nil, onShortcut: @escaping (RailShortcut) -> Bool = { _ in false }, onShow: @escaping () -> Void, onHide: @escaping () -> Void = {}) {
        self.tracker = tracker
        self.onShow = onShow
        self.onHide = onHide
        panel = EmbercuePanel(
            contentRect: NSRect(origin: .zero, size: RightEdgePlacement.defaultPanelSize),
            styleMask: [.borderless, .resizable],
            backing: .buffered,
            defer: false
        )
        super.init()

        panel.delegate = self
        (panel as? EmbercuePanel)?.shortcutHandler = onShortcut
        panel.isMovableByWindowBackground = true
        panel.backgroundColor = .clear
        panel.appearance = appearance
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.minSize = RightEdgePlacement.minimumPanelSize
        panel.maxSize = NSSize(width: 440, height: CGFloat.greatestFiniteMagnitude)
        panel.contentView = NSHostingView(rootView: rootView)
    }

    public func show(capturingPreviousApplication: Bool = true) {
        if capturingPreviousApplication { tracker.capturePreviousApplication() }
        placeAtRightEdge()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        onShow()
    }

    public func hide() { panel.orderOut(nil); onHide() }
    public func hideAndReturn() { panel.orderOut(nil); onHide(); tracker.reactivatePreviousApplication() }

    public func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        onHide()
        return BackgroundResidencyPolicy.shouldClosePanel
    }

    private func placeAtRightEdge() {
        let pointer = NSEvent.mouseLocation
        let screens = NSScreen.screens
        let fallback = NSScreen.main.flatMap { main in screens.firstIndex(where: { $0 === main }) }
        guard let index = RightEdgePlacement.selectedScreenIndex(pointer: pointer, screenFrames: screens.map(\.frame), fallbackIndex: fallback) else { return }
        let visibleFrame = screens[index].visibleFrame
        panel.minSize = RightEdgePlacement.effectiveMinimumPanelSize(for: visibleFrame)
        let frame = RightEdgePlacement.constrainedFrame(visibleFrame: visibleFrame, panelSize: panel.frame.size)
        panel.setFrame(frame, display: false)
    }
}
