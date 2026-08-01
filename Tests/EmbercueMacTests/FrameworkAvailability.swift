#if canImport(XCTest)
import AppKit
import EmbercueCore
@_spi(Testing) import EmbercueMac
import XCTest

@MainActor
final class EmbercueMacTests: XCTestCase {
    func testPointerSelectionResolverUsesOriginatingModifiers() {
        XCTAssertTrue(isReplace(WorkbenchSelectionModeResolver.mode(for: [])))
        XCTAssertTrue(isToggle(WorkbenchSelectionModeResolver.mode(for: [.command])))
        XCTAssertTrue(isExtend(WorkbenchSelectionModeResolver.mode(for: [.shift, .command, .capsLock])))
    }

    func testClipboardActionsAreExplicitAndCopyFailureDoesNotComplete() throws {
        let clipboard = FakeClipboard()
        let model = WorkbenchModel(engine: try LibraryEngine(repository: MemoryRepository()), clipboard: clipboard)
        model.draft = "prompt"
        model.queueDraft()
        let item = try XCTUnwrap(model.visibleItems.first)
        XCTAssertEqual(clipboard.reads, 0)
        clipboard.writeSucceeds = false
        XCTAssertFalse(model.copy(item))
        XCTAssertEqual(model.document.items[0].state, .active)
        clipboard.text = "keep"
        model.keepClipboard()
        XCTAssertEqual(clipboard.reads, 1)
    }

    func testComposerHashCommandCreatesAndSelectsSectionWithoutCapturingOtherMarkdown() throws {
        let model = WorkbenchModel(engine: try LibraryEngine(repository: MemoryRepository()), clipboard: FakeClipboard())
        model.draft = "# Switzerland Trip"
        model.submitDraft()
        let section = try XCTUnwrap(model.document.sections.first(where: { $0.name == "Switzerland Trip" }))
        XCTAssertEqual(model.captureSectionID, section.id)
        XCTAssertEqual(model.draft, "")

        model.draft = "# switzerland trip"
        model.submitDraft()
        XCTAssertEqual(model.draft, "# switzerland trip")
        XCTAssertNotNil(model.errorMessage)
        model.dismissError()

        model.draft = "## Still a note"
        model.submitDraft()
        XCTAssertTrue(model.document.items.contains(where: { $0.text == "## Still a note" }))
    }

    func testCopyAsListShowsCountOnlyAfterClipboardAndCompletionSucceed() throws {
        let repository = MemoryRepository()
        let model = WorkbenchModel(engine: try LibraryEngine(repository: repository), clipboard: FakeClipboard())
        model.draft = "one"
        model.submitDraft()
        let item = try XCTUnwrap(model.visibleItems.first)
        model.select(item)
        XCTAssertTrue(model.copyAsList())
        XCTAssertEqual(model.successMessage, "Copied × 1")
        XCTAssertTrue(model.inlineNoticeIsSuccess)
    }

    func testDoubleShiftStateCapturesOnlyASecondPressInsideTheWindow() {
        var state = DoubleShiftCaptureState()
        XCTAssertFalse(state.consume(shiftIsDown: true, at: 1))
        XCTAssertFalse(state.consume(shiftIsDown: true, at: 1.1))
        XCTAssertFalse(state.consume(shiftIsDown: false, at: 1.2))
        XCTAssertFalse(state.consume(shiftIsDown: true, at: 1.3))
        XCTAssertFalse(state.consume(shiftIsDown: false, at: 1.4))
        XCTAssertTrue(state.consume(shiftIsDown: true, at: 1.5))
        XCTAssertFalse(state.consume(shiftIsDown: false, at: 1.6))
        XCTAssertFalse(state.consume(shiftIsDown: true, at: 2.3))

        var interrupted = DoubleShiftCaptureState()
        XCTAssertFalse(interrupted.consume(modifierFlags: [.shift], at: 1))
        for modifier in [NSEvent.ModifierFlags.command, .option, .control, .function] {
            var modifierState = DoubleShiftCaptureState()
            XCTAssertFalse(modifierState.consume(modifierFlags: [.shift], at: 1))
            XCTAssertFalse(modifierState.consume(modifierFlags: [.shift, modifier], at: 1.1))
            XCTAssertFalse(modifierState.consume(modifierFlags: [], at: 1.2))
            XCTAssertFalse(modifierState.consume(modifierFlags: [.shift], at: 1.3))
        }
        XCTAssertFalse(interrupted.consume(modifierFlags: [.shift, .option], at: 1.1))
        XCTAssertFalse(interrupted.consume(modifierFlags: [], at: 1.2))
        XCTAssertFalse(interrupted.consume(modifierFlags: [.shift], at: 1.3))
        XCTAssertFalse(interrupted.consume(modifierFlags: [.shift], at: 1.4))
        XCTAssertFalse(interrupted.consume(modifierFlags: [], at: 1.5))
        XCTAssertFalse(interrupted.consume(modifierFlags: [.shift], at: 2))
        XCTAssertFalse(interrupted.consume(modifierFlags: [], at: 2.1))
        XCTAssertFalse(interrupted.consume(modifierFlags: [.shift], at: 1.9))
    }

