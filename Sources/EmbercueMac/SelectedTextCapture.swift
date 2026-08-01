import ApplicationServices
import AppKit
import Foundation

public protocol SelectedTextReading: AnyObject {
    var isTrusted: Bool { get }
    func requestTrust() -> Bool
    func selectedText() throws -> String
}

public enum SelectedTextCaptureError: LocalizedError, Equatable {
    case permissionDenied
    case unavailable
    case emptySelection
    case monitorUnavailable
    case automaticCopyTargetUnavailable
    case automaticCopyFailed
    case automaticCopyTimedOut
    case automaticCopyWasEmpty
    case automaticCopyFocusChanged
    case automaticCopyPasteboardChangedUnexpectedly
    public var errorDescription: String? {
        switch self {
        case .permissionDenied: "Allow Accessibility for Embercue to capture selected text."
        case .unavailable: "The focused app does not expose selected text."
        case .emptySelection: "Select text before pressing Shift twice."
        case .monitorUnavailable: "Embercue could not start the double-Shift shortcut."
        case .automaticCopyTargetUnavailable: "Embercue could not safely send Command-C to the frontmost app."
        case .automaticCopyFailed: "Embercue could not send Command-C to the frontmost app."
        case .automaticCopyTimedOut: "The frontmost app did not place new text on the clipboard after Command-C."
        case .automaticCopyWasEmpty: "The frontmost app copied empty text."
        case .automaticCopyFocusChanged: "The frontmost app changed before Embercue could read the copied text."
        case .automaticCopyPasteboardChangedUnexpectedly: "The clipboard changed more than once after Command-C, so Embercue discarded it."
        }
    }
}

@_spi(Testing) public enum AutomaticSelectionCopyTarget {
    public static func isEligible(
        frontmostBundleIdentifier: String?,
        frontmostProcessIdentifier: pid_t,
        embercueBundleIdentifier: String?,
        embercueProcessIdentifier: pid_t
    ) -> Bool {
        guard frontmostProcessIdentifier > 0,
              frontmostProcessIdentifier != embercueProcessIdentifier else { return false }
        return frontmostBundleIdentifier != embercueBundleIdentifier
    }

    public static func isStillFrontmost(capturedProcessIdentifier: pid_t, currentProcessIdentifier: pid_t?) -> Bool {
        capturedProcessIdentifier > 0 && currentProcessIdentifier == capturedProcessIdentifier
    }
}

@_spi(Testing) public enum AutomaticSelectionCopyPasteboardChange: Equatable {
    case unchanged
    case exactlyOne
    case unexpected

    public static func classify(before: Int, after: Int) -> Self {
        guard after != before else { return .unchanged }
        guard before < Int.max, after == before + 1 else { return .unexpected }
        return .exactlyOne
    }
}

/// A single, consented Command-C attempt. Implementations may inspect the
/// pasteboard only until its change count differs from the pre-copy snapshot.
@MainActor
public protocol AutomaticSelectionCopying: AnyObject {
    func copySelection(completion: @escaping @MainActor (Result<String, Error>) -> Void)
    func cancelPendingCopy()
}

@MainActor
public final class FrontmostSelectionCopier: AutomaticSelectionCopying {
    private static let maximumChangeChecks = 6
    private static let changeCheckInterval: TimeInterval = 0.025

    private let clipboard: any SystemClipboard
    private let frontmostApplication: () -> NSRunningApplication?
    private let embercueBundleIdentifier: () -> String?
    private let embercueProcessIdentifier: () -> pid_t
    private var generation = 0
    private var pendingCheck: DispatchWorkItem?

    public convenience init(clipboard: any SystemClipboard) {
        self.init(
            clipboard: clipboard,
            frontmostApplication: { NSWorkspace.shared.frontmostApplication },
            embercueBundleIdentifier: { Bundle.main.bundleIdentifier },
            embercueProcessIdentifier: { ProcessInfo.processInfo.processIdentifier }
        )
    }

