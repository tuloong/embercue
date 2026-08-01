import AppKit

@MainActor
public final class StatusItemController {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let onShow: () -> Void
    private let onExport: () -> Void
    private let queueCountItem = NSMenuItem(title: "No prompts waiting", action: nil, keyEquivalent: "")

    public init(onShow: @escaping () -> Void, onExport: @escaping () -> Void) {
        self.onShow = onShow
        self.onExport = onExport
        item.button?.image = NSImage(systemSymbolName: "flame", accessibilityDescription: "Embercue")
        item.button?.image?.isTemplate = true
        item.button?.imagePosition = .imageLeading
        item.button?.title = WorkbenchLifecycleMenuTitles.menuBarTitle
        item.button?.toolTip = "Embercue"

        let menu = NSMenu()
        let showItem = menu.addItem(withTitle: "Show Embercue", action: #selector(open), keyEquivalent: "")
        showItem.target = self
        queueCountItem.isEnabled = false
        menu.addItem(queueCountItem)
        let exportItem = menu.addItem(withTitle: "Export Library Metadata…", action: #selector(exportLibrary), keyEquivalent: "")
        exportItem.target = self
        menu.addItem(.separator())
        let quitItem = menu.addItem(withTitle: "Quit Embercue", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        item.menu = menu
    }

    @_spi(Testing)
    public var statusButtonTitleForTesting: String { item.button?.title ?? "" }

    @_spi(Testing)
    public var menuItemsForTesting: [NSMenuItem] { item.menu?.items ?? [] }

    public func updateQueueCount(_ count: Int) {
        queueCountItem.title = count == 1 ? "1 prompt waiting" : "\(count) prompts waiting"
    }

    @objc private func open() { onShow() }
    @objc private func exportLibrary() { onExport() }
    @objc private func quit() { NSApp.terminate(nil) }
}