    func testAccessibilitySelectionResolverUsesParentsAndRangeFallbacks() throws {
        XCTAssertEqual(
            try AccessibilitySelectionResolver.resolve([
                AccessibilitySelectionCandidate(),
                AccessibilitySelectionCandidate(directText: "parent selection")
            ]),
            "parent selection"
        )
        XCTAssertEqual(
            try AccessibilitySelectionResolver.resolve([
                AccessibilitySelectionCandidate(
                    selectedRange: CFRange(location: 5, length: 9),
                    rangedText: "range text"
                )
            ]),
            "range text"
        )
        XCTAssertEqual(
            try AccessibilitySelectionResolver.resolve([
                AccessibilitySelectionCandidate(
                    selectedRange: CFRange(location: 1, length: 3),
                    fullText: "A😀BC"
                )
            ]),
            "😀B"
        )
        XCTAssertEqual(
            try AccessibilitySelectionResolver.resolve([
                AccessibilitySelectionCandidate(selectedRange: CFRange(location: 0, length: 5), fullText: "focus"),
                AccessibilitySelectionCandidate(directText: "ancestor")
            ]),
            "focus",
            "a focused candidate full-text fallback must outrank an ancestor direct selection"
        )
        XCTAssertThrowsError(
            try AccessibilitySelectionResolver.resolve([
                AccessibilitySelectionCandidate(
                    selectedRange: CFRange(location: 0, length: 0),
                    fullText: "text"
                )
            ])
        ) { XCTAssertEqual($0 as? SelectedTextCaptureError, .emptySelection) }
        XCTAssertThrowsError(
            try AccessibilitySelectionResolver.resolve([AccessibilitySelectionCandidate()])
        ) { XCTAssertEqual($0 as? SelectedTextCaptureError, .unavailable) }
        XCTAssertThrowsError(
            try AccessibilitySelectionResolver.resolve([
                AccessibilitySelectionCandidate(
                    selectedRange: CFRange(location: -1, length: 3),
                    fullText: "text"
                )
            ])
        ) { XCTAssertEqual($0 as? SelectedTextCaptureError, .unavailable) }
        XCTAssertThrowsError(
            try AccessibilitySelectionResolver.resolve([
                AccessibilitySelectionCandidate(
                    selectedRange: CFRange(location: 1, length: 1),
                    fullText: "A😀B"
                )
            ])
        ) { XCTAssertEqual($0 as? SelectedTextCaptureError, .unavailable) }

        var providerCalls: [String] = []
        let providerCandidate = AccessibilitySelectionCandidateBuilder.make(
            directText: nil,
            selectedRange: CFRange(location: 0, length: 5),
            rangedText: { providerCalls.append("range"); return "range" },
            fullText: { providerCalls.append("full"); return "unused" }
        )
        XCTAssertEqual(try AccessibilitySelectionResolver.resolve([providerCandidate]), "range")
        XCTAssertEqual(providerCalls, ["range"])

        providerCalls.removeAll()
        let fullValueCandidate = AccessibilitySelectionCandidateBuilder.make(
            directText: nil,
            selectedRange: CFRange(location: 1, length: 3),
            rangedText: { providerCalls.append("range"); return nil },
            fullText: { providerCalls.append("full"); return "A😀BC" }
        )
        XCTAssertEqual(try AccessibilitySelectionResolver.resolve([fullValueCandidate]), "😀B")
        XCTAssertEqual(providerCalls, ["range", "full"])

        providerCalls.removeAll()
        _ = AccessibilitySelectionCandidateBuilder.make(
            directText: nil,
            selectedRange: CFRange(location: 0, length: 1),
            rangedText: { providerCalls.append("range"); return "   " },
            fullText: { providerCalls.append("full"); return "A" }
        )
        XCTAssertEqual(providerCalls, ["range", "full"])

        XCTAssertThrowsError(
            try AccessibilitySelectionResolver.resolve([
                AccessibilitySelectionCandidate(
                    selectedRange: CFRange(location: 1, length: 1),
                    fullText: "Ae\u{301}B"
                )
            ])
        ) { XCTAssertEqual($0 as? SelectedTextCaptureError, .unavailable) }

        let parentNode = TestAccessibilitySelectionNode(candidate: AccessibilitySelectionCandidate(directText: "parent selection"))
        let focusedNode = TestAccessibilitySelectionNode()
        focusedNode.parent = parentNode
        parentNode.parent = focusedNode
        let walkedCandidates = AccessibilitySelectionTraversal.candidates(
            startingAt: focusedNode,
            maximumDepth: 16,
            equals: { $0 === $1 },
            candidate: { $0.candidate },
            parent: { $0.parent }
        )
        XCTAssertEqual(try AccessibilitySelectionResolver.resolve(walkedCandidates), "parent selection")
        XCTAssertEqual(walkedCandidates.count, 2)
    }