    @_spi(Testing) public init(
        clipboard: any SystemClipboard,
        frontmostApplication: @escaping () -> NSRunningApplication?,
        embercueBundleIdentifier: @escaping () -> String?,
        embercueProcessIdentifier: @escaping () -> pid_t
    ) {
        self.clipboard = clipboard
        self.frontmostApplication = frontmostApplication
        self.embercueBundleIdentifier = embercueBundleIdentifier
        self.embercueProcessIdentifier = embercueProcessIdentifier
    }

    public func copySelection(completion: @escaping @MainActor (Result<String, Error>) -> Void) {
        cancelPendingCopy()
        guard let target = frontmostApplication(),
              !target.isTerminated,
              AutomaticSelectionCopyTarget.isEligible(
                frontmostBundleIdentifier: target.bundleIdentifier,
                frontmostProcessIdentifier: target.processIdentifier,
                embercueBundleIdentifier: embercueBundleIdentifier(),
                embercueProcessIdentifier: embercueProcessIdentifier()
              ) else {
            completion(.failure(SelectedTextCaptureError.automaticCopyTargetUnavailable))
            return
        }

        let beforeCopyChangeCount = clipboard.changeCount()
        guard let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: 8, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: 8, keyDown: false) else {
            completion(.failure(SelectedTextCaptureError.automaticCopyFailed))
            return
        }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.postToPid(target.processIdentifier)
        keyUp.postToPid(target.processIdentifier)

        generation &+= 1
        scheduleChangeCheck(
            generation: generation,
            targetProcessIdentifier: target.processIdentifier,
            beforeCopyChangeCount: beforeCopyChangeCount,
            remainingChecks: Self.maximumChangeChecks,
            completion: completion
        )
    }

    public func cancelPendingCopy() {
        generation &+= 1
        pendingCheck?.cancel()
        pendingCheck = nil
    }

    private func scheduleChangeCheck(
        generation: Int,
        targetProcessIdentifier: pid_t,
        beforeCopyChangeCount: Int,
        remainingChecks: Int,
        completion: @escaping @MainActor (Result<String, Error>) -> Void
    ) {
        let check = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                self?.finishChangeCheck(
                    generation: generation,
                    targetProcessIdentifier: targetProcessIdentifier,
                    beforeCopyChangeCount: beforeCopyChangeCount,
                    remainingChecks: remainingChecks,
                    completion: completion
                )
            }
        }
        pendingCheck = check
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.changeCheckInterval, execute: check)
    }

    private func finishChangeCheck(
        generation: Int,
        targetProcessIdentifier: pid_t,
        beforeCopyChangeCount: Int,
        remainingChecks: Int,
        completion: @escaping @MainActor (Result<String, Error>) -> Void
    ) {
        guard generation == self.generation else { return }
        pendingCheck = nil
        guard AutomaticSelectionCopyTarget.isStillFrontmost(
            capturedProcessIdentifier: targetProcessIdentifier,
            currentProcessIdentifier: frontmostApplication()?.processIdentifier
        ) else {
            completion(.failure(SelectedTextCaptureError.automaticCopyFocusChanged))
            return
        }
        switch AutomaticSelectionCopyPasteboardChange.classify(
            before: beforeCopyChangeCount,
            after: clipboard.changeCount()
        ) {
        case .unchanged:
            guard remainingChecks > 1 else {
                completion(.failure(SelectedTextCaptureError.automaticCopyTimedOut))
                return
            }
            scheduleChangeCheck(
                generation: generation,
                targetProcessIdentifier: targetProcessIdentifier,
                beforeCopyChangeCount: beforeCopyChangeCount,
                remainingChecks: remainingChecks - 1,
                completion: completion
            )
        case .unexpected:
            completion(.failure(SelectedTextCaptureError.automaticCopyPasteboardChangedUnexpectedly))
        case .exactlyOne:
            guard let text = clipboard.readPlainText(), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                completion(.failure(SelectedTextCaptureError.automaticCopyWasEmpty))
                return
            }
            completion(.success(text))
        }
    }
}

