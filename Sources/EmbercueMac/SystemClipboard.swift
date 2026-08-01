import AppKit

public struct ClipboardPayload: Equatable {
    public let text: String?
    public let fileURLs: [URL]
    public init(text: String?, fileURLs: [URL] = []) { self.text = text; self.fileURLs = fileURLs }
}

public protocol SystemClipboard: AnyObject {
    /// A snapshot used only by a bounded, user-initiated copy operation to
    /// reject the clipboard value that existed before Command-C was sent.
    func changeCount() -> Int
    func readPlainText() -> String?
    func writePlainText(_ text: String) -> Bool
    func write(_ payload: ClipboardPayload) -> Bool
}

public extension SystemClipboard {
    func write(_ payload: ClipboardPayload) -> Bool {
        guard payload.fileURLs.isEmpty, let text = payload.text else { return false }
        return writePlainText(text)
    }
}

public final class NSPasteboardClipboard: SystemClipboard {
    private let pasteboard: NSPasteboard

    public init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    public func changeCount() -> Int { pasteboard.changeCount }

    public func readPlainText() -> String? {
        pasteboard.string(forType: .string)
    }

    public func writePlainText(_ text: String) -> Bool {
        pasteboard.clearContents()
        return pasteboard.setString(text, forType: .string)
    }

    public func write(_ payload: ClipboardPayload) -> Bool {
        guard payload.text != nil || !payload.fileURLs.isEmpty else { return false }
        pasteboard.clearContents()
        var objects: [any NSPasteboardWriting] = []
        if let text = payload.text { objects.append(text as NSString) }
        objects.append(contentsOf: payload.fileURLs.map { $0 as NSURL })
        return pasteboard.writeObjects(objects)
    }
}