    func testSelectedTextCapturePermissionLifecycle() throws {
        let reader = TestSelectedTextReader()
        let monitor = TestDoubleShiftMonitor()
        let preferences = TestDoubleShiftCapturePreferences()
        let model = WorkbenchModel(engine: try LibraryEngine(repository: MemoryRepository()), clipboard: FakeClipboard())
        var captures: [String] = []
        let coordinator = SelectedTextCaptureCoordinator(
            reader: reader,
            monitor: monitor,
            preferences: preferences,
            capture: { captures.append($0) },
            statusChanged: { model.setSelectedTextCaptureStatus($0) },
            captureConfirmation: { true }
        )

        coordinator.restore()
        XCTAssertEqual(coordinator.status, .disabled)
        XCTAssertEqual(model.selectedTextCaptureStatus, .disabled)
        XCTAssertEqual(reader.requestTrustCalls, 0)

        coordinator.performMenuAction()
        XCTAssertEqual(coordinator.status, .awaitingPermission)
        XCTAssertEqual(model.selectedTextCaptureStatus, .awaitingPermission)
        XCTAssertTrue(preferences.doubleShiftCaptureEnabled)
        XCTAssertEqual(reader.requestTrustCalls, 1)
        XCTAssertEqual(monitor.starts, 0)
        XCTAssertEqual(SelectedTextCaptureStatus.awaitingPermission.menuTitle, "Waiting for Accessibility… (Cancel Setup)")

        reader.isTrusted = true
        coordinator.refreshAuthorization()
        coordinator.refreshAuthorization()
        XCTAssertEqual(coordinator.status, .enabled)
        XCTAssertEqual(model.selectedTextCaptureStatus, .enabled)
        XCTAssertEqual(monitor.starts, 1)
        monitor.trigger()
        XCTAssertEqual(captures, ["captured text"])

        reader.isTrusted = false
        coordinator.refreshAuthorization()
        XCTAssertEqual(coordinator.status, .awaitingPermission)
        XCTAssertEqual(model.selectedTextCaptureStatus, .awaitingPermission)
        XCTAssertEqual(monitor.stops, 1)
        coordinator.performMenuAction()
        XCTAssertEqual(coordinator.status, .disabled)
        XCTAssertEqual(model.selectedTextCaptureStatus, .disabled)
        XCTAssertFalse(preferences.doubleShiftCaptureEnabled)
        coordinator.performMenuAction()
        XCTAssertEqual(reader.requestTrustCalls, 2)

        let trustedReader = TestSelectedTextReader(); trustedReader.isTrusted = true
        let trustedMonitor = TestDoubleShiftMonitor()
        let trustedPreferences = TestDoubleShiftCapturePreferences(); trustedPreferences.doubleShiftCaptureEnabled = true
        let trustedLaunch = SelectedTextCaptureCoordinator(reader: trustedReader, monitor: trustedMonitor, preferences: trustedPreferences, capture: { _ in })
        trustedLaunch.restore()
        XCTAssertEqual(trustedLaunch.status, .enabled)
        XCTAssertEqual(trustedMonitor.starts, 1)
        XCTAssertEqual(trustedReader.requestTrustCalls, 0)

        let untrustedReader = TestSelectedTextReader()
        let untrustedMonitor = TestDoubleShiftMonitor()
        let untrustedPreferences = TestDoubleShiftCapturePreferences(); untrustedPreferences.doubleShiftCaptureEnabled = true
        let untrustedLaunch = SelectedTextCaptureCoordinator(reader: untrustedReader, monitor: untrustedMonitor, preferences: untrustedPreferences, capture: { _ in })
        untrustedLaunch.restore()
        XCTAssertEqual(untrustedLaunch.status, .awaitingPermission)
        XCTAssertEqual(untrustedMonitor.starts, 0)
        XCTAssertEqual(untrustedReader.requestTrustCalls, 0)

        let captureReader = TestSelectedTextReader(); captureReader.isTrusted = true
        let captureMonitor = TestDoubleShiftMonitor()
        let capturePreferences = TestDoubleShiftCapturePreferences(); capturePreferences.doubleShiftCaptureEnabled = true
        let captureCoordinator = SelectedTextCaptureCoordinator(reader: captureReader, monitor: captureMonitor, preferences: capturePreferences, capture: { _ in })
        captureCoordinator.restore()
        captureReader.isTrusted = false
        captureMonitor.trigger()
        XCTAssertEqual(captureCoordinator.status, .awaitingPermission)
        XCTAssertEqual(captureMonitor.stops, 1)
        XCTAssertEqual(captureReader.selectedTextCalls, 0)

        XCTAssertEqual(SelectedTextCaptureStatus.disabled.menuTitle, "Enable Double-Shift Capture…")
        XCTAssertEqual(SelectedTextCaptureStatus.awaitingPermission.menuTitle, "Waiting for Accessibility… (Cancel Setup)")
        XCTAssertEqual(SelectedTextCaptureStatus.enabled.menuTitle, "Disable Double-Shift Capture")
    }