@_spi(Testing) public struct AccessibilitySelectionCandidate {
    public let directText: String?
    public let selectedRange: CFRange?
    public let rangedText: String?
    public let fullText: String?

    public init(
        directText: String? = nil,
        selectedRange: CFRange? = nil,
        rangedText: String? = nil,
        fullText: String? = nil
    ) {
        self.directText = directText
        self.selectedRange = selectedRange
        self.rangedText = rangedText
        self.fullText = fullText
    }
}

@_spi(Testing) public enum AccessibilitySelectionCandidateBuilder {
    public static func make(
        directText: String?,
        selectedRange: CFRange?,
        rangedText: () -> String?,
        fullText: () -> String?
    ) -> AccessibilitySelectionCandidate {
        guard let selectedRange, selectedRange.location >= 0, selectedRange.length > 0 else {
            return AccessibilitySelectionCandidate(directText: directText, selectedRange: selectedRange)
        }

        let rangeText = rangedText()
        let valueText = rangeText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? nil
            : fullText()
        return AccessibilitySelectionCandidate(
            directText: directText,
            selectedRange: selectedRange,
            rangedText: rangeText,
            fullText: valueText
        )
    }
}

@_spi(Testing) public enum AccessibilitySelectionTraversal {
    public static func candidates<Node>(
        startingAt node: Node?,
        maximumDepth: Int,
        equals: (Node, Node) -> Bool,
        candidate: (Node) -> AccessibilitySelectionCandidate,
        parent: (Node) -> Node?
    ) -> [AccessibilitySelectionCandidate] {
        guard maximumDepth > 0 else { return [] }
        var candidates: [AccessibilitySelectionCandidate] = []
        var visited: [Node] = []
        var current = node

        while let node = current, candidates.count < maximumDepth,
              !visited.contains(where: { equals($0, node) }) {
            visited.append(node)
            candidates.append(candidate(node))
            current = parent(node)
        }
        return candidates
    }
}

@_spi(Testing) public enum AccessibilitySelectionResolver {
    public static func resolve(_ candidates: [AccessibilitySelectionCandidate]) throws -> String {
        var encounteredEmptySelection = false

        for candidate in candidates {
            if let directText = usableText(candidate.directText, encounteredEmptySelection: &encounteredEmptySelection) {
                return directText
            }
            guard let range = candidate.selectedRange else { continue }
            guard isNonempty(range) else {
                if range.location >= 0, range.length == 0 {
                    encounteredEmptySelection = true
                }
                continue
            }
            if let rangedText = usableText(candidate.rangedText, encounteredEmptySelection: &encounteredEmptySelection) {
                return rangedText
            }
            guard let fullText = candidate.fullText,
                  let selection = utf16Substring(fullText, range: range) else { continue }
            if let selection = usableText(selection, encounteredEmptySelection: &encounteredEmptySelection) {
                return selection
            }
        }

        throw encounteredEmptySelection ? SelectedTextCaptureError.emptySelection : SelectedTextCaptureError.unavailable
    }

    private static func usableText(_ text: String?, encounteredEmptySelection: inout Bool) -> String? {
        guard let text else { return nil }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            encounteredEmptySelection = true
            return nil
        }
        return text
    }

    private static func isNonempty(_ range: CFRange) -> Bool {
        range.location >= 0 && range.length > 0
    }

    private static func utf16Substring(_ text: String, range: CFRange) -> String? {
        guard range.location >= 0, range.length > 0,
              range.location <= CFIndex(Int.max), range.length <= CFIndex(Int.max) else { return nil }
        let location = Int(range.location)
        let length = Int(range.length)
        guard let substringRange = Range(NSRange(location: location, length: length), in: text),
              isCharacterBoundary(substringRange.lowerBound, in: text),
              isCharacterBoundary(substringRange.upperBound, in: text) else { return nil }
        return String(text[substringRange])
    }

    private static func isCharacterBoundary(_ index: String.Index, in text: String) -> Bool {
        index == text.endIndex || text.indices.contains(index)
    }
}

