import AppKit
import EmbercueCore
import SwiftUI

@MainActor
public final class ItemEditorController: NSObject, NSWindowDelegate {
    private var windows: [UUID: NSWindow] = [:]
    private weak var model: WorkbenchModel?

    public init(model: WorkbenchModel) { self.model = model }

    public func show(_ item: EmbercueCore.LibraryItem) {
        if let existing = windows[item.id] {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 330),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Edit note"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = NSHostingView(rootView: ItemEditorView(item: item, save: { [weak self] (text: String) in
            guard let self, let model = self.model else { return false }
            model.edit(item, text: text)
            return model.errorMessage == nil
        }, close: { [weak window] in window?.close() }))
        windows[item.id] = window
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    public func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        windows = windows.filter { $0.value !== window }
    }
}