    func testSelectedTextCaptureEdgesAndActivationRelay() {
        let enabledReader = TestSelectedTextReader(); enabledReader.isTrusted = true
        let enabledMonitor = TestDoubleShiftMonitor()
        let enabledPreferences = TestDoubleShiftCapturePreferences(); enabledPreferences.doubleShiftCaptureEnabled = true
        var captures = 0
        let enabledCoordinator = SelectedTextCaptureCoordinator(reader: enabledReader, monitor: enabledMonitor, preferences: enabledPreferences, capture: { _ in captures += 1 })
        enabledCoordinator.restore()
        enabledCoordinator.performMenuAction()
        enabledMonitor.trigger()
        XCTAssertEqual(enabledCoordinator.status, .disabled)
        XCTAssertFalse(enabledPreferences.doubleShiftCaptureEnabled)
        XCTAssertEqual(enabledMonitor.stops, 1)
        XCTAssertEqual(captures, 0)

        let stoppedReader = TestSelectedTextReader(); stoppedReader.isTrusted = true
        let stoppedMonitor = TestDoubleShiftMonitor()
        let stoppedPreferences = TestDoubleShiftCapturePreferences(); stoppedPreferences.doubleShiftCaptureEnabled = true
        let stoppedCoordinator = SelectedTextCaptureCoordinator(reader: stoppedReader, monitor: stoppedMonitor, preferences: stoppedPreferences, capture: { _ in })
        stoppedCoordinator.restore()
        stoppedCoordinator.stop()
        XCTAssertEqual(stoppedCoordinator.status, .enabled)
        XCTAssertTrue(stoppedPreferences.doubleShiftCaptureEnabled)
        XCTAssertEqual(stoppedMonitor.stops, 1)

        let errorReader = TestSelectedTextReader(); errorReader.isTrusted = true; errorReader.selectedTextFailure = SelectedTextCaptureError.emptySelection
        let errorMonitor = TestDoubleShiftMonitor()
        let errorPreferences = TestDoubleShiftCapturePreferences(); errorPreferences.doubleShiftCaptureEnabled = true
        var errors: [Error] = []
        var recovered: [String] = []
        let errorCoordinator = SelectedTextCaptureCoordinator(reader: errorReader, monitor: errorMonitor, preferences: errorPreferences, capture: { recovered.append($0) }, reportError: { errors.append($0) })
        errorCoordinator.restore()
        errorMonitor.trigger()
        errorReader.selectedTextFailure = nil
        errorMonitor.trigger()
        XCTAssertEqual(errorCoordinator.status, .enabled)
        XCTAssertEqual(errors.first as? SelectedTextCaptureError, .emptySelection)
        XCTAssertEqual(recovered, ["captured text"])

        let failedReader = TestSelectedTextReader(); failedReader.isTrusted = true
        let failedMonitor = TestDoubleShiftMonitor(); failedMonitor.startSucceeds = false
        let failedPreferences = TestDoubleShiftCapturePreferences()
        var failedErrors: [Error] = []
        let failedCoordinator = SelectedTextCaptureCoordinator(reader: failedReader, monitor: failedMonitor, preferences: failedPreferences, capture: { _ in }, reportError: { failedErrors.append($0) })
        failedCoordinator.performMenuAction()
        XCTAssertEqual(failedCoordinator.status, .disabled)
        XCTAssertFalse(failedPreferences.doubleShiftCaptureEnabled)
        XCTAssertEqual(failedErrors.first as? SelectedTextCaptureError, .monitorUnavailable)
        failedMonitor.startSucceeds = true
        failedCoordinator.performMenuAction()
        XCTAssertEqual(failedCoordinator.status, .enabled)
        XCTAssertEqual(failedMonitor.starts, 2)

        let suiteName = "EmbercueMacTests.SelectedTextCapture.\(UUID().uuidString)"
        let firstDefaults = UserDefaults(suiteName: suiteName)!
        firstDefaults.removePersistentDomain(forName: suiteName)
        defer { firstDefaults.removePersistentDomain(forName: suiteName) }
        firstDefaults.set(true, forKey: "selectedTextCaptureEnabled")
        XCTAssertFalse(UserDefaultsDoubleShiftCapturePreferences(defaults: UserDefaults(suiteName: suiteName)!).doubleShiftCaptureEnabled)

        let activationReader = TestSelectedTextReader()
        let activationMonitor = TestDoubleShiftMonitor()
        let activationPreferences = TestDoubleShiftCapturePreferences(); activationPreferences.doubleShiftCaptureEnabled = true
        let activationCoordinator = SelectedTextCaptureCoordinator(reader: activationReader, monitor: activationMonitor, preferences: activationPreferences, capture: { _ in })
        activationCoordinator.restore()
        let relay = ApplicationDidBecomeActiveRelay()
        var activationCallbacks = 0
        relay.start {
            activationCallbacks += 1
            activationCoordinator.refreshAuthorization()
        }
        activationReader.isTrusted = true
        NotificationCenter.default.post(name: NSApplication.didBecomeActiveNotification, object: NSApp)
        XCTAssertEqual(activationCallbacks, 1, "didBecomeActive relay must refresh authorization synchronously on the main queue")
        let firstActivationDeadline = Date().addingTimeInterval(1)
        while activationCallbacks < 1 && Date() < firstActivationDeadline {
            RunLoop.current.run(until: min(firstActivationDeadline, Date().addingTimeInterval(0.01)))
        }
        XCTAssertEqual(activationCallbacks, 1, "first didBecomeActive relay callback must arrive before its deadline")
        NotificationCenter.default.post(name: NSApplication.didBecomeActiveNotification, object: NSApp)
        let secondActivationDeadline = Date().addingTimeInterval(1)
        while activationCallbacks < 2 && Date() < secondActivationDeadline {
            RunLoop.current.run(until: min(secondActivationDeadline, Date().addingTimeInterval(0.01)))
        }
        relay.stop()
        XCTAssertEqual(activationCallbacks, 2, "second didBecomeActive relay callback must arrive before its deadline")
        NotificationCenter.default.post(name: NSApplication.didBecomeActiveNotification, object: NSApp)
        XCTAssertEqual(activationCallbacks, 2, "stopped activation relays must not invoke a deferred callback")
        XCTAssertEqual(activationCoordinator.status, .enabled)
        XCTAssertEqual(activationMonitor.starts, 1)
    }