public final class AccessibilitySelectedTextReader: SelectedTextReading {
    private static let maximumParentDepth = 16

    public init() {}
    public var isTrusted: Bool { AXIsProcessTrusted() }
    public func requestTrust() -> Bool {
        AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt" as CFString: true] as CFDictionary)
    }
    public func selectedText() throws -> String {
        guard isTrusted else { throw SelectedTextCaptureError.permissionDenied }
        let system = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focusedElement = accessibilityElement(from: focused) else { throw SelectedTextCaptureError.unavailable }
        let directText = stringAttribute(kAXSelectedTextAttribute, of: focusedElement)
        if let directText, !directText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return directText
        }
        return try AccessibilitySelectionResolver.resolve(
            selectionCandidates(startingAt: focusedElement, focusedDirectText: directText)
        )
    }

    private func selectionCandidates(startingAt focusedElement: AXUIElement, focusedDirectText: String?) -> [AccessibilitySelectionCandidate] {
        var isFocusedElement = true
        return AccessibilitySelectionTraversal.candidates(
            startingAt: focusedElement,
            maximumDepth: Self.maximumParentDepth,
            equals: { CFEqual($0, $1) },
            candidate: { element in
                let directText: String?
                if isFocusedElement {
                    directText = focusedDirectText
                    isFocusedElement = false
                } else {
                    directText = self.stringAttribute(kAXSelectedTextAttribute, of: element)
                }
                return self.selectionCandidate(for: element, directText: directText)
            },
            parent: { self.parent(of: $0) }
        )
    }

    private func selectionCandidate(for element: AXUIElement, directText: String?) -> AccessibilitySelectionCandidate {
        let rangeValue = selectedRangeValue(of: element)
        let selectedRange = rangeValue.flatMap { range(from: $0) }
        return AccessibilitySelectionCandidateBuilder.make(
            directText: directText,
            selectedRange: selectedRange,
            rangedText: { [self] in
                guard let rangeValue else { return nil }
                return parameterizedString(for: rangeValue, of: element)
            },
            fullText: { [self] in stringAttribute(kAXValueAttribute, of: element) }
        )
    }

    private func stringAttribute(_ attribute: String, of element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    private func selectedRangeValue(of element: AXUIElement) -> AXValue? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &value) == .success else { return nil }
        guard let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        return unsafeDowncast(value, to: AXValue.self)
    }

    private func range(from value: AXValue) -> CFRange? {
        guard AXValueGetType(value) == .cfRange else { return nil }
        var range = CFRange()
        return AXValueGetValue(value, .cfRange, &range) ? range : nil
    }

    private func parameterizedString(for rangeValue: AXValue, of element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXStringForRangeParameterizedAttribute as CFString,
            rangeValue,
            &value
        ) == .success else { return nil }
        return value as? String
    }

    private func parent(of element: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXParentAttribute as CFString, &value) == .success else { return nil }
        return accessibilityElement(from: value)
    }

    private func accessibilityElement(from value: CFTypeRef?) -> AXUIElement? {
        guard let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return unsafeDowncast(value, to: AXUIElement.self)
    }
}

public struct DoubleShiftCaptureState: Equatable {
    private var firstPress: TimeInterval?
    private var shiftWasDown = false
    public init() {}

    public mutating func consume(shiftIsDown: Bool, at time: TimeInterval, interval: TimeInterval = 0.6) -> Bool {
        consume(modifierFlags: shiftIsDown ? [.shift] : [], at: time, interval: interval)
    }

