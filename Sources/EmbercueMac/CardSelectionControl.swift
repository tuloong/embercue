import AppKit
import SwiftUI

@_spi(Testing) public enum WorkbenchSelectionModeResolver {
    public static func mode(for flags: NSEvent.ModifierFlags) -> WorkbenchSelectionMode {
        if flags.contains(.shift) { return .extend }
        if flags.contains(.command) { return .toggle }
        return .replace
    }
}

struct CardSelectionButton: NSViewRepresentable {
    let accessibilityIdentifier: String
    let accessibilityLabel: String
    let selected: Bool
    let fixedPointerMode: WorkbenchSelectionMode?
    let selection: (WorkbenchSelectionMode) -> Void
    let prepareContext: () -> Void
    @Binding var pressed: Bool

    func makeNSView(context: Context) -> NativeCardSelectionButton {
        let button = NativeCardSelectionButton(frame: .zero)
        configure(button)
        return button
    }

    func updateNSView(_ button: NativeCardSelectionButton, context: Context) {
        configure(button)
    }

    private func configure(_ button: NativeCardSelectionButton) {
        button.configure(
            accessibilityIdentifier: accessibilityIdentifier,
            accessibilityLabel: accessibilityLabel,
            selected: selected,
            fixedPointerMode: fixedPointerMode,
            selection: selection,
            prepareContext: prepareContext,
            pressed: { pressed = $0 }
        )
    }
}

struct CardContextCaptureSurface: NSViewRepresentable {
    let identifier: String
    let prepareContext: () -> Void

    func makeNSView(context: Context) -> NativeCardContextCaptureView {
        let view = NativeCardContextCaptureView(frame: .zero)
        view.setAccessibilityIdentifier(identifier)
        view.prepareContext = prepareContext
        return view
    }

    func updateNSView(_ view: NativeCardContextCaptureView, context: Context) {
        view.setAccessibilityIdentifier(identifier)
        view.prepareContext = prepareContext
    }
}

@_spi(Testing) public final class NativeCardSelectionButton: NSButton {
    private var pointerMode: WorkbenchSelectionMode?
    private var fixedPointerMode: WorkbenchSelectionMode?
    private var selection: ((WorkbenchSelectionMode) -> Void)?
    private var prepareContext: (() -> Void)?
    private var pressed: ((Bool) -> Void)?

    override public var acceptsFirstResponder: Bool { true }

    override public init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        title = ""
        isBordered = false
        setButtonType(.momentaryChange)
        target = self
        action = #selector(activateSelection)
        setAccessibilityRole(.button)
    }

    required init?(coder: NSCoder) { nil }

    func configure(
        accessibilityIdentifier: String,
        accessibilityLabel: String,
        selected: Bool,
        fixedPointerMode: WorkbenchSelectionMode?,
        selection: @escaping (WorkbenchSelectionMode) -> Void,
        prepareContext: @escaping () -> Void,
        pressed: @escaping (Bool) -> Void
    ) {
        self.fixedPointerMode = fixedPointerMode
        self.selection = selection
        self.prepareContext = prepareContext
        self.pressed = pressed
        setAccessibilityIdentifier(accessibilityIdentifier)
        setAccessibilityLabel(accessibilityLabel)
        setAccessibilityValue(selected ? "Selected" : "Not selected")
        setAccessibilitySelected(selected)
    }

    override public func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        pointerMode = fixedPointerMode ?? WorkbenchSelectionModeResolver.mode(for: event.modifierFlags)
        pressed?(true)
        defer {
            pointerMode = nil
            pressed?(false)
        }
        super.mouseDown(with: event)
    }

    override public func keyDown(with event: NSEvent) {
        pointerMode = nil
        super.keyDown(with: event)
    }

    override public func rightMouseDown(with event: NSEvent) {
        prepareContext?()
        super.rightMouseDown(with: event)
    }

    @objc private func activateSelection() {
        let mode = pointerMode ?? .replace
        pointerMode = nil
        selection?(mode)
    }
}

final class NativeCardContextCaptureView: NSView {
    var prepareContext: (() -> Void)?

    override public func hitTest(_ point: NSPoint) -> NSView? {
        guard bounds.contains(point) else { return nil }
        guard let event = NSApp.currentEvent, event.type == .rightMouseDown else { return nil }
        return self
    }

    override public func rightMouseDown(with event: NSEvent) {
        prepareContext?()
        if let menu {
            menu.popUp(positioning: nil, at: convert(event.locationInWindow, from: nil), in: self)
        } else {
            super.rightMouseDown(with: event)
        }
    }
}