    func testUnifiedDoubleShiftCaptureUsesOnlyPostCopyText() throws {
        let reader = TestSelectedTextReader(); reader.isTrusted = true
        let monitor = TestDoubleShiftMonitor()
        let preferences = TestDoubleShiftCapturePreferences(); preferences.doubleShiftCaptureEnabled = true
        let copier = TestAutomaticSelectionCopier()
        var captures: [String] = []
        var errors: [Error] = []
        let coordinator = SelectedTextCaptureCoordinator(
            reader: reader,
            monitor: monitor,
            preferences: preferences,
            automaticSelectionCopier: copier,
            capture: { captures.append($0) },
            reportError: { errors.append($0) }
        )

        coordinator.restore()
        reader.selectedTextFailure = SelectedTextCaptureError.unavailable
        monitor.trigger()
        XCTAssertEqual(copier.copies, 1)
        copier.finish(.failure(SelectedTextCaptureError.automaticCopyTimedOut))
        XCTAssertTrue(captures.isEmpty)
        XCTAssertEqual(errors.last as? SelectedTextCaptureError, .automaticCopyTimedOut)

        monitor.trigger()
        copier.finish(.success("newly copied selection"))
        XCTAssertEqual(captures, ["newly copied selection"])
        XCTAssertTrue(AutomaticSelectionCopyTarget.isEligible(frontmostBundleIdentifier: "com.example.editor", frontmostProcessIdentifier: 42, embercueBundleIdentifier: "com.embercue.app", embercueProcessIdentifier: 1))
        XCTAssertEqual(AutomaticSelectionCopyPasteboardChange.classify(before: 10, after: 11), .exactlyOne)
        XCTAssertEqual(AutomaticSelectionCopyPasteboardChange.classify(before: 10, after: 12), .unexpected)

        let defaultsName = "EmbercueMacTests.UnifiedDoubleShift.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: defaultsName)!
        defaults.removePersistentDomain(forName: defaultsName)
        defer { defaults.removePersistentDomain(forName: defaultsName) }
        defaults.set(true, forKey: "selectedTextCaptureEnabled")
        XCTAssertFalse(UserDefaultsDoubleShiftCapturePreferences(defaults: defaults).doubleShiftCaptureEnabled)
    }