    public mutating func consume(
        modifierFlags: NSEvent.ModifierFlags,
        at time: TimeInterval,
        interval: TimeInterval = 0.6
    ) -> Bool {
        let shiftIsDown = modifierFlags.contains(.shift)
        let forbiddenModifiers: NSEvent.ModifierFlags = [.command, .option, .control, .function]
        guard modifierFlags.intersection(forbiddenModifiers).isEmpty else {
            firstPress = nil
            shiftWasDown = shiftIsDown
            return false
        }
        guard shiftIsDown != shiftWasDown else {
            firstPress = nil
            return false
        }
        defer { shiftWasDown = shiftIsDown }
        guard shiftIsDown else { return false }
        guard let firstPress else {
            self.firstPress = time
            return false
        }
        guard time >= firstPress, time - firstPress <= interval else {
            self.firstPress = time >= firstPress ? time : nil
            return false
        }
        self.firstPress = nil
        return true
    }
}

@_spi(Testing) public struct ModifierEvent {
    public let modifierFlags: NSEvent.ModifierFlags
    public let timestamp: TimeInterval

    public init(modifierFlags: NSEvent.ModifierFlags, timestamp: TimeInterval) {
        self.modifierFlags = modifierFlags
        self.timestamp = timestamp
    }
}

@_spi(Testing) @MainActor public protocol ModifierEventSource: AnyObject {
    func addGlobalModifierMonitor(handler: @escaping (ModifierEvent) -> Void) -> Any?
    func addLocalModifierMonitor(handler: @escaping (ModifierEvent) -> Void) -> Any?
    func removeMonitor(_ token: Any)
}

@MainActor
private final class AppKitModifierEventSource: ModifierEventSource {
    func addGlobalModifierMonitor(handler: @escaping (ModifierEvent) -> Void) -> Any? {
        NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { event in
            handler(ModifierEvent(modifierFlags: event.modifierFlags, timestamp: event.timestamp))
        }
    }

    func addLocalModifierMonitor(handler: @escaping (ModifierEvent) -> Void) -> Any? {
        NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
            handler(ModifierEvent(modifierFlags: event.modifierFlags, timestamp: event.timestamp))
            return event
        }
    }

    func removeMonitor(_ token: Any) {
        NSEvent.removeMonitor(token)
    }
}

@MainActor
public protocol DoubleShiftMonitoring: AnyObject {
    @discardableResult func start(action: @escaping @MainActor () -> Void) -> Bool
    func stop()
}

@MainActor
public final class GlobalDoubleShiftMonitor: DoubleShiftMonitoring {
    private let eventSource: any ModifierEventSource
    private var globalToken: Any?
    private var localToken: Any?
    private var state = DoubleShiftCaptureState()
    private var generation = 0

    public convenience init() {
        self.init(eventSource: AppKitModifierEventSource())
    }

    @_spi(Testing) public init(eventSource: any ModifierEventSource) {
        self.eventSource = eventSource
    }

    public func start(action: @escaping @MainActor () -> Void) -> Bool {
        stop()
        generation &+= 1
        let registrationGeneration = generation
        let globalToken = eventSource.addGlobalModifierMonitor { [weak self] event in
            MainActor.assumeIsolated {
                self?.consume(event, generation: registrationGeneration, action: action)
            }
        }
        guard let globalToken else { return false }
        let localToken = eventSource.addLocalModifierMonitor { [weak self] event in
            MainActor.assumeIsolated {
                self?.consume(event, generation: registrationGeneration, action: action)
            }
        }
        guard let localToken else {
            eventSource.removeMonitor(globalToken)
            generation &+= 1
            state = DoubleShiftCaptureState()
            return false
        }
        self.globalToken = globalToken
        self.localToken = localToken
        return true
    }

    public func stop() {
        generation &+= 1
        if let globalToken { eventSource.removeMonitor(globalToken) }
        if let localToken { eventSource.removeMonitor(localToken) }
        globalToken = nil
        localToken = nil
        state = DoubleShiftCaptureState()
    }

