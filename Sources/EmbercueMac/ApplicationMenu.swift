import AppKit

/// AppKit routes standard text-editing key equivalents through the main menu.
/// Embercue runs a manually bootstrapped accessory application, so it must
/// install this responder-chain surface explicitly.
@MainActor
public enum EmbercueApplicationMenu {
    public static func install(on application: NSApplication) {
        application.mainMenu = make()
    }

    public static func make() -> NSMenu {
        let mainMenu = NSMenu(title: "Main Menu")

        let applicationItem = NSMenuItem()
        applicationItem.submenu = applicationMenu()
        mainMenu.addItem(applicationItem)

        let editItem = NSMenuItem()
        editItem.submenu = editMenu()
        mainMenu.addItem(editItem)

        return mainMenu
    }

    private static func applicationMenu() -> NSMenu {
        let menu = NSMenu(title: "Embercue")
        menu.addItem(item("About Embercue", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:))))
        menu.addItem(.separator())
        menu.addItem(item("Hide Embercue", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h"))
        menu.addItem(item("Quit Embercue", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        return menu
    }

    private static func editMenu() -> NSMenu {
        let menu = NSMenu(title: "Edit")
        menu.addItem(item("Undo", action: Selector(("undo:")), keyEquivalent: "z"))
        menu.addItem(item("Redo", action: Selector(("redo:")), keyEquivalent: "z", modifiers: [.command, .shift]))
        menu.addItem(.separator())
        menu.addItem(item("Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        menu.addItem(item("Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        menu.addItem(item("Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        menu.addItem(item("Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        return menu
    }

    private static func item(
        _ title: String,
        action: Selector,
        keyEquivalent: String = "",
        modifiers: NSEvent.ModifierFlags = [.command]
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.keyEquivalentModifierMask = keyEquivalent.isEmpty ? [] : modifiers
        item.target = nil
        return item
    }
}