    func testAdapterSeamsCoverHotKeyForegroundAndPlacement() {
        let hotKey = FakeHotKey(fails: true)
        let coordinator = HotKeyAvailabilityCoordinator(hotKey: hotKey)
        var menuCompositions = 0
        coordinator.composeMenuFallback { menuCompositions += 1 }
        XCTAssertNotNil(coordinator.start(action: {}))
        XCTAssertTrue(coordinator.menuFallbackAvailable)
        XCTAssertEqual(menuCompositions, 1)
        XCTAssertEqual(hotKey.stopCalls, 1)

        let application = FakeApplication(bundleIdentifier: "com.example.other", processIdentifier: 42)
        var frontmost: (any ForegroundApplication)? = application
        let tracker = ForegroundApplicationTracker(frontmostApplication: { frontmost }, ownProcessIdentifier: 1)
        tracker.capturePreviousApplication(ignoring: "com.embercue.app")
        tracker.reactivatePreviousApplication()
        tracker.reactivatePreviousApplication()
        XCTAssertEqual(application.activations, 1)
        frontmost = FakeApplication(bundleIdentifier: "com.embercue.app", processIdentifier: 1)
        tracker.capturePreviousApplication(ignoring: "com.embercue.app")
        tracker.reactivatePreviousApplication()
        XCTAssertEqual(application.activations, 1)

        let screenFrames = [CGRect(x: 0, y: 0, width: 100, height: 100), CGRect(x: 100, y: 0, width: 100, height: 100)]
        XCTAssertEqual(RightEdgePlacement.selectedScreenIndex(pointer: CGPoint(x: 150, y: 20), screenFrames: screenFrames, fallbackIndex: 0), 1)
        let largeVisibleFrame = CGRect(x: 100, y: 50, width: 1400, height: 1000)
        let defaultFrame = RightEdgePlacement.constrainedFrame(visibleFrame: largeVisibleFrame, panelSize: RightEdgePlacement.defaultPanelSize)
        XCTAssertEqual(defaultFrame.size, RightEdgePlacement.defaultPanelSize)
        XCTAssertEqual(RightEdgePlacement.effectiveMinimumPanelSize(for: largeVisibleFrame), RightEdgePlacement.minimumPanelSize)
        XCTAssertEqual(defaultFrame.maxX, largeVisibleFrame.maxX - RightEdgePlacement.margin)
        XCTAssertEqual(defaultFrame.midY, largeVisibleFrame.midY)

        let shortVisibleFrame = CGRect(x: 100, y: 50, width: 1200, height: 650)
        let shortFrame = RightEdgePlacement.constrainedFrame(visibleFrame: shortVisibleFrame, panelSize: RightEdgePlacement.defaultPanelSize)
        XCTAssertTrue(shortVisibleFrame.contains(shortFrame))
        XCTAssertEqual(shortFrame.height, 626)

        let enlargedFrame = RightEdgePlacement.constrainedFrame(visibleFrame: largeVisibleFrame, panelSize: CGSize(width: 440, height: 860))
        XCTAssertEqual(enlargedFrame.size, CGSize(width: 440, height: 860))
        XCTAssertEqual(enlargedFrame.maxX, largeVisibleFrame.maxX - RightEdgePlacement.margin)

        let narrowVisibleFrame = CGRect(x: 100, y: 50, width: 340, height: 800)
        let narrowFrame = RightEdgePlacement.constrainedFrame(visibleFrame: narrowVisibleFrame, panelSize: RightEdgePlacement.defaultPanelSize)
        XCTAssertTrue(narrowVisibleFrame.contains(narrowFrame))
        XCTAssertEqual(narrowFrame.width, RightEdgePlacement.minimumPanelSize.width)
        XCTAssertEqual(narrowFrame.minX, narrowVisibleFrame.minX + 6)
        XCTAssertEqual(narrowFrame.maxX, narrowVisibleFrame.maxX - 6)

        let undersizedVisibleFrame = CGRect(x: 100, y: 50, width: 300, height: 500)
        let undersizedFrame = RightEdgePlacement.constrainedFrame(visibleFrame: undersizedVisibleFrame, panelSize: RightEdgePlacement.defaultPanelSize, inset: -12)
        XCTAssertTrue(undersizedVisibleFrame.contains(undersizedFrame))
        XCTAssertEqual(undersizedFrame.size, undersizedVisibleFrame.size)
        XCTAssertEqual(RightEdgePlacement.effectiveMinimumPanelSize(for: undersizedVisibleFrame), undersizedVisibleFrame.size)
        XCTAssertFalse(BackgroundResidencyPolicy.shouldTerminateAfterLastWindowClosed)
        XCTAssertFalse(BackgroundResidencyPolicy.shouldClosePanel)
    }