    private func consume(_ event: ModifierEvent, generation: Int, action: @escaping @MainActor () -> Void) {
        guard generation == self.generation,
              state.consume(modifierFlags: event.modifierFlags, at: event.timestamp) else { return }
        action()
    }
}

public enum SelectedTextCaptureStatus: Equatable {
    case disabled
    case awaitingPermission
    case enabled

    public var menuTitle: String {
        switch self {
        case .disabled: "Enable Double-Shift Capture…"
        case .awaitingPermission: "Waiting for Accessibility… (Cancel Setup)"
        case .enabled: "Disable Double-Shift Capture"
        }
    }
}

public protocol DoubleShiftCapturePreferences: AnyObject {
    var doubleShiftCaptureEnabled: Bool { get set }
}

/// This key is deliberately separate from the legacy selection-only consent.
/// A prior selection opt-in never authorizes synthetic Command-C.
public final class UserDefaultsDoubleShiftCapturePreferences: DoubleShiftCapturePreferences {
    public static let key = "doubleShiftCaptureEnabled"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    public var doubleShiftCaptureEnabled: Bool {
        get { defaults.bool(forKey: Self.key) }
        set { defaults.set(newValue, forKey: Self.key) }
    }
}

@MainActor
enum DoubleShiftCaptureConsentAlert {
    static func requestEnable() -> Bool {
        let alert = NSAlert()
        alert.messageText = "Enable Double-Shift Capture?"
        alert.informativeText = "Embercue will request Accessibility access to read selected text after double Shift. If the focused app does not expose a selection, Embercue sends one Command-C to that same frontmost app and saves only a new nonblank plain-text clipboard value when focus remains unchanged and the clipboard changes exactly once. This changes the clipboard. Embercue does not read an existing clipboard value, activate apps, paste, submit, clear, restore, or monitor the clipboard."
        alert.addButton(withTitle: "Enable")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }
}

@MainActor
public final class SelectedTextCaptureCoordinator {
    public private(set) var status: SelectedTextCaptureStatus = .disabled

    private let reader: any SelectedTextReading
    private let monitor: any DoubleShiftMonitoring
    private let preferences: any DoubleShiftCapturePreferences
    private let automaticSelectionCopier: (any AutomaticSelectionCopying)?
    private let capture: (String) -> Void
    private let reportError: (Error) -> Void
    private let statusChanged: (SelectedTextCaptureStatus) -> Void
    private let captureConfirmation: () -> Bool
    private var isMonitoring = false
    private var hasRequestedTrust = false
    private var monitorGeneration = 0
    private var captureGeneration = 0

    public init(
        reader: any SelectedTextReading,
        monitor: any DoubleShiftMonitoring,
        preferences: any DoubleShiftCapturePreferences,
        automaticSelectionCopier: (any AutomaticSelectionCopying)? = nil,
        capture: @escaping (String) -> Void,
        reportError: @escaping (Error) -> Void = { _ in },
        statusChanged: @escaping (SelectedTextCaptureStatus) -> Void = { _ in },
        captureConfirmation: @escaping () -> Bool = { false }
    ) {
        self.reader = reader
        self.monitor = monitor
        self.preferences = preferences
        self.automaticSelectionCopier = automaticSelectionCopier
        self.capture = capture
        self.reportError = reportError
        self.statusChanged = statusChanged
        self.captureConfirmation = captureConfirmation
    }

    /// Restores prior user intent without showing the system Accessibility prompt.
    public func restore() { refreshAuthorization() }

    /// Handles the explicit menu action. While awaiting, this cancels the
    /// pending opt-in; a later Enable is a new, explicit prompt request.
    public func performMenuAction() {
        switch status {
        case .disabled:
            guard captureConfirmation() else { return }
            enable()
        case .awaitingPermission: disable()
        case .enabled: disable()
        }
    }

    public func enable() {
        preferences.doubleShiftCaptureEnabled = true
        guard !reader.isTrusted else {
            guard startMonitoringIfNeeded() else { return }
            transition(to: .enabled)
            return
        }
        stopMonitoring()
        transition(to: .awaitingPermission)
        guard !hasRequestedTrust else { return }
        hasRequestedTrust = true
        _ = reader.requestTrust()
    }

