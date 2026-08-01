import AppKit

/// Native window key routing for the rail. This is deliberately a responder
/// path, not a local/global event monitor, so AppKit text editing keeps first
/// refusal rights.
public enum RailShortcut: Equatable, Sendable {
    case copy, copyAsList, markDone, edit, editInNewWindow, mergeNotes
}

public enum RailShortcutRouter {
    public static func shortcut(characters: String?, modifiers: NSEvent.ModifierFlags) -> RailShortcut? {
        // Deliberately ignore device state such as Caps Lock, Fn and numeric
        // keypad. They must not make a documented command shortcut stop
        // working; only modifier keys that alter the command are relevant.
        let flags = modifiers.intersection([.command, .shift, .option, .control])
        switch (characters?.lowercased(), flags) {
        case ("c", [.command]): return .copy
        case ("c", [.command, .shift]): return .copyAsList
        case (" ", []): return .markDone
        case ("\r", []), ("\n", []): return .edit
        case ("\r", [.command]), ("\n", [.command]): return .editInNewWindow
        case ("m", [.command, .shift]): return .mergeNotes
        default: return nil
        }
    }

    @MainActor public static func acceptsRailShortcut(_ shortcut: RailShortcut, firstResponder: AnyObject?) -> Bool {
        if let textView = firstResponder as? NSTextView {
            // A selected text range owns Command-C. An empty selection has
            // nothing to copy, so the selected rail cards may handle it.
            if shortcut == .copy { return textView.selectedRange().length == 0 }
            // Command-Shift-C has no native text-copy equivalent. Return and
            // other typing-related commands must remain with the editor.
            return shortcut == .copyAsList
        }
        // NSTextField does not expose a reliable live selection range here;
        // preserve its native Command-C behavior rather than guessing.
        if firstResponder is NSTextField { return shortcut == .copyAsList }
        return true
    }
}