    func testRailShortcutFocusOwnershipPreservesTextEditing() {
        XCTAssertEqual(RailShortcutRouter.shortcut(characters: "\r", modifiers: []), .edit)
        XCTAssertEqual(RailShortcutRouter.shortcut(characters: "\n", modifiers: []), .edit)

        let textView = NSTextView()
        textView.string = "selected text"
        textView.setSelectedRange(NSRange(location: 0, length: 8))
        XCTAssertFalse(RailShortcutRouter.acceptsRailShortcut(.copy, firstResponder: textView))
        XCTAssertTrue(RailShortcutRouter.acceptsRailShortcut(.copyAsList, firstResponder: textView))
        XCTAssertFalse(RailShortcutRouter.acceptsRailShortcut(.edit, firstResponder: textView))

        textView.setSelectedRange(NSRange(location: 0, length: 0))
        XCTAssertTrue(RailShortcutRouter.acceptsRailShortcut(.copy, firstResponder: textView))
        XCTAssertFalse(RailShortcutRouter.acceptsRailShortcut(.copy, firstResponder: NSTextField()))
    }

    func testRailEditShortcutStartsInlineEditingForOneSelectedCard() throws {
        let model = WorkbenchModel(engine: try LibraryEngine(repository: MemoryRepository()), clipboard: FakeClipboard())
        model.draft = "edit me"
        model.submitDraft()
        let item = try XCTUnwrap(model.visibleItems.first)
        XCTAssertFalse(model.handleShortcut(.edit))
        model.select(item)

        XCTAssertTrue(model.handleShortcut(.edit))
        XCTAssertEqual(model.inlineEditID, item.id)
        XCTAssertEqual(model.inlineEditDraft, item.text)
    }
}