    /// Called when Embercue returns to the foreground. It rechecks trust but
    /// never prompts, including during launch restoration.
    public func refreshAuthorization() {
        guard preferences.doubleShiftCaptureEnabled else {
            stopMonitoring()
            transition(to: .disabled)
            return
        }
        guard reader.isTrusted else {
            stopMonitoring()
            transition(to: .awaitingPermission)
            return
        }
        guard startMonitoringIfNeeded() else { return }
        transition(to: .enabled)
    }

    public func disable() {
        preferences.doubleShiftCaptureEnabled = false
        hasRequestedTrust = false
        cancelPendingAutomaticCopy()
        stopMonitoring()
        transition(to: .disabled)
    }

    /// Keeps persisted intent intact while releasing the process-local monitor.
    public func stop() {
        cancelPendingAutomaticCopy()
        stopMonitoring()
    }

    private func startMonitoringIfNeeded() -> Bool {
        guard !isMonitoring else { return true }
        monitorGeneration &+= 1
        let registrationGeneration = monitorGeneration
        guard monitor.start(action: { [weak self] in
            guard let self, self.monitorGeneration == registrationGeneration else { return }
            self.captureSelectedText()
        }) else {
            preferences.doubleShiftCaptureEnabled = false
            transition(to: .disabled)
            reportError(SelectedTextCaptureError.monitorUnavailable)
            return false
        }
        isMonitoring = true
        return true
    }

    private func stopMonitoring() {
        cancelPendingAutomaticCopy()
        monitorGeneration &+= 1
        guard isMonitoring else { return }
        monitor.stop()
        isMonitoring = false
    }

    private func captureSelectedText() {
        guard preferences.doubleShiftCaptureEnabled, reader.isTrusted else {
            stopMonitoring()
            transition(to: preferences.doubleShiftCaptureEnabled ? .awaitingPermission : .disabled)
            return
        }
        cancelPendingAutomaticCopy()
        let captureGeneration = self.captureGeneration
        do { capture(try reader.selectedText()) }
        catch SelectedTextCaptureError.unavailable {
            guard let automaticSelectionCopier else {
                reportError(SelectedTextCaptureError.automaticCopyFailed)
                return
            }
            automaticSelectionCopier.copySelection { [weak self] result in
                guard let self,
                      self.captureGeneration == captureGeneration,
                      self.preferences.doubleShiftCaptureEnabled,
                      self.reader.isTrusted else { return }
                switch result {
                case let .success(text): self.capture(text)
                case let .failure(error): self.reportError(error)
                }
            }
        }
        catch { reportError(error) }
    }

    private func cancelPendingAutomaticCopy() {
        captureGeneration &+= 1
        automaticSelectionCopier?.cancelPendingCopy()
    }

    private func transition(to status: SelectedTextCaptureStatus) {
        guard self.status != status else { return }
        self.status = status
        statusChanged(status)
    }
}

@MainActor
public protocol ApplicationActivationRelaying: AnyObject {
    func start(action: @escaping @MainActor () -> Void)
    func stop()
}

@MainActor
public final class ApplicationDidBecomeActiveRelay: ApplicationActivationRelaying {
    private let notificationCenter: NotificationCenter
    private let application: NSApplication?
    private var observer: NSObjectProtocol?
    private var action: (@MainActor () -> Void)?

    public init(notificationCenter: NotificationCenter = .default, application: NSApplication? = NSApp) {
        self.notificationCenter = notificationCenter
        self.application = application
    }

    public func start(action: @escaping @MainActor () -> Void) {
        stop()
        self.action = action
        observer = notificationCenter.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: application,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.action?() }
        }
    }

    public func stop() {
        if let observer { notificationCenter.removeObserver(observer) }
        observer = nil
        action = nil
    }
}