private func isReplace(_ mode: WorkbenchSelectionMode) -> Bool {
    if case .replace = mode { return true }
    return false
}

private func isToggle(_ mode: WorkbenchSelectionMode) -> Bool {
    if case .toggle = mode { return true }
    return false
}

private func isExtend(_ mode: WorkbenchSelectionMode) -> Bool {
    if case .extend = mode { return true }
    return false
}

private final class FakeClipboard: SystemClipboard {
    var text: String?
    var pasteboardChangeCount = 0
    var reads = 0
    var writeSucceeds = true
    func changeCount() -> Int { pasteboardChangeCount }
    func readPlainText() -> String? { reads += 1; return text }
    func writePlainText(_ text: String) -> Bool { writeSucceeds }
}

private final class MemoryRepository: LibraryRepository {
    var document = LibraryDocument()
    func load() throws -> LibraryLoadResult { LibraryLoadResult(document: document) }
    func save(_ document: LibraryDocument, expectedRevision: Int) throws { self.document = document }
    func export(_ document: LibraryDocument, to destination: URL) throws {}
}

private final class FakeHotKey: GlobalHotKeying {
    let fails: Bool
    var stopCalls = 0
    init(fails: Bool) { self.fails = fails }
    func start(action: @escaping @Sendable () -> Void) throws {
        if fails { throw GlobalHotKeyError.registration(-1) }
    }
    func stop() { stopCalls += 1 }
}

private final class FakeApplication: ForegroundApplication {
    let bundleIdentifier: String?
    let processIdentifier: pid_t
    var isTerminated = false
    var activations = 0
    init(bundleIdentifier: String?, processIdentifier: pid_t) {
        self.bundleIdentifier = bundleIdentifier
        self.processIdentifier = processIdentifier
    }
    func activate() { activations += 1 }
}

private final class TestSelectedTextReader: SelectedTextReading {
    var isTrusted = false
    var requestTrustCalls = 0
    var selectedTextCalls = 0
    var selectedTextValue = "captured text"
    var selectedTextFailure: Error?
    func requestTrust() -> Bool { requestTrustCalls += 1; return false }
    func selectedText() throws {
        selectedTextCalls += 1
        if let selectedTextFailure { throw selectedTextFailure }
        return selectedTextValue
    }
}

private struct TestSelectedTextUnexpectedError: Error {}

private final class TestAccessibilitySelectionNode {
    let candidate: AccessibilitySelectionCandidate
    var parent: TestAccessibilitySelectionNode?

    init(candidate: AccessibilitySelectionCandidate = AccessibilitySelectionCandidate()) {
        self.candidate = candidate
    }
}

@MainActor
private final class TestDoubleShiftMonitor: DoubleShiftMonitoring {
    var starts = 0
    var stops = 0
    var startSucceeds = true
    private var action: (@MainActor () -> Void)?
    func start(action: @escaping @MainActor () -> Void) -> Bool {
        starts += 1
        guard startSucceeds else { return false }
        self.action = action
        return true
    }
    func stop() { stops += 1; action = nil }
    func trigger() { action?() }
}

private final class TestDoubleShiftCapturePreferences: DoubleShiftCapturePreferences {
    var doubleShiftCaptureEnabled = false
}

private final class TestAutomaticCopyTargetSource {
    var frontmostProcessIdentifier: pid_t?
    func currentProcessIdentifier() -> pid_t? { frontmostProcessIdentifier }
}

@MainActor
private final class TestAutomaticSelectionCopier: AutomaticSelectionCopying {
    var copies = 0
    var cancellations = 0
    private var completion: (@MainActor (Result<String, Error>) -> Void)?
    func copySelection(completion: @escaping @MainActor (Result<String, Error>) -> Void) {
        copies += 1
        self.completion = completion
    }
    func cancelPendingCopy() { cancellations += 1; completion = nil }
    func finish(_ result: Result<String, Error>) { completion?(result) }
}
#else
// See EmbercueCoreTests/FrameworkAvailability.swift for the full-Xcode test fallback boundary.
enum EmbercueMacTestTarget {}
#endif
