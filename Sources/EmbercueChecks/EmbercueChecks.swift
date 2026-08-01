import AppKit
import Darwin
import EmbercueCore
@_spi(Testing) import EmbercueMac
import Foundation
import SwiftUI

enum CheckFailure: Error { case failed(String) }
func require(_ condition: @autoclosure () -> Bool, _ message: String) throws { if !condition() { throw CheckFailure.failed(message) } }

final class MemoryRepository: LibraryRepository {
    var document = LibraryDocument()
    var fail = false
    func load() throws -> LibraryLoadResult { LibraryLoadResult(document: document) }
    func save(_ document: LibraryDocument, expectedRevision: Int) throws {
        if fail { throw LibraryRepositoryError.saveFailed("injected") }
        guard self.document.revision == expectedRevision else { throw LibraryRepositoryError.revisionConflict(expected: expectedRevision, actual: self.document.revision) }
        self.document = document
    }
    func export(_ document: LibraryDocument, to destination: URL) throws {}
}

@MainActor
private final class CardInteractionHarness {
    let model: WorkbenchModel
    let first: EmbercueCore.LibraryItem
    let second: EmbercueCore.LibraryItem
    let third: EmbercueCore.LibraryItem
    let destination: LibrarySection
    private let window: NSWindow

    init() throws {
        let source = try LibrarySection(name: "SELECTION", sortOrder: 2)
        destination = try LibrarySection(name: "DESTINATION", sortOrder: 3)
        let date = Date(timeIntervalSince1970: 1_700_000_002)
        first = try LibraryItem(kind: .prompt, text: "First selectable note", createdAt: date, updatedAt: date, sectionID: source.id, sortOrder: 0)
        second = try LibraryItem(kind: .prompt, text: "Second selectable note", createdAt: date.addingTimeInterval(1), updatedAt: date.addingTimeInterval(1), sectionID: source.id, sortOrder: 1)
        third = try LibraryItem(kind: .prompt, text: "Third selectable note", createdAt: date.addingTimeInterval(2), updatedAt: date.addingTimeInterval(2), sectionID: source.id, sortOrder: 2)
        let repository = MemoryRepository()
        repository.document = LibraryDocument(revision: 1, sections: LibraryDocument.builtInSections + [source, destination], items: [first, second, third])
        model = WorkbenchModel(engine: try LibraryEngine(repository: repository), clipboard: FakeClipboard())

        _ = NSApplication.shared
        window = NSWindow(
            contentRect: NSRect(x: -10_000, y: -10_000, width: 364, height: 640),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: WorkbenchView(model: model, onCopyAndReturn: {}, onExport: {}, onHide: {}))
        window.orderFrontRegardless()
        settle()
    }

    func close() {
        window.contentView = nil
        window.orderOut(nil)
        window.close()
    }

    func body(for item: EmbercueCore.LibraryItem) throws -> NativeCardSelectionButton {
        try button(identifier: "item-card-body-\(item.id.uuidString)")
    }

    func circle(for item: EmbercueCore.LibraryItem) throws -> NativeCardSelectionButton {
        try button(identifier: "item-card-circle-\(item.id.uuidString)")
    }

    func context(for item: EmbercueCore.LibraryItem) throws -> NSView {
        settle()
        let identifier = "item-card-context-\(item.id.uuidString)"
        guard let context = findView(in: window.contentView, identifier: identifier) else {
            throw CheckFailure.failed("offscreen hosting view could not find \(identifier)")
        }
        return context
    }

    func clickBody(_ item: EmbercueCore.LibraryItem, downFlags: NSEvent.ModifierFlags, upFlags: NSEvent.ModifierFlags) throws {
        try click(try body(for: item), downFlags: downFlags, upFlags: upFlags)
    }

    func clickCircle(_ item: EmbercueCore.LibraryItem, downFlags: NSEvent.ModifierFlags, upFlags: NSEvent.ModifierFlags) throws {
        try click(try circle(for: item), downFlags: downFlags, upFlags: upFlags)
    }

    func clickCircle(_ item: EmbercueCore.LibraryItem, at point: NSPoint) throws {
        try click(try circle(for: item), at: point, downFlags: [], upFlags: [])
    }

    func performClickBody(_ item: EmbercueCore.LibraryItem) throws {
        try body(for: item).performClick(nil)
        settle()
    }

    func bodyOwnsKeyboardFocus(_ item: EmbercueCore.LibraryItem) throws -> Bool {
        window.firstResponder === (try body(for: item))
    }

    private func button(identifier: String) throws -> NativeCardSelectionButton {
        settle()
        guard let button = findView(in: window.contentView, identifier: identifier) as? NativeCardSelectionButton else {
            throw CheckFailure.failed("offscreen hosting view could not find \(identifier)")
        }
        return button
    }

    private func click(_ button: NativeCardSelectionButton, at point: NSPoint? = nil, downFlags: NSEvent.ModifierFlags, upFlags: NSEvent.ModifierFlags) throws {
        let point = point ?? NSPoint(x: button.bounds.midX, y: button.bounds.midY)
        let location = button.convert(point, to: nil)
        guard let down = NSEvent.mouseEvent(with: .leftMouseDown, location: location, modifierFlags: downFlags, timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1),
              let up = NSEvent.mouseEvent(with: .leftMouseUp, location: location, modifierFlags: upFlags, timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 0) else {
            throw CheckFailure.failed("could not create in-process mouse events")
        }
        NSApp.postEvent(up, atStart: true)
        window.sendEvent(down)
        settle()
    }

    private func settle() {
        window.contentView?.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.01))
    }

    private func findView(in view: NSView?, identifier: String) -> NSView? {
        guard let view else { return nil }
        if view.accessibilityIdentifier() == identifier { return view }
        for subview in view.subviews {
            if let found = findView(in: subview, identifier: identifier) { return found }
        }
        return nil
    }

}

final class FakeClipboard: SystemClipboard {
    var text: String?
    var pasteboardChangeCount = 0
    var reads = 0
    var writes: [String] = []
    var payloads: [ClipboardPayload] = []
    var succeeds = true
    func changeCount() -> Int { pasteboardChangeCount }
    func readPlainText() -> String? { reads += 1; return text }
    func writePlainText(_ text: String) -> Bool { writes.append(text); return succeeds }
    func write(_ payload: ClipboardPayload) -> Bool { payloads.append(payload); return succeeds }
}

final class FakeHotKey: GlobalHotKeying {
    var fail = false; var starts = 0; var stops = 0
    func start(action: @escaping @Sendable () -> Void) throws { starts += 1; if fail { throw GlobalHotKeyError.registration(-1) } }
    func stop() { stops += 1 }
}
final class FakeForeground: ForegroundApplication {
    let bundleIdentifier: String?; let processIdentifier: pid_t; var isTerminated = false; var activations = 0
    init(_ bundleIdentifier: String?, _ processIdentifier: pid_t) { self.bundleIdentifier = bundleIdentifier; self.processIdentifier = processIdentifier }
    func activate() { activations += 1 }
}

final class FakeSelectedTextReader: SelectedTextReading {
    var isTrusted = false
    var requestTrustCalls = 0
    var selectedTextValue = "captured text"
    var selectedTextFailure: Error?
    var selectedTextCalls = 0

    func requestTrust() -> Bool { requestTrustCalls += 1; return false }
    func selectedText() throws -> String {
        selectedTextCalls += 1
        if let selectedTextFailure { throw selectedTextFailure }
        return selectedTextValue
    }
}

final class FakeAccessibilitySelectionNode {
    let candidate: AccessibilitySelectionCandidate
    var parent: FakeAccessibilitySelectionNode?

    init(candidate: AccessibilitySelectionCandidate = AccessibilitySelectionCandidate()) {
        self.candidate = candidate
    }
}

@MainActor
final class FakeDoubleShiftMonitor: DoubleShiftMonitoring {
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

@MainActor
final class RetainingDoubleShiftMonitor: DoubleShiftMonitoring {
    var starts = 0
    var stops = 0
    private var action: (@MainActor () -> Void)?

    func start(action: @escaping @MainActor () -> Void) -> Bool {
        starts += 1
        self.action = action
        return true
    }

    func stop() { stops += 1 }
    func triggerRetainedAction() { action?() }
}

@MainActor
final class FakeModifierEventSource: ModifierEventSource {
    var globalTokenAvailable = true
    var localTokenAvailable = true
    private(set) var removedTokens: [AnyHashable] = []
    private var globalHandlers: [(ModifierEvent) -> Void] = []
    private var localHandlers: [(ModifierEvent) -> Void] = []

    func addGlobalModifierMonitor(handler: @escaping (ModifierEvent) -> Void) -> Any? {
        guard globalTokenAvailable else { return nil }
        globalHandlers.append(handler)
        return "global-\(globalHandlers.count)"
    }

    func addLocalModifierMonitor(handler: @escaping (ModifierEvent) -> Void) -> Any? {
        guard localTokenAvailable else { return nil }
        localHandlers.append(handler)
        return "local-\(localHandlers.count)"
    }

    func removeMonitor(_ token: Any) {
        if let token = token as? AnyHashable { removedTokens.append(token) }
    }

    func emitGlobal(_ event: ModifierEvent, handlerAt index: Int = 0) {
        globalHandlers[index](event)
    }

    func emitLocal(_ event: ModifierEvent, handlerAt index: Int = 0) {
        localHandlers[index](event)
    }
}

final class FakeDoubleShiftCapturePreferences: DoubleShiftCapturePreferences {
    var doubleShiftCaptureEnabled = false
}

final class FakeAutomaticCopyTargetSource {
    var frontmostProcessIdentifier: pid_t?
    func currentProcessIdentifier() -> pid_t? { frontmostProcessIdentifier }
}

@MainActor
final class FakeAutomaticSelectionCopier: AutomaticSelectionCopying {
    var copies = 0
    var cancellations = 0
    var retainsCompletionAfterCancellation = false
    private var completion: (@MainActor (Result<String, Error>) -> Void)?

    func copySelection(completion: @escaping @MainActor (Result<String, Error>) -> Void) {
        copies += 1
        self.completion = completion
    }

    func cancelPendingCopy() {
        cancellations += 1
        if !retainsCompletionAfterCancellation { completion = nil }
    }

    func finish(_ result: Result<String, Error>) { completion?(result) }
}

@main @MainActor
enum EmbercueChecks {
    static func main() {
        do {
            if CommandLine.arguments.count == 3, CommandLine.arguments[1] == "--write-visual-fixture" {
                try writeVisualFixture(URL(fileURLWithPath: CommandLine.arguments[2]))
            } else if CommandLine.arguments.count == 4, CommandLine.arguments[1] == "--concurrent-writer" {
                try concurrentWriter(root: URL(fileURLWithPath: CommandLine.arguments[2]), text: CommandLine.arguments[3])
            } else if CommandLine.arguments.count == 1 {
                try run()
                print("Embercue behavior checks passed")
            } else {
                throw CheckFailure.failed("usage: EmbercueChecks [--write-visual-fixture <absolute-data-root>]")
            }
        } catch {
            fputs("Embercue behavior check failed: \(error)\n", stderr)
            exit(1)
        }
    }

    static func run() throws {
        try schemaAndEngineChecks()
        try migrationAndRepositoryChecks()
        try attachmentChecks()
        try recoveryAndSafetyChecks()
        try concurrentWriterChecks()
        try workbenchChecks()
        try markdownBoundaryChecks()
        try fixtureChecks()
        try presentationChecks()
        try adapterRegressionChecks()
        try cardSelectionInteractionChecks()
        try selectedTextCaptureChecks()
    }

    static func schemaAndEngineChecks() throws {
        let memory = MemoryRepository()
        let engine = try LibraryEngine(repository: memory)
        let first = try engine.add(kind: .prompt, text: "First", now: Date(timeIntervalSince1970: 1))
        let second = try engine.add(kind: .prompt, text: "Second", now: Date(timeIntervalSince1970: 2))
        try require(first.sortOrder == 0 && second.sortOrder == 1, "new items must append in section order")
        let section = try engine.createSection(name: "Research")
        try require(engine.document.revision == 3, "each success must advance one revision")
        try engine.move([first.id, second.id], to: section.id, now: Date(timeIntervalSince1970: 3))
        try require(engine.document.items(in: section.id).map(\.id) == [first.id, second.id], "move must retain supplied display order")
        let beforeFailure = engine.document
        memory.fail = true
        do {
            try engine.edit(first.id, text: "Not persisted")
            throw CheckFailure.failed("injected persistence failure unexpectedly saved")
        } catch LibraryRepositoryError.saveFailed {}
        try require(engine.document == beforeFailure, "failed persistence must not publish candidate state")
        memory.fail = false
        let merged = try engine.merge([first.id, second.id], now: Date(timeIntervalSince1970: 4))
        try require(merged.text == "First\n\nSecond", "merge must retain raw Markdown with a blank separator")
        try require(engine.document.items.first(where: { $0.id == first.id })?.state == .archived, "merge archives originals atomically")
        try require(engine.document.items.first(where: { $0.id == second.id })?.state == .archived, "merge archives every source")
        do { try engine.removeEmptySection(section.id); throw CheckFailure.failed("nonempty section was removed") } catch LibraryRepositoryError.nonEmptySection {}
        do { _ = try engine.createSection(name: " research "); throw CheckFailure.failed("duplicate normalized section name accepted") } catch LibraryRepositoryError.duplicateSectionName {}
        do { try engine.complete([merged.id, merged.id]); throw CheckFailure.failed("duplicate selection accepted") } catch LibraryRepositoryError.invalidSelection {}
        try engine.complete([merged.id], now: Date(timeIntervalSince1970: 5))
        try require(engine.document.items.first(where: { $0.id == merged.id })?.state == .completed, "bulk complete must mark active item done")
    }

    static func migrationAndRepositoryChecks() throws {
        let root = try temporaryRoot("Embercue-v2-migration")
        defer { try? FileManager.default.removeItem(at: root) }
        let repo = try JSONLibraryRepository(rootURL: root)
        let rawV1 = literalV1(revision: 7)
        try rawV1.write(to: repo.documentURL)
        let beforeAttributes = try FileManager.default.attributesOfItem(atPath: repo.documentURL.path)
        let loaded = try repo.load()
        try require(loaded.document.schemaVersion == 3 && loaded.document.revision == 7, "v1 must decode into normalized v3 memory")
        let primaryAfterLoad = try Data(contentsOf: repo.documentURL)
        try require(primaryAfterLoad == rawV1, "loading v1 must not rewrite primary bytes")
        try require(!FileManager.default.fileExists(atPath: repo.preSchema2BackupURL.path), "load must not create migration backup")
        let engine = try LibraryEngine(repository: repo)
        _ = try engine.add(kind: .prompt, text: "New after migration")
        let preSchemaAfterFirstMutation = try Data(contentsOf: repo.preSchema2BackupURL)
        try require(preSchemaAfterFirstMutation == rawV1, "first mutation must preserve exact v1 primary bytes")
        try require(permissions(of: repo.preSchema2BackupURL) == 0o600, "pre-schema backup must be owner-only")
        let preSchema3AfterFirstMutation = try Data(contentsOf: repo.preSchema3BackupURL)
        try require(preSchema3AfterFirstMutation == rawV1 && permissions(of: repo.preSchema3BackupURL) == 0o600, "v3 migration must preserve the exact prior primary owner-only")
        let after = try Data(contentsOf: repo.documentURL)
        try require(!after.elementsEqual(rawV1), "first mutation must write v3 primary")
        let afterSchema = try decodedSchema(after)
        try require(afterSchema == 3, "primary must be schema 3 after mutation")
        _ = try engine.add(kind: .prompt, text: "Second mutation")
        let preSchemaAfterSecondMutation = try Data(contentsOf: repo.preSchema2BackupURL)
        try require(preSchemaAfterSecondMutation == rawV1, "pre-schema backup must never rotate")
        _ = beforeAttributes // mtime/data assertion is the byte equality above; timestamps are intentionally untouched by load.

        let backupRoot = try temporaryRoot("Embercue-v1-backup")
        defer { try? FileManager.default.removeItem(at: backupRoot) }
        let backupRepo = try JSONLibraryRepository(rootURL: backupRoot)
        try rawV1.write(to: backupRepo.backupURL)
        let recovered = try backupRepo.load()
        try require(recovered.document.revision == 7, "v1 backup must recover")
        let restoredBackupPrimary = try Data(contentsOf: backupRepo.documentURL)
        try require(restoredBackupPrimary == rawV1, "backup recovery must restore raw v1 bytes")
        try require(!FileManager.default.fileExists(atPath: backupRepo.preSchema2BackupURL.path), "recovery itself must not migrate")
        _ = try LibraryEngine(repository: backupRepo).add(kind: .prompt, text: "mutate recovered")
        let recoveredPreSchema = try Data(contentsOf: backupRepo.preSchema2BackupURL)
        try require(recoveredPreSchema == rawV1, "first post-recovery mutation must preserve restored v1 bytes")

        let migrationSymlinkRoot = try temporaryRoot("Embercue-migration-symlink")
        defer { try? FileManager.default.removeItem(at: migrationSymlinkRoot) }
        let migrationSymlinkRepo = try JSONLibraryRepository(rootURL: migrationSymlinkRoot)
        try rawV1.write(to: migrationSymlinkRepo.documentURL)
        let migrationTarget = migrationSymlinkRoot.appendingPathComponent("migration-target.json")
        let migrationTargetData = Data("untouched migration target".utf8)
        try migrationTargetData.write(to: migrationTarget)
        try FileManager.default.createSymbolicLink(at: migrationSymlinkRepo.preSchema2BackupURL, withDestinationURL: migrationTarget)
        let symlinkEngine = try LibraryEngine(repository: migrationSymlinkRepo)
        do { _ = try symlinkEngine.add(kind: .prompt, text: "must fail"); throw CheckFailure.failed("migration backup symlink accepted") } catch LibraryRepositoryError.invalidDocument {}
        let migrationPrimaryAfter = try Data(contentsOf: migrationSymlinkRepo.documentURL)
        try require(migrationPrimaryAfter == rawV1, "failed migration must not replace v1 primary")
        let migrationTargetAfter = try Data(contentsOf: migrationTarget)
        try require(migrationTargetAfter == migrationTargetData, "failed migration must not touch symlink target")

        let failedMigrationRoot = try temporaryRoot("Embercue-migration-rollback")
        defer { try? FileManager.default.removeItem(at: failedMigrationRoot) }
        let failedMigrationRepo = try JSONLibraryRepository(rootURL: failedMigrationRoot)
        try rawV1.write(to: failedMigrationRepo.documentURL)
        let priorBackup = Data("prior backup bytes".utf8)
        try priorBackup.write(to: failedMigrationRepo.backupURL)
        guard chflags(failedMigrationRepo.documentURL.path, UInt32(UF_IMMUTABLE)) == 0 else { throw CheckFailure.failed("could not make isolated primary immutable") }
        defer { _ = chflags(failedMigrationRepo.documentURL.path, 0) }
        let failedEngine = try LibraryEngine(repository: failedMigrationRepo)
        do {
            _ = try failedEngine.add(kind: .prompt, text: "must roll back")
            throw CheckFailure.failed("immutable primary accepted migration")
        } catch LibraryRepositoryError.saveFailed {}
        let failedPrimary = try Data(contentsOf: failedMigrationRepo.documentURL)
        let failedBackup = try Data(contentsOf: failedMigrationRepo.backupURL)
        try require(failedPrimary == rawV1 && failedBackup == priorBackup, "failed first migration must restore primary and prior backup bytes")
        try require(!FileManager.default.fileExists(atPath: failedMigrationRepo.preSchema2BackupURL.path) && !FileManager.default.fileExists(atPath: failedMigrationRepo.preSchema3BackupURL.path), "failed first migration must not leave migration snapshots")
        guard chflags(failedMigrationRepo.documentURL.path, 0) == 0 else { throw CheckFailure.failed("could not clear immutable flag") }
        _ = try LibraryEngine(repository: failedMigrationRepo).add(kind: .prompt, text: "successful migration")
        let successfulPreSchema = try Data(contentsOf: failedMigrationRepo.preSchema2BackupURL)
        try require(successfulPreSchema == rawV1 && permissions(of: failedMigrationRepo.preSchema2BackupURL) == 0o600, "later successful migration must create exact owner-only snapshot")

        let document = try fixtureDocument(revision: 1, text: "durable")
        let freshRoot = try temporaryRoot("Embercue-v2-repository")
        defer { try? FileManager.default.removeItem(at: freshRoot) }
        let fresh = try JSONLibraryRepository(rootURL: freshRoot)
        try fresh.save(document, expectedRevision: 0)
        try require(permissions(of: freshRoot) == 0o700 && permissions(of: fresh.documentURL) == 0o600, "managed storage must remain owner-only")
        let freshReload = try fresh.load().document
        try require(freshReload == document, "v3 save/reload must preserve document")
        var updated = document; updated.revision = 2
        try fresh.save(updated, expectedRevision: 1)
        try require(FileManager.default.fileExists(atPath: fresh.backupURL.path), "v3 rotation must write normal backup")
        for reserved in [fresh.documentURL, fresh.backupURL, fresh.preSchema2BackupURL, fresh.preSchema3BackupURL, freshRoot.appendingPathComponent(".library.lock")] {
            do { try fresh.export(updated, to: reserved); throw CheckFailure.failed("reserved destination accepted") } catch LibraryRepositoryError.reservedExportDestination {}
        }

        let v2Root = try temporaryRoot("Embercue-v2-to-v3")
        defer { try? FileManager.default.removeItem(at: v2Root) }
        let v2Repo = try JSONLibraryRepository(rootURL: v2Root)
        let rawV2 = literalV2(revision: 4)
        try rawV2.write(to: v2Repo.documentURL)
        let loadedV2 = try v2Repo.load()
        try require(loadedV2.document.schemaVersion == 3, "v2 must load as v3 memory without rewriting")
        let v2AfterLoad = try Data(contentsOf: v2Repo.documentURL)
        try require(v2AfterLoad == rawV2, "loading v2 must preserve primary bytes")
        _ = try LibraryEngine(repository: v2Repo).add(kind: .prompt, text: "v3 mutation")
        let v2PreSchema3 = try Data(contentsOf: v2Repo.preSchema3BackupURL)
        try require(v2PreSchema3 == rawV2 && permissions(of: v2Repo.preSchema3BackupURL) == 0o600, "v2 first mutation must preserve exact owner-only v3 migration snapshot")
    }

    static func workbenchChecks() throws {
        let repository = MemoryRepository()
        let research = try LibrarySection(name: "RESEARCH", sortOrder: 2)
        let first = try LibraryItem(kind: .prompt, text: "**Bold** and *italic*", sectionID: research.id, sortOrder: 0)
        let second = try LibraryItem(kind: .prompt, text: "Second\nline", sectionID: research.id, sortOrder: 1)
        repository.document = LibraryDocument(revision: 1, sections: LibraryDocument.builtInSections + [research], items: [first, second])
        let clipboard = FakeClipboard()
        let model = WorkbenchModel(engine: try LibraryEngine(repository: repository), clipboard: clipboard)
        try require(model.sections.map(\.section.name) == ["RESEARCH"], "active rail must project data sections, not lifecycle buckets")
        model.search = "Bold"
        try require(model.sections.map(\.section.name) == ["RESEARCH"], "search must hide sections without matching notes")
        model.search = "missing"
        try require(model.sections.isEmpty, "search with no matches must project the empty state instead of empty section headings")
        model.search = ""
        model.select(first); model.select(second, mode: .extend)
        try require(model.selectedDisplayItems().map(\.id) == [first.id, second.id], "range selection must use visible display order")
        try require(LibraryListFormatter.numberedList(model.selectedDisplayItems()) == "1. **Bold** and *italic*\n2. Second\n   line", "copy-as-list format must preserve raw Markdown and indent continuations")
        clipboard.succeeds = false
        try require(!model.copyAsList(), "clipboard failure must be reported")
        try require(model.document.revision == 1, "clipboard failure must not mutate persistence")
        try require(model.successMessage == nil, "clipboard failure must never produce copied success feedback")
        clipboard.succeeds = true
        try require(model.copyAsList(), "copy-as-list must complete after clipboard write")
        try require(model.document.revision == 2 && model.document.items.allSatisfy { $0.state == .completed }, "copy-as-list success must complete selected items in one revision")
        try require(model.successMessage == "Copied × 2" && model.inlineNoticeIsSuccess, "successful completion must report the actual copied count")
        try require(model.sections.flatMap(\.items).map(\.id) == [first.id, second.id], "successful completion must remain visible as a rail echo until hide")
        model.clearCompletionEcho()
        try require(!model.sections.flatMap(\.items).contains(where: { $0.id == first.id || $0.id == second.id }), "clearing completion echo must remove completed cards from the rail")
        model.draft = "Return-path capture"
        model.submitDraft()
        try require(model.draft.isEmpty && model.document.items.contains(where: { $0.text == "Return-path capture" && $0.state == .active }), "composer submit must persist a new active item and clear its draft")
        model.draft = "# Switzerland Trip"
        model.submitDraft()
        guard let trip = model.document.sections.first(where: { $0.name == "Switzerland Trip" }) else {
            throw CheckFailure.failed("composer section command must create a named section")
        }
        try require(model.captureSectionID == trip.id && model.draft.isEmpty, "composer section command must select its new section and clear the draft")
        let revisionAfterSection = model.document.revision
        model.draft = "# switzerland trip"
        model.submitDraft()
        try require(model.document.revision == revisionAfterSection && model.draft == "# switzerland trip" && model.errorMessage != nil, "duplicate section command must retain its draft and avoid a mutation")
        model.dismissError()
        model.draft = "## Markdown heading"
        model.submitDraft()
        try require(model.document.items.contains(where: { $0.text == "## Markdown heading" }), "other Markdown must remain a normal composer note")
        model.draft = "# \nnext line"
        model.submitDraft()
        try require(model.document.items.contains(where: { $0.text == "# \nnext line" }), "multiline hash text must remain a normal composer note")
        model.page = .history
        try require(model.historyItems.map(\.id) == [first.id, second.id], "completed cards must be visible in history")
        model.search = "missing"
        try require(model.selectedDisplayItems().isEmpty, "search must prune hidden actionable selection")

        let plainRepository = MemoryRepository()
        let plainItem = try LibraryItem(kind: .prompt, text: "plain copy")
        plainRepository.document = LibraryDocument(revision: 1, items: [plainItem])
        let plainClipboard = FakeClipboard()
        let plainModel = WorkbenchModel(engine: try LibraryEngine(repository: plainRepository), clipboard: plainClipboard)
        plainModel.select(plainItem)
        try require(plainModel.copySelected(), "plain Copy must write selected text")
        try require(plainClipboard.writes == ["plain copy"] && plainModel.document.revision == 1 && plainModel.document.items.first?.state == .active, "plain Copy and Copy & Return must be state-neutral")

        let manualCompletionRepository = MemoryRepository()
        let manualCompletionItem = try LibraryItem(kind: .prompt, text: "manual completion")
        manualCompletionRepository.document = LibraryDocument(revision: 1, items: [manualCompletionItem])
        var expireManualCompletionEcho: (() -> Void)?
        let manualCompletionModel = WorkbenchModel(
            engine: try LibraryEngine(repository: manualCompletionRepository),
            clipboard: FakeClipboard(),
            completionEchoExpiryScheduler: { expireManualCompletionEcho = $0 }
        )
        manualCompletionModel.select(manualCompletionItem)
        manualCompletionModel.requestComposerFocus()
        manualCompletionModel.execute(.markDone)
        try require(manualCompletionModel.document.items.first?.state == .completed, "Mark as Done must persist completion immediately")
        try require(manualCompletionModel.sections.flatMap(\.items).map(\.id) == [manualCompletionItem.id], "Mark as Done must retain a brief visible completion echo while the composer stays focused")
        guard let expireManualCompletionEcho else { throw CheckFailure.failed("Mark as Done must schedule completion echo expiry") }
        expireManualCompletionEcho()
        try require(manualCompletionModel.sections.flatMap(\.items).isEmpty && manualCompletionModel.selectedIDs.isEmpty, "expired manual completion echo must leave the rail and prune its selection")

        let restoredCompletionRepository = MemoryRepository()
        let restoredCompletionItem = try LibraryItem(kind: .prompt, text: "restored completion")
        restoredCompletionRepository.document = LibraryDocument(revision: 1, items: [restoredCompletionItem])
        var expireRestoredCompletionEcho: (() -> Void)?
        let restoredCompletionModel = WorkbenchModel(
            engine: try LibraryEngine(repository: restoredCompletionRepository),
            clipboard: FakeClipboard(),
            completionEchoExpiryScheduler: { expireRestoredCompletionEcho = $0 }
        )
        restoredCompletionModel.select(restoredCompletionItem)
        restoredCompletionModel.completeSelected()
        restoredCompletionModel.restore(restoredCompletionItem)
        guard let restoredItem = restoredCompletionModel.document.items.first else { throw CheckFailure.failed("restored completion item missing") }
        try require(restoredItem.state == .active && !restoredCompletionModel.isCompletionEcho(restoredItem), "restore before echo expiry must immediately remove the completed presentation")
        guard let expireRestoredCompletionEcho else { throw CheckFailure.failed("manual completion must retain its scheduled expiry after restore") }
        expireRestoredCompletionEcho()
        try require(restoredCompletionModel.selectedIDs == [restoredCompletionItem.id], "expired restored completion callback must preserve valid active selection")

        let customDestination = try LibrarySection(name: "CUSTOM KEEPS", sortOrder: 3)
        let customOnlyRepository = MemoryRepository()
        customOnlyRepository.document = LibraryDocument(revision: 1, sections: [research, customDestination])
        let customClipboard = FakeClipboard()
        customClipboard.text = "clipboard keep"
        let customOnlyModel = WorkbenchModel(engine: try LibraryEngine(repository: customOnlyRepository), clipboard: customClipboard)
        customOnlyModel.captureSectionID = customDestination.id
        customOnlyModel.keepClipboard()
        try require(customOnlyModel.errorMessage == nil && customOnlyModel.document.items.count == 1, "Keep Clipboard must work in a valid library without the legacy KEEPS section")
        try require(customOnlyModel.document.items[0].kind == .snippet && customOnlyModel.document.items[0].sectionID == customDestination.id, "Keep Clipboard must fall back to the selected capture section when legacy KEEPS is absent")

        let builtInClipboard = FakeClipboard()
        builtInClipboard.text = "legacy keep"
        let builtInModel = WorkbenchModel(engine: try LibraryEngine(repository: MemoryRepository()), clipboard: builtInClipboard)
        builtInModel.keepClipboard()
        try require(builtInModel.document.items.first?.sectionID == LibrarySectionID.keeps, "Keep Clipboard must preserve the legacy KEEPS destination when it exists")

        let attachmentRoot = try temporaryRoot("Embercue-mixed-copy")
        defer { try? FileManager.default.removeItem(at: attachmentRoot) }
        let attachmentStore = try AttachmentStore(rootURL: attachmentRoot)
        let source = attachmentRoot.appendingPathComponent("source.txt")
        try Data("attachment bytes".utf8).write(to: source)
        let attachment = try attachmentStore.importFile(at: source)
        let mixedRepository = MemoryRepository()
        let attachmentItem = try LibraryItem(kind: .prompt, text: "", attachments: [attachment])
        let textItem = try LibraryItem(kind: .prompt, text: "mixed text", sectionID: attachmentItem.sectionID, sortOrder: 1)
        mixedRepository.document = LibraryDocument(revision: 1, items: [attachmentItem, textItem])
        let mixedClipboard = FakeClipboard()
        let mixedModel = WorkbenchModel(engine: try LibraryEngine(repository: mixedRepository), clipboard: mixedClipboard, attachmentStore: attachmentStore)
        mixedModel.select(attachmentItem); mixedModel.select(textItem, mode: .extend)
        try require(mixedModel.copyAsList(), "mixed copy must complete after its combined payload write")
        guard let mixedURL = attachmentStore.url(for: attachment) else { throw CheckFailure.failed("stored mixed attachment missing") }
        try require(mixedClipboard.payloads.last == ClipboardPayload(text: "1. mixed text", fileURLs: [mixedURL]), "mixed copy must write numbered text plus the private attachment URL")
        try require(mixedModel.successMessage == "Copied × 2", "mixed copy success count must include attachment-only cards")

        let truthfulRepository = MemoryRepository()
        let truthfulItem = try LibraryItem(kind: .prompt, text: "truthful list")
        truthfulRepository.document = LibraryDocument(revision: 1, items: [truthfulItem])
        let truthfulClipboard = FakeClipboard()
        let truthfulModel = WorkbenchModel(engine: try LibraryEngine(repository: truthfulRepository), clipboard: truthfulClipboard)
        truthfulModel.select(truthfulItem)
        truthfulRepository.fail = true
        try require(!truthfulModel.copyAsList(), "Copy as List must report failed persistence after a successful clipboard write")
        try require(truthfulClipboard.payloads.last == ClipboardPayload(text: "1. truthful list") && truthfulModel.document.items.first?.state == .active && truthfulModel.errorMessage?.contains("Copied the list") == true, "Copy as List must not falsely report completion when save fails")
        try require(truthfulModel.successMessage == nil, "failed completion must not report copied success")

        let editRepository = MemoryRepository()
        let editItem = try LibraryItem(kind: .prompt, text: "before edit")
        editRepository.document = LibraryDocument(revision: 1, items: [editItem])
        let editModel = WorkbenchModel(engine: try LibraryEngine(repository: editRepository), clipboard: FakeClipboard())
        var openedItemID: UUID?
        editModel.onOpenEditor = { openedItemID = $0.id }
        try require(!editModel.handleShortcut(.edit), "Return Edit must fall through when no card is selected")
        editModel.select(editItem)
        try require(editModel.handleShortcut(.edit) && editModel.inlineEditID == editItem.id && openedItemID == nil, "Return Edit must start inline editing without opening a new window")
        editModel.inlineEditDraft = "retained draft"
        editRepository.fail = true
        try require(!editModel.saveInlineEdit() && editModel.inlineEditID == editItem.id && editModel.inlineEditDraft == "retained draft", "failed inline edit must retain its draft and editing state")
        editRepository.fail = false
        try require(editModel.saveInlineEdit() && editModel.inlineEditID == nil && editModel.document.items.first?.text == "retained draft", "successful inline edit must persist and close inline editing")
        editModel.select(editModel.document.items[0])
        editModel.execute(.editInNewWindow)
        try require(openedItemID == editItem.id && editModel.inlineEditID == nil, "Edit in New Window must use the distinct editor callback")

        let overflowRepository = MemoryRepository()
        overflowRepository.document = LibraryDocument(revision: Int.max)
        let overflowEngine = try LibraryEngine(repository: overflowRepository)
        do {
            _ = try overflowEngine.add(kind: .prompt, text: "must overflow")
            throw CheckFailure.failed("engine accepted an Int.max revision")
        } catch LibraryRepositoryError.revisionOverflow {}
    }

    static func attachmentChecks() throws {
        let root = try temporaryRoot("Embercue-attachments")
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = try JSONLibraryRepository(rootURL: root)
        let store = try AttachmentStore(rootURL: root)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let malformedV3 = Data("""
        {"schemaVersion":3,"revision":1,"sections":[{"id":"9B4EF8E0-917A-4F7C-95A1-4ED5EB0B4D01","name":"INBOX","sortOrder":0}],"items":[{"id":"00000000-0000-0000-0000-000000000003","kind":"prompt","state":"active","text":"bad attachment","attachments":[{"id":"00000000-0000-0000-0000-000000000004","storagePath":"../../outside","filename":"bad.txt","byteCount":1}],"createdAt":1,"updatedAt":1,"sectionID":"9B4EF8E0-917A-4F7C-95A1-4ED5EB0B4D01","sortOrder":0}]}
        """.utf8)
        do {
            _ = try LibrarySchemaCodec.decode(data: malformedV3, decoder: decoder)
            throw CheckFailure.failed("v3 decoding accepted an unmanaged attachment path")
        } catch LibraryRepositoryError.invalidDocument {}

        let source = root.appendingPathComponent("upload.txt")
        try Data("private attachment".utf8).write(to: source)
        let attachment = try store.importFile(at: source)
        guard let storedURL = store.url(for: attachment) else { throw CheckFailure.failed("stored attachment could not be resolved") }
        try require(permissions(of: store.rootURL) == 0o700 && permissions(of: storedURL) == 0o600, "attachment storage must remain owner-only")
        let engine = try LibraryEngine(repository: repository)
        let item = try engine.add(kind: .prompt, text: "", attachments: [attachment])
        try require(item.attachments == [attachment], "attachment-only cards must be accepted")
        let reloaded = try JSONLibraryRepository(rootURL: root).load().document
        try require(reloaded.items.first?.attachments == [attachment], "attachment references must persist through relaunch")
        let symlink = root.appendingPathComponent("source-link")
        try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: source)
        do { try store.validateSource(at: symlink); throw CheckFailure.failed("attachment symlink accepted") } catch LibraryRepositoryError.invalidDocument {}
        let tooLarge = root.appendingPathComponent("large.bin")
        try Data(repeating: 0, count: LibraryAttachment.maximumBytes + 1).write(to: tooLarge)
        do { try store.validateSource(at: tooLarge); throw CheckFailure.failed("oversize attachment accepted") } catch LibraryRepositoryError.dataTooLarge {}
    }

    static func selectedTextCaptureChecks() throws {
        let containerWithoutSelection = AccessibilitySelectionCandidate()
        let parentSelection = AccessibilitySelectionCandidate(directText: "parent selection")
        let resolvedParentSelection = try AccessibilitySelectionResolver.resolve([containerWithoutSelection, parentSelection])
        try require(
            resolvedParentSelection == "parent selection",
            "selected text exposed by a focused element ancestor must be captured"
        )

        let rangedSelection = AccessibilitySelectionCandidate(
            selectedRange: CFRange(location: 5, length: 9),
            rangedText: "range text"
        )
        let resolvedRangedSelection = try AccessibilitySelectionResolver.resolve([rangedSelection])
        try require(
            resolvedRangedSelection == "range text",
            "AX string-for-range must recover selection when AXSelectedText is unavailable"
        )

        let utf16Selection = AccessibilitySelectionCandidate(
            selectedRange: CFRange(location: 1, length: 3),
            fullText: "A😀BC"
        )
        let resolvedUTF16Selection = try AccessibilitySelectionResolver.resolve([utf16Selection])
        try require(
            resolvedUTF16Selection == "😀B",
            "AXValue fallback must slice the selected CFRange in UTF-16 coordinates"
        )

        do {
            _ = try AccessibilitySelectionResolver.resolve([AccessibilitySelectionCandidate(selectedRange: CFRange(location: 0, length: 0), fullText: "text")])
            throw CheckFailure.failed("a zero-length AX selection was accepted")
        } catch SelectedTextCaptureError.emptySelection {}

        do {
            _ = try AccessibilitySelectionResolver.resolve([AccessibilitySelectionCandidate()])
            throw CheckFailure.failed("an element without any standard AX selection representation was accepted")
        } catch SelectedTextCaptureError.unavailable {}

        do {
            _ = try AccessibilitySelectionResolver.resolve([
                AccessibilitySelectionCandidate(selectedRange: CFRange(location: -1, length: 3), fullText: "text")
            ])
            throw CheckFailure.failed("an invalid AX selection range was accepted")
        } catch SelectedTextCaptureError.unavailable {}

        do {
            _ = try AccessibilitySelectionResolver.resolve([
                AccessibilitySelectionCandidate(selectedRange: CFRange(location: 1, length: 1), fullText: "A😀B")
            ])
            throw CheckFailure.failed("an AX range splitting a UTF-16 surrogate pair was accepted")
        } catch SelectedTextCaptureError.unavailable {}

        var providerCalls: [String] = []
        let providerCandidate = AccessibilitySelectionCandidateBuilder.make(
            directText: nil,
            selectedRange: CFRange(location: 0, length: 5),
            rangedText: { providerCalls.append("range"); return "range" },
            fullText: { providerCalls.append("full"); return "unused" }
        )
        let providerResult = try AccessibilitySelectionResolver.resolve([providerCandidate])
        try require(providerResult == "range" && providerCalls == ["range"], "AX string-for-range must run before and suppress full-value fallback")

        providerCalls.removeAll()
        let fullValueCandidate = AccessibilitySelectionCandidateBuilder.make(
            directText: nil,
            selectedRange: CFRange(location: 1, length: 3),
            rangedText: { providerCalls.append("range"); return nil },
            fullText: { providerCalls.append("full"); return "A😀BC" }
        )
        let fullValueResult = try AccessibilitySelectionResolver.resolve([fullValueCandidate])
        try require(fullValueResult == "😀B" && providerCalls == ["range", "full"], "missing AX string-for-range must invoke full-value fallback exactly once")

        providerCalls.removeAll()
        _ = AccessibilitySelectionCandidateBuilder.make(
            directText: nil,
            selectedRange: CFRange(location: 0, length: 1),
            rangedText: { providerCalls.append("range"); return "   " },
            fullText: { providerCalls.append("full"); return "A" }
        )
        try require(providerCalls == ["range", "full"], "blank AX string-for-range must invoke full-value fallback exactly once")

        do {
            _ = try AccessibilitySelectionResolver.resolve([
                AccessibilitySelectionCandidate(selectedRange: CFRange(location: 1, length: 1), fullText: "Ae\u{301}B")
            ])
            throw CheckFailure.failed("an AX range splitting a composed grapheme was accepted")
        } catch SelectedTextCaptureError.unavailable {}

        let parentNode = FakeAccessibilitySelectionNode(candidate: AccessibilitySelectionCandidate(directText: "parent selection"))
        let focusedNode = FakeAccessibilitySelectionNode()
        focusedNode.parent = parentNode
        parentNode.parent = focusedNode
        let walkedCandidates = AccessibilitySelectionTraversal.candidates(
            startingAt: focusedNode,
            maximumDepth: 16,
            equals: { $0 === $1 },
            candidate: { $0.candidate },
            parent: { $0.parent }
        )
        let walkedResult = try AccessibilitySelectionResolver.resolve(walkedCandidates)
        try require(walkedResult == "parent selection" && walkedCandidates.count == 2, "production parent traversal must resolve an ancestor and stop on a cycle")

        let focusedFallback = try AccessibilitySelectionResolver.resolve([
            AccessibilitySelectionCandidate(selectedRange: CFRange(location: 0, length: 5), fullText: "focus"),
            AccessibilitySelectionCandidate(directText: "ancestor")
        ])
        try require(focusedFallback == "focus", "focused full-text fallback must outrank an ancestor direct selection")

        var state = DoubleShiftCaptureState()
        try require(!state.consume(shiftIsDown: true, at: 1), "first Shift press must not capture")
        try require(!state.consume(shiftIsDown: true, at: 1.1), "unchanged Shift state must not be counted twice")
        try require(!state.consume(shiftIsDown: false, at: 1.2), "Shift release must not capture")
        try require(!state.consume(shiftIsDown: true, at: 1.4), "a reset gesture requires a new first Shift press")
        try require(!state.consume(shiftIsDown: false, at: 1.5), "Shift release must not capture")
        try require(state.consume(shiftIsDown: true, at: 1.6), "a second Shift press inside debounce window must capture once")
        try require(!state.consume(shiftIsDown: false, at: 1.7) && !state.consume(shiftIsDown: true, at: 2.4), "expired first press must not capture")

        var interruptedState = DoubleShiftCaptureState()
        try require(!interruptedState.consume(modifierFlags: [.shift], at: 1), "first Shift press must not capture")
        for modifier in [NSEvent.ModifierFlags.command, .option, .control, .function] {
            var modifierState = DoubleShiftCaptureState()
            try require(!modifierState.consume(modifierFlags: [.shift], at: 1), "first Shift press must not capture")
            try require(!modifierState.consume(modifierFlags: [.shift, modifier], at: 1.1), "non-Shift modifiers must interrupt a pending Shift gesture")
            try require(!modifierState.consume(modifierFlags: [], at: 1.2), "release after an interrupted gesture must not capture")
            try require(!modifierState.consume(modifierFlags: [.shift], at: 1.3), "an interrupted gesture must not capture on the next Shift press")
        }
        try require(!interruptedState.consume(modifierFlags: [.shift, .command], at: 1.1), "Command must interrupt a pending Shift gesture")
        try require(!interruptedState.consume(modifierFlags: [], at: 1.2), "release after an interrupted gesture must not capture")
        try require(!interruptedState.consume(modifierFlags: [.shift], at: 1.3), "interrupted gestures must require a fresh first press")
        try require(!interruptedState.consume(modifierFlags: [.shift], at: 1.4), "an unchanged Shift transition must reset a pending gesture")
        try require(!interruptedState.consume(modifierFlags: [], at: 1.5), "release after unchanged Shift must not capture")
        try require(!interruptedState.consume(modifierFlags: [.shift], at: 2), "new first press must remain inert")
        try require(!interruptedState.consume(modifierFlags: [], at: 2.1), "release must remain inert")
        try require(!interruptedState.consume(modifierFlags: [.shift], at: 1.9), "a negative timestamp delta must reject the gesture")

        let modifierSource = FakeModifierEventSource()
        let modifierMonitor = GlobalDoubleShiftMonitor(eventSource: modifierSource)
        var modifierActions = 0
        try require(modifierMonitor.start { modifierActions += 1 }, "both modifier monitor registrations must succeed")
        modifierSource.emitGlobal(ModifierEvent(modifierFlags: [.shift], timestamp: 1))
        modifierSource.emitGlobal(ModifierEvent(modifierFlags: [], timestamp: 1.1))
        modifierSource.emitLocal(ModifierEvent(modifierFlags: [.shift], timestamp: 1.2))
        try require(modifierActions == 1, "local and global callbacks must share synchronous double-Shift handling")
        modifierMonitor.stop()
        try require(modifierSource.removedTokens == ["global-1", "local-1"], "stop must remove both modifier monitor tokens")
        modifierSource.emitGlobal(ModifierEvent(modifierFlags: [], timestamp: 1.3))
        modifierSource.emitGlobal(ModifierEvent(modifierFlags: [.shift], timestamp: 1.4))
        try require(modifierActions == 1, "callbacks retained by an event source after stop must be generation-stale")
        try require(modifierMonitor.start { modifierActions += 1 }, "monitor restart must succeed")
        modifierSource.emitGlobal(ModifierEvent(modifierFlags: [.shift], timestamp: 2), handlerAt: 0)
        modifierSource.emitGlobal(ModifierEvent(modifierFlags: [], timestamp: 2.1), handlerAt: 0)
        modifierSource.emitGlobal(ModifierEvent(modifierFlags: [.shift], timestamp: 2.2), handlerAt: 0)
        try require(modifierActions == 1, "callbacks from a prior registration must remain inert after restart")

        let partialSource = FakeModifierEventSource()
        partialSource.localTokenAvailable = false
        let partialMonitor = GlobalDoubleShiftMonitor(eventSource: partialSource)
        var partialActions = 0
        try require(!partialMonitor.start { partialActions += 1 }, "partial modifier registration must fail closed")
        try require(partialSource.removedTokens == ["global-1"], "partial modifier registration must remove the installed global token")
        partialSource.emitGlobal(ModifierEvent(modifierFlags: [.shift], timestamp: 1))
        partialSource.emitGlobal(ModifierEvent(modifierFlags: [], timestamp: 1.1))
        partialSource.emitGlobal(ModifierEvent(modifierFlags: [.shift], timestamp: 1.2))
        try require(partialActions == 0, "callbacks from a failed partial registration must be generation-stale")

        let reader = FakeSelectedTextReader()
        let monitor = FakeDoubleShiftMonitor()
        let preferences = FakeDoubleShiftCapturePreferences()
        var captures: [String] = []
        var errors: [Error] = []
        let coordinator = SelectedTextCaptureCoordinator(
            reader: reader,
            monitor: monitor,
            preferences: preferences,
            capture: { captures.append($0) },
            reportError: { errors.append($0) },
            captureConfirmation: { true }
        )
        coordinator.restore()
        try require(coordinator.status == .disabled && !preferences.doubleShiftCaptureEnabled && reader.requestTrustCalls == 0 && monitor.starts == 0, "default launch must remain disabled without prompting")

        coordinator.performMenuAction()
        try require(coordinator.status == .awaitingPermission && preferences.doubleShiftCaptureEnabled && reader.requestTrustCalls == 1 && monitor.starts == 0 && errors.isEmpty, "explicit untrusted enable must await one prompt without a false denial")
        coordinator.refreshAuthorization()
        try require(coordinator.status == .awaitingPermission && reader.requestTrustCalls == 1 && monitor.starts == 0, "untrusted refresh must neither prompt nor start")

        reader.isTrusted = true
        coordinator.refreshAuthorization()
        try require(coordinator.status == .enabled && monitor.starts == 1, "trusted refresh must start capture once")
        coordinator.refreshAuthorization()
        try require(monitor.starts == 1, "repeated trusted refresh must not duplicate the monitor")
        monitor.trigger()
        try require(captures == ["captured text"] && reader.selectedTextCalls == 1, "enabled monitor must retain selected-text capture semantics")

        reader.isTrusted = false
        coordinator.refreshAuthorization()
        try require(coordinator.status == .awaitingPermission && monitor.stops == 1 && preferences.doubleShiftCaptureEnabled, "revocation must stop monitoring while retaining opt-in for a later grant")
        coordinator.performMenuAction()
        try require(coordinator.status == .disabled && !preferences.doubleShiftCaptureEnabled, "awaiting setup must be cancellable and clear opt-in")
        coordinator.performMenuAction()
        try require(coordinator.status == .awaitingPermission && preferences.doubleShiftCaptureEnabled && reader.requestTrustCalls == 2, "re-enabling after cancellation must make a new explicit prompt request")

        let trustedReader = FakeSelectedTextReader(); trustedReader.isTrusted = true
        let trustedMonitor = FakeDoubleShiftMonitor()
        let trustedPreferences = FakeDoubleShiftCapturePreferences(); trustedPreferences.doubleShiftCaptureEnabled = true
        let trustedLaunch = SelectedTextCaptureCoordinator(reader: trustedReader, monitor: trustedMonitor, preferences: trustedPreferences, capture: { _ in })
        trustedLaunch.restore()
        try require(trustedLaunch.status == .enabled && trustedMonitor.starts == 1 && trustedReader.requestTrustCalls == 0, "trusted launch must restore capture without prompting")

        let untrustedReader = FakeSelectedTextReader()
        let untrustedMonitor = FakeDoubleShiftMonitor()
        let untrustedPreferences = FakeDoubleShiftCapturePreferences(); untrustedPreferences.doubleShiftCaptureEnabled = true
        let untrustedLaunch = SelectedTextCaptureCoordinator(reader: untrustedReader, monitor: untrustedMonitor, preferences: untrustedPreferences, capture: { _ in })
        untrustedLaunch.restore()
        try require(untrustedLaunch.status == .awaitingPermission && untrustedMonitor.starts == 0 && untrustedReader.requestTrustCalls == 0, "untrusted launch must await authorization without prompting")

        let captureReader = FakeSelectedTextReader(); captureReader.isTrusted = true
        let captureMonitor = FakeDoubleShiftMonitor()
        let capturePreferences = FakeDoubleShiftCapturePreferences(); capturePreferences.doubleShiftCaptureEnabled = true
        let captureCoordinator = SelectedTextCaptureCoordinator(reader: captureReader, monitor: captureMonitor, preferences: capturePreferences, capture: { _ in })
        captureCoordinator.restore()
        captureReader.isTrusted = false
        captureMonitor.trigger()
        try require(captureCoordinator.status == .awaitingPermission && captureMonitor.stops == 1 && captureReader.selectedTextCalls == 0, "capture-time revocation must stop before reading selected text")

        let enabledReader = FakeSelectedTextReader(); enabledReader.isTrusted = true
        let enabledMonitor = FakeDoubleShiftMonitor()
        let enabledPreferences = FakeDoubleShiftCapturePreferences(); enabledPreferences.doubleShiftCaptureEnabled = true
        var enabledCaptures = 0
        let enabledCoordinator = SelectedTextCaptureCoordinator(reader: enabledReader, monitor: enabledMonitor, preferences: enabledPreferences, capture: { _ in enabledCaptures += 1 })
        enabledCoordinator.restore()
        enabledCoordinator.performMenuAction()
        enabledMonitor.trigger()
        try require(enabledCoordinator.status == .disabled && !enabledPreferences.doubleShiftCaptureEnabled && enabledMonitor.stops == 1 && enabledCaptures == 0, "enabled Disable must stop, clear intent, and make the prior monitor inert")

        let stoppedReader = FakeSelectedTextReader(); stoppedReader.isTrusted = true
        let stoppedMonitor = FakeDoubleShiftMonitor()
        let stoppedPreferences = FakeDoubleShiftCapturePreferences(); stoppedPreferences.doubleShiftCaptureEnabled = true
        let stoppedCoordinator = SelectedTextCaptureCoordinator(reader: stoppedReader, monitor: stoppedMonitor, preferences: stoppedPreferences, capture: { _ in })
        stoppedCoordinator.restore()
        stoppedCoordinator.stop()
        try require(stoppedCoordinator.status == .enabled && stoppedPreferences.doubleShiftCaptureEnabled && stoppedMonitor.stops == 1, "process-local stop must retain persisted opt-in")

        let errorReader = FakeSelectedTextReader(); errorReader.isTrusted = true; errorReader.selectedTextFailure = SelectedTextCaptureError.emptySelection
        let errorMonitor = FakeDoubleShiftMonitor()
        let errorPreferences = FakeDoubleShiftCapturePreferences(); errorPreferences.doubleShiftCaptureEnabled = true
        var captureErrors: [Error] = []
        var recoveredCaptures: [String] = []
        let errorCoordinator = SelectedTextCaptureCoordinator(reader: errorReader, monitor: errorMonitor, preferences: errorPreferences, capture: { recoveredCaptures.append($0) }, reportError: { captureErrors.append($0) })
        errorCoordinator.restore()
        errorMonitor.trigger()
        errorReader.selectedTextFailure = nil
        errorMonitor.trigger()
        try require(errorCoordinator.status == .enabled && (captureErrors.first as? SelectedTextCaptureError) == .emptySelection && recoveredCaptures == ["captured text"], "selected-text errors must report without disabling later capture")

        let automaticReader = FakeSelectedTextReader(); automaticReader.isTrusted = true; automaticReader.selectedTextFailure = SelectedTextCaptureError.unavailable
        let automaticMonitor = FakeDoubleShiftMonitor()
        let automaticPreferences = FakeDoubleShiftCapturePreferences(); automaticPreferences.doubleShiftCaptureEnabled = true
        let automaticCopier = FakeAutomaticSelectionCopier()
        var automaticCaptures: [String] = []
        var automaticErrors: [Error] = []
        let automaticCoordinator = SelectedTextCaptureCoordinator(
            reader: automaticReader,
            monitor: automaticMonitor,
            preferences: automaticPreferences,
            automaticSelectionCopier: automaticCopier,
            capture: { automaticCaptures.append($0) },
            reportError: { automaticErrors.append($0) }
        )
        automaticCoordinator.restore()
        automaticMonitor.trigger()
        try require(automaticCopier.copies == 1 && automaticCaptures.isEmpty, "unified enabled capture must use guarded Command-C only after exact AX unavailability")
        automaticCopier.finish(.failure(SelectedTextCaptureError.automaticCopyTimedOut))
        try require(automaticCaptures.isEmpty && (automaticErrors.last as? SelectedTextCaptureError) == .automaticCopyTimedOut, "automatic-copy timeout must never capture prior clipboard text")
        automaticMonitor.trigger()
        automaticCopier.finish(.success("newly copied selection"))
        try require(automaticCaptures == ["newly copied selection"], "automatic copy must capture only the copier's newly changed plain text")
        automaticCopier.retainsCompletionAfterCancellation = true
        automaticMonitor.trigger()
        automaticCoordinator.disable()
        automaticCopier.finish(.success("late copy"))
        try require(automaticCaptures == ["newly copied selection"] && !automaticPreferences.doubleShiftCaptureEnabled, "disabled automatic-copy callbacks must be generation-stale")
        try require(AutomaticSelectionCopyTarget.isEligible(frontmostBundleIdentifier: "com.example.editor", frontmostProcessIdentifier: 42, embercueBundleIdentifier: "com.embercue.app", embercueProcessIdentifier: 1), "a distinct frontmost application may receive Command-C")
        try require(!AutomaticSelectionCopyTarget.isEligible(frontmostBundleIdentifier: "com.embercue.app", frontmostProcessIdentifier: 1, embercueBundleIdentifier: "com.embercue.app", embercueProcessIdentifier: 1), "Embercue must never target itself for automatic Command-C")
        let targetSource = FakeAutomaticCopyTargetSource(); targetSource.frontmostProcessIdentifier = 42
        try require(AutomaticSelectionCopyTarget.isStillFrontmost(capturedProcessIdentifier: 42, currentProcessIdentifier: targetSource.currentProcessIdentifier()), "automatic copy may read only while its captured target remains frontmost")
        targetSource.frontmostProcessIdentifier = 43
        try require(!AutomaticSelectionCopyTarget.isStillFrontmost(capturedProcessIdentifier: 42, currentProcessIdentifier: targetSource.currentProcessIdentifier()), "focus loss must fail closed before automatic clipboard capture")
        try require(AutomaticSelectionCopyPasteboardChange.classify(before: 10, after: 11) == .exactlyOne, "exactly one post-copy pasteboard change is acceptable")
        try require(AutomaticSelectionCopyPasteboardChange.classify(before: 10, after: 12) == .unexpected, "a pasteboard count jump must fail closed")

        let missingCopierReader = FakeSelectedTextReader(); missingCopierReader.isTrusted = true; missingCopierReader.selectedTextFailure = SelectedTextCaptureError.unavailable
        let missingCopierMonitor = FakeDoubleShiftMonitor()
        let missingCopierPreferences = FakeDoubleShiftCapturePreferences(); missingCopierPreferences.doubleShiftCaptureEnabled = true
        var missingCopierErrors: [Error] = []
        let missingCopierCoordinator = SelectedTextCaptureCoordinator(reader: missingCopierReader, monitor: missingCopierMonitor, preferences: missingCopierPreferences, capture: { _ in }, reportError: { missingCopierErrors.append($0) })
        missingCopierCoordinator.restore()
        missingCopierMonitor.trigger()
        try require((missingCopierErrors.last as? SelectedTextCaptureError) == .automaticCopyFailed, "enabled capture must fail closed when its guarded copier is unavailable")

        let failedReader = FakeSelectedTextReader(); failedReader.isTrusted = true
        let failedMonitor = FakeDoubleShiftMonitor(); failedMonitor.startSucceeds = false
        let failedPreferences = FakeDoubleShiftCapturePreferences()
        var failedErrors: [Error] = []
        let failedCoordinator = SelectedTextCaptureCoordinator(reader: failedReader, monitor: failedMonitor, preferences: failedPreferences, capture: { _ in }, reportError: { failedErrors.append($0) }, captureConfirmation: { true })
        failedCoordinator.performMenuAction()
        try require(failedCoordinator.status == .disabled && !failedPreferences.doubleShiftCaptureEnabled && failedMonitor.starts == 1 && (failedErrors.first as? SelectedTextCaptureError) == .monitorUnavailable, "failed monitor registration must not claim enabled and must report a retryable error")
        failedMonitor.startSucceeds = true
        failedCoordinator.performMenuAction()
        try require(failedCoordinator.status == .enabled && failedMonitor.starts == 2, "a monitor registration failure must be retryable")

        let suiteName = "EmbercueChecks.SelectedTextCapture.\(UUID().uuidString)"
        let initialDefaults = UserDefaults(suiteName: suiteName)!
        initialDefaults.removePersistentDomain(forName: suiteName)
        defer { initialDefaults.removePersistentDomain(forName: suiteName) }
        initialDefaults.set(true, forKey: "selectedTextCaptureEnabled")
        let restoredDefaults = UserDefaults(suiteName: suiteName)!
        try require(!UserDefaultsDoubleShiftCapturePreferences(defaults: restoredDefaults).doubleShiftCaptureEnabled, "legacy selection-only consent must not enable unified Command-C capture")
        UserDefaultsDoubleShiftCapturePreferences(defaults: restoredDefaults).doubleShiftCaptureEnabled = true
        try require(UserDefaultsDoubleShiftCapturePreferences(defaults: UserDefaults(suiteName: suiteName)!).doubleShiftCaptureEnabled, "unified capture must persist only after its explicit opt-in")

        let activationReader = FakeSelectedTextReader()
        let activationMonitor = FakeDoubleShiftMonitor()
        let activationPreferences = FakeDoubleShiftCapturePreferences(); activationPreferences.doubleShiftCaptureEnabled = true
        let activationCoordinator = SelectedTextCaptureCoordinator(reader: activationReader, monitor: activationMonitor, preferences: activationPreferences, capture: { _ in })
        activationCoordinator.restore()
        let activationRelay = ApplicationDidBecomeActiveRelay()
        var activationCallbacks = 0
        activationRelay.start {
            activationCallbacks += 1
            activationCoordinator.refreshAuthorization()
        }
        activationReader.isTrusted = true
        NotificationCenter.default.post(name: NSApplication.didBecomeActiveNotification, object: NSApp)
        try require(activationCallbacks == 1, "didBecomeActive relay must refresh authorization synchronously on the main queue")
        let firstActivationDeadline = Date().addingTimeInterval(1)
        while activationCallbacks < 1 && Date() < firstActivationDeadline {
            RunLoop.current.run(until: min(firstActivationDeadline, Date().addingTimeInterval(0.01)))
        }
        try require(activationCallbacks == 1, "first didBecomeActive relay callback must arrive before its deadline")
        NotificationCenter.default.post(name: NSApplication.didBecomeActiveNotification, object: NSApp)
        let secondActivationDeadline = Date().addingTimeInterval(1)
        while activationCallbacks < 2 && Date() < secondActivationDeadline {
            RunLoop.current.run(until: min(secondActivationDeadline, Date().addingTimeInterval(0.01)))
        }
        activationRelay.stop()
        NotificationCenter.default.post(name: NSApplication.didBecomeActiveNotification, object: NSApp)
        try require(activationCallbacks == 2, "a stopped activation relay must not invoke a deferred callback")
        try require(activationCallbacks == 2 && activationCoordinator.status == .enabled && activationMonitor.starts == 1, "didBecomeActive relay must refresh newly granted trust exactly once")

        try require(
            SelectedTextCaptureStatus.disabled.menuTitle == "Enable Double-Shift Capture…" &&
                SelectedTextCaptureStatus.awaitingPermission.menuTitle == "Waiting for Accessibility… (Cancel Setup)" &&
                SelectedTextCaptureStatus.enabled.menuTitle == "Disable Double-Shift Capture",
            "each selected-text lifecycle state must expose an explicit menu title"
        )
    }

    static func recoveryAndSafetyChecks() throws {
        let root = try temporaryRoot("Embercue-recovery")
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = try JSONLibraryRepository(rootURL: root)
        let primary = try fixtureDocument(revision: 1, text: "primary")
        try repository.save(primary, expectedRevision: 0)
        var backup = primary; backup.revision = 2
        try repository.save(backup, expectedRevision: 1)
        let backupRaw = try Data(contentsOf: repository.backupURL)
        let corrupt = Data("not-json".utf8)
        try corrupt.write(to: repository.documentURL)
        let recovered = try repository.load()
        try require(recovered.document == primary, "corrupt primary must recover the valid backup")
        let restoredBytes = try Data(contentsOf: repository.documentURL)
        try require(restoredBytes == backupRaw, "recovery must restore backup bytes exactly")
        guard case .recoveredFromBackup = recovered.recoveryNotice else { throw CheckFailure.failed("recovery requires a named notice") }

        let malformedRoot = try temporaryRoot("Embercue-malformed")
        defer { try? FileManager.default.removeItem(at: malformedRoot) }
        let malformedRepo = try JSONLibraryRepository(rootURL: malformedRoot)
        try Data("{\"schemaVersion\":999,\"revision\":1,\"items\":[]}".utf8).write(to: malformedRepo.documentURL)
        let future = try malformedRepo.load()
        try require(future.document == LibraryDocument(), "future schema must not become live data")
        guard case .startedEmpty = future.recoveryNotice else { throw CheckFailure.failed("future schema must be quarantined") }
        let quarantineNames = try FileManager.default.contentsOfDirectory(atPath: malformedRoot.path)
        try require(quarantineNames.contains(where: { $0.hasPrefix("library.quarantine-") }), "future schema must preserve a quarantine file")

        let invalidBackupRoot = try temporaryRoot("Embercue-invalid-backup")
        defer { try? FileManager.default.removeItem(at: invalidBackupRoot) }
        let invalidBackupRepo = try JSONLibraryRepository(rootURL: invalidBackupRoot)
        let invalidBackup = Data("invalid backup".utf8)
        try invalidBackup.write(to: invalidBackupRepo.backupURL)
        let invalidBackupResult = try invalidBackupRepo.load()
        guard case let .startedEmptyWithQuarantinedBackup(quarantinedName) = invalidBackupResult.recoveryNotice else { throw CheckFailure.failed("invalid backup-only state must have a distinct notice") }
        let quarantinedInvalidBackup = invalidBackupRoot.appendingPathComponent(quarantinedName)
        let preservedInvalidBackup = try Data(contentsOf: quarantinedInvalidBackup)
        try require(preservedInvalidBackup == invalidBackup && permissions(of: quarantinedInvalidBackup) == 0o600, "invalid backup must be byte-preserved and owner-only")
        try require(!FileManager.default.fileExists(atPath: invalidBackupRepo.documentURL.path) && !FileManager.default.fileExists(atPath: invalidBackupRepo.backupURL.path), "invalid backup-only recovery must not create a primary or retain active backup")
        let invalidBackupEngine = try LibraryEngine(repository: invalidBackupRepo)
        _ = try invalidBackupEngine.add(kind: .prompt, text: "first valid mutation")
        _ = try invalidBackupEngine.add(kind: .prompt, text: "second valid mutation")
        let invalidBackupRelaunch = try JSONLibraryRepository(rootURL: invalidBackupRoot).load().document
        try require(invalidBackupRelaunch.revision == 2 && invalidBackupRelaunch.items.map(\.text) == ["first valid mutation", "second valid mutation"], "invalid backup-only recovery must support mutation and relaunch")

        let corruptBothRoot = try temporaryRoot("Embercue-corrupt-both")
        defer { try? FileManager.default.removeItem(at: corruptBothRoot) }
        let corruptBothRepo = try JSONLibraryRepository(rootURL: corruptBothRoot)
        let corruptPrimary = Data("invalid primary".utf8)
        let corruptBackup = Data("invalid backup".utf8)
        try corruptPrimary.write(to: corruptBothRepo.documentURL)
        try corruptBackup.write(to: corruptBothRepo.backupURL)
        let corruptBothResult = try corruptBothRepo.load()
        guard case let .startedEmptyWithQuarantinedPrimaryAndBackup(primaryName, backupName) = corruptBothResult.recoveryNotice else { throw CheckFailure.failed("corrupt primary and backup need dual quarantine notice") }
        let quarantinedPrimary = corruptBothRoot.appendingPathComponent(primaryName)
        let quarantinedBackup = corruptBothRoot.appendingPathComponent(backupName)
        let preservedInvalidPrimary = try Data(contentsOf: quarantinedPrimary)
        let preservedCorruptBackup = try Data(contentsOf: quarantinedBackup)
        try require(preservedInvalidPrimary == corruptPrimary && preservedCorruptBackup == corruptBackup, "corrupt primary and backup must both be byte-preserved")
        try require(permissions(of: quarantinedPrimary) == 0o600 && permissions(of: quarantinedBackup) == 0o600, "dual quarantines must be owner-only")
        let corruptBothEngine = try LibraryEngine(repository: corruptBothRepo)
        _ = try corruptBothEngine.add(kind: .prompt, text: "first valid mutation")
        _ = try corruptBothEngine.add(kind: .prompt, text: "second valid mutation")
        let corruptBothRelaunch = try JSONLibraryRepository(rootURL: corruptBothRoot).load().document
        try require(corruptBothRelaunch.revision == 2 && corruptBothRelaunch.items.count == 2, "dual-corrupt recovery must support mutation and relaunch")

        let symlinkRoot = try temporaryRoot("Embercue-symlink")
        defer { try? FileManager.default.removeItem(at: symlinkRoot) }
        let symlinkRepo = try JSONLibraryRepository(rootURL: symlinkRoot)
        let target = symlinkRoot.appendingPathComponent("outside.json")
        let targetData = Data("do not touch".utf8)
        try targetData.write(to: target)
        try FileManager.default.createSymbolicLink(at: symlinkRepo.documentURL, withDestinationURL: target)
        _ = try symlinkRepo.load()
        let targetAfterLoad = try Data(contentsOf: target)
        try require(targetAfterLoad == targetData, "managed symlink target must never be read or modified")

        let symlinkParent = try temporaryRoot("Embercue-symlink-root")
        defer { try? FileManager.default.removeItem(at: symlinkParent) }
        let symlinkTargetRoot = symlinkParent.appendingPathComponent("target", isDirectory: true)
        let symlinkRootURL = symlinkParent.appendingPathComponent("link", isDirectory: true)
        try FileManager.default.createDirectory(at: symlinkTargetRoot, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: symlinkRootURL, withDestinationURL: symlinkTargetRoot)
        do { _ = try JSONLibraryRepository(rootURL: symlinkRootURL); throw CheckFailure.failed("symlink storage root accepted") } catch LibraryRepositoryError.invalidStorageRoot {}

        let sizeRoot = try temporaryRoot("Embercue-size")
        defer { try? FileManager.default.removeItem(at: sizeRoot) }
        let sizeRepo = try JSONLibraryRepository(rootURL: sizeRoot)
        FileManager.default.createFile(atPath: sizeRepo.documentURL.path, contents: Data())
        let handle = try FileHandle(forWritingTo: sizeRepo.documentURL)
        try handle.truncate(atOffset: UInt64(JSONLibraryRepository.maximumDocumentBytes + 1))
        try handle.close()
        let oversized = try sizeRepo.load()
        guard case .startedEmpty = oversized.recoveryNotice else { throw CheckFailure.failed("oversized primary must be quarantined") }

        let restrictiveRoot = try temporaryRoot("Embercue-umask")
        defer { try? FileManager.default.removeItem(at: restrictiveRoot) }
        let restrictive = try JSONLibraryRepository(rootURL: restrictiveRoot)
        let export = restrictiveRoot.appendingPathComponent("export.json")
        let oldUmask = umask(0o777)
        defer { _ = umask(oldUmask) }
        try restrictive.export(try fixtureDocument(revision: 0, text: "export"), to: export)
        try require(permissions(of: export) == 0o600, "exports must force owner-only permissions despite restrictive umask")

        let guardedDocument = try fixtureDocument(revision: 1, text: "guarded")
        let guardedRoot = try temporaryRoot("Embercue-reserved-export")
        defer { try? FileManager.default.removeItem(at: guardedRoot) }
        let guardedRepo = try JSONLibraryRepository(rootURL: guardedRoot)
        try guardedRepo.save(guardedDocument, expectedRevision: 0)
        let primaryBeforeExport = try Data(contentsOf: guardedRepo.documentURL)
        let alias = guardedRoot.appendingPathComponent("primary-alias.json")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: guardedRepo.documentURL)
        do { try guardedRepo.export(guardedDocument, to: alias); throw CheckFailure.failed("symlink alias of primary accepted as export destination") } catch LibraryRepositoryError.reservedExportDestination {}
        let primaryAfterExport = try Data(contentsOf: guardedRepo.documentURL)
        try require(primaryAfterExport == primaryBeforeExport, "reserved alias export must not alter primary")

        do {
            _ = try JSONLibraryRepository.defaultRootURL(environment: [JSONLibraryRepository.dataDirectoryEnvironmentVariable: "relative"])
            throw CheckFailure.failed("relative storage override accepted")
        } catch LibraryRepositoryError.invalidStorageRoot {}
    }

    static func concurrentWriterChecks() throws {
        let root = try temporaryRoot("Embercue-concurrent")
        defer { try? FileManager.default.removeItem(at: root) }
        let repo = try JSONLibraryRepository(rootURL: root)
        try repo.save(try fixtureDocument(revision: 1, text: "seed"), expectedRevision: 0)
        let executable = URL(fileURLWithPath: CommandLine.arguments[0])
        let processes = ["writer one", "writer two"].map { text -> Process in
            let process = Process()
            process.executableURL = executable
            process.arguments = ["--concurrent-writer", root.path, text]
            process.standardOutput = Pipe(); process.standardError = Pipe()
            return process
        }
        try processes.forEach { try $0.run() }
        processes.forEach { $0.waitUntilExit() }
        let statuses = processes.map(\.terminationStatus).sorted()
        try require(statuses == [0, 1], "two writers at one revision must yield one success and one conflict")
        let final = try JSONLibraryRepository(rootURL: root).load().document
        try require(final.revision == 2 && final.items.count == 2, "concurrent writers must leave one durable atomic mutation")
    }

    static func concurrentWriter(root: URL, text: String) throws {
        let engine = try LibraryEngine(repository: JSONLibraryRepository(rootURL: root))
        // Both child processes have loaded the same revision before either save.
        // This is a test-only barrier, not a product retry policy.
        usleep(300_000)
        _ = try engine.add(kind: .prompt, text: text)
    }

    static func fixtureChecks() throws {
        let root = try temporaryRoot("Embercue-fixture")
        defer { try? FileManager.default.removeItem(at: root) }
        try writeVisualFixture(root)
        let repository = try JSONLibraryRepository(rootURL: root)
        let document = try repository.load().document
        try require(document.revision == 1 && document.sections.map(\.name) == ["RESEARCH", "CONFIGURATION FORMATS"], "visual fixture must have stable ordered sections")
        try require(document.items.map(\.text) == ["**Save this useful answer** for later and keep the *important* context.", "Three things worth locking down before it ships:", "How should configuration migrations work?", "Should plugins own their configuration schema?"], "visual fixture must have exact observed scenario cards")
        try require(permissions(of: root) == 0o700 && permissions(of: repository.documentURL) == 0o600, "visual fixture must use production repository permissions")
    }

    static func markdownBoundaryChecks() throws {
        let rendered = SafeMarkdownRenderer.render("**bold** *italic* `code` ~~strike~~ [label](https://example.invalid/secret) ![alt text](https://example.invalid/image.png) <b>hidden</b>")
        let visible = String(rendered.characters)
        try require(visible.contains("bold") && visible.contains("italic") && visible.contains("code") && visible.contains("strike"), "safe Markdown renderer must retain allowed local text runs")
        try require(visible.contains("label") && visible.contains("alt text"), "safe Markdown renderer must retain link labels and image alt text")
        try require(!visible.contains("https://") && !visible.contains("<b>"), "safe Markdown renderer must discard destinations and HTML tags")
    }

    static func presentationChecks() throws {
        try require(RightEdgePlacement.defaultPanelSize == NSSize(width: 364, height: 640), "rail geometry token must match video candidate")
        let frame = RightEdgePlacement.constrainedFrame(visibleFrame: CGRect(x: 0, y: 0, width: 1920, height: 1080), panelSize: RightEdgePlacement.defaultPanelSize)
        try require(abs(frame.maxX - 1856) < 0.1 && abs(frame.midY - 540) < 0.1, "rail must be 64pt inset and vertically centered")
        try require(BackgroundResidencyPolicy.shouldTerminateAfterLastWindowClosed == false && BackgroundResidencyPolicy.shouldClosePanel == false, "close must preserve background residency")
        try require(AppController.qaAppearance(environment: [:]) == nil, "normal launch must not override appearance")
        try require(AppController.qaAppearance(environment: ["EMBERCUE_QA_APPEARANCE": "light"]) == nil, "appearance variable without isolated data root must be ignored")
        try require(AppController.qaAppearance(environment: [JSONLibraryRepository.dataDirectoryEnvironmentVariable: "/tmp/isolated", "EMBERCUE_QA_APPEARANCE": "light"])?.name == .aqua, "isolated light QA must resolve Aqua")
        try require(AppController.qaAppearance(environment: [JSONLibraryRepository.dataDirectoryEnvironmentVariable: "/tmp/isolated", "EMBERCUE_QA_APPEARANCE": "dark"])?.name == .darkAqua, "isolated dark QA must resolve Dark Aqua")
        try require(AppController.qaAppearance(environment: [JSONLibraryRepository.dataDirectoryEnvironmentVariable: "/tmp/isolated", "EMBERCUE_QA_APPEARANCE": "invalid"]) == nil, "invalid QA appearance must be ignored")
        let large = CGRect(x: 100, y: 50, width: 1400, height: 1000)
        let short = CGRect(x: 100, y: 50, width: 1200, height: 650)
        let narrow = CGRect(x: 100, y: 50, width: 340, height: 800)
        let tiny = CGRect(x: 100, y: 50, width: 300, height: 500)
        try require(RightEdgePlacement.constrainedFrame(visibleFrame: large, panelSize: RightEdgePlacement.defaultPanelSize).maxX == large.maxX - RightEdgePlacement.margin, "large display placement must retain inset")
        try require(RightEdgePlacement.effectiveMinimumPanelSize(for: large) == RightEdgePlacement.minimumPanelSize, "normal display must retain formal panel minimum")
        try require(short.contains(RightEdgePlacement.constrainedFrame(visibleFrame: short, panelSize: RightEdgePlacement.defaultPanelSize)), "short display must contain panel")
        try require(narrow.contains(RightEdgePlacement.constrainedFrame(visibleFrame: narrow, panelSize: RightEdgePlacement.defaultPanelSize)), "narrow display must contain panel")
        try require(tiny.contains(RightEdgePlacement.constrainedFrame(visibleFrame: tiny, panelSize: RightEdgePlacement.defaultPanelSize, inset: -1)) && RightEdgePlacement.effectiveMinimumPanelSize(for: tiny) == tiny.size, "tiny display must lower minimum safely")
        let enlarged = RightEdgePlacement.constrainedFrame(visibleFrame: large, panelSize: NSSize(width: 440, height: 860))
        try require(enlarged.size == NSSize(width: 440, height: 860) && enlarged.maxX == large.maxX - RightEdgePlacement.margin && enlarged.midY == large.midY, "large displays must retain deliberate expanded panel geometry")
    }

    static func adapterRegressionChecks() throws {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("EmbercueChecks.\(UUID().uuidString)"))
        let clipboard = NSPasteboardClipboard(pasteboard: pasteboard)
        let clipboardRoot = try temporaryRoot("Embercue-isolated-pasteboard")
        defer { try? FileManager.default.removeItem(at: clipboardRoot) }
        let firstFile = clipboardRoot.appendingPathComponent("first.txt")
        let secondFile = clipboardRoot.appendingPathComponent("second.txt")
        try Data().write(to: firstFile)
        try Data().write(to: secondFile)
        try require(
            clipboard.write(ClipboardPayload(text: "mixed clipboard text", fileURLs: [firstFile, secondFile])),
            "mixed clipboard payload must write to an isolated pasteboard"
        )
        try require(pasteboard.string(forType: .string) == "mixed clipboard text", "mixed clipboard payload must retain its text")
        let pastedURLs = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL]
        try require(pastedURLs == [firstFile, secondFile], "mixed clipboard payload must retain every file URL")

        let failing = FakeHotKey(); failing.fail = true
        let coordinator = HotKeyAvailabilityCoordinator(hotKey: failing); var menus = 0
        coordinator.composeMenuFallback { menus += 1 }
        try require(coordinator.start(action: {}) != nil && menus == 1 && failing.starts == 1 && failing.stops == 1, "hotkey failure must retain menu fallback and stop")
        let working = FakeHotKey(); let workingCoordinator = HotKeyAvailabilityCoordinator(hotKey: working)
        try require(workingCoordinator.start(action: {}) == nil, "working hotkey must start")
        workingCoordinator.stop()
        try require(working.stops == 1, "hotkey lifecycle must stop")
        let other = FakeForeground("other", 77); var front: (any ForegroundApplication)? = other
        let tracker = ForegroundApplicationTracker(frontmostApplication: { front }, ownProcessIdentifier: 99)
        tracker.capturePreviousApplication(ignoring: "own"); tracker.reactivatePreviousApplication(); tracker.reactivatePreviousApplication()
        try require(other.activations == 1, "foreground return must reactivate once")
        front = FakeForeground("own", 99)
        tracker.capturePreviousApplication(ignoring: "own"); tracker.reactivatePreviousApplication()
        try require(other.activations == 1, "ineligible capture must clear the prior foreground target")
        try require(
            RailShortcutRouter.shortcut(characters: "c", modifiers: [.command, .capsLock, .numericPad]) == .copy &&
                RailShortcutRouter.shortcut(characters: "m", modifiers: [.command, .shift]) == .mergeNotes &&
                RailShortcutRouter.shortcut(characters: "\r", modifiers: []) == .edit &&
                RailShortcutRouter.shortcut(characters: "\n", modifiers: []) == .edit,
            "rail shortcuts must ignore non-command modifier noise and map documented commands"
        )
        let selectedTextView = NSTextView()
        selectedTextView.string = "selected text"
        selectedTextView.setSelectedRange(NSRange(location: 0, length: 8))
        try require(
            !RailShortcutRouter.acceptsRailShortcut(.copy, firstResponder: selectedTextView) &&
                RailShortcutRouter.acceptsRailShortcut(.copyAsList, firstResponder: selectedTextView) &&
                !RailShortcutRouter.acceptsRailShortcut(.edit, firstResponder: selectedTextView),
            "selected NSTextView text must retain Command-C and Return"
        )
        selectedTextView.setSelectedRange(NSRange(location: 0, length: 0))
        try require(
            RailShortcutRouter.acceptsRailShortcut(.copy, firstResponder: selectedTextView) &&
                !RailShortcutRouter.acceptsRailShortcut(.copy, firstResponder: NSTextField()) &&
                RailShortcutRouter.acceptsRailShortcut(.copy, firstResponder: nil),
            "only an empty NSTextView selection may fall through to selected rail cards"
        )
        let applicationMenu = EmbercueApplicationMenu.make()
        let editItems = applicationMenu.items.first(where: { $0.submenu?.title == "Edit" })?.submenu?.items ?? []
        let expectedEditShortcuts: [(String, NSEvent.ModifierFlags, Selector)] = [
            ("z", [.command], Selector(("undo:"))),
            ("z", [.command, .shift], Selector(("redo:"))),
            ("x", [.command], #selector(NSText.cut(_:))),
            ("c", [.command], #selector(NSText.copy(_:))),
            ("v", [.command], #selector(NSText.paste(_:))),
            ("a", [.command], #selector(NSText.selectAll(_:)))
        ]
        try require(expectedEditShortcuts.allSatisfy { key, modifiers, action in
            editItems.contains(where: { $0.keyEquivalent == key && $0.keyEquivalentModifierMask == modifiers && $0.action == action && $0.target == nil })
        }, "application Edit menu must expose standard responder-chain text shortcuts")

        let statusItemController = StatusItemController(onShow: {}, onExport: {})
        let statusItems = statusItemController.menuItemsForTesting.filter { !$0.isSeparatorItem }
        try require(statusItemController.statusButtonTitleForTesting == WorkbenchLifecycleMenuTitles.menuBarTitle, "menu-bar status item must expose an Embercue title alongside its icon")
        try require(
            statusItems.map(\.title) == ["Show Embercue", "No prompts waiting", "Export Library Metadata…", "Quit Embercue"] &&
                statusItems.last?.keyEquivalent == "q" && statusItems.last?.keyEquivalentModifierMask == [.command],
            "status menu must retain Show, Export, and Command-Q Quit actions"
        )
        try require(
            WorkbenchLifecycleMenuTitles.hideToMenuBar == "Hide to Menu Bar" && WorkbenchLifecycleMenuTitles.quit == "Quit Embercue",
            "overflow menu must expose explicit menu-bar residency and quit labels"
        )

        var hideCallbacks = 0
        let lifecyclePanel = PanelController(
            rootView: EmptyView(),
            tracker: ForegroundApplicationTracker(frontmostApplication: { nil }, ownProcessIdentifier: 99),
            onShow: {},
            onHide: { hideCallbacks += 1 }
        )
        lifecyclePanel.hide()
        try require(hideCallbacks == 1, "hide must invoke the unified hide callback exactly once")
        lifecyclePanel.hideAndReturn()
        try require(hideCallbacks == 2, "hideAndReturn must invoke the unified hide callback exactly once")
        let closeResult = lifecyclePanel.windowShouldClose(NSWindow())
        try require(hideCallbacks == 3 && closeResult == BackgroundResidencyPolicy.shouldClosePanel, "windowShouldClose must hide through the same callback exactly once")
    }

    static func cardSelectionInteractionChecks() throws {
        try require(WorkbenchSelectionModeResolver.mode(for: []) == .replace, "plain pointer flags must replace selection")
        try require(WorkbenchSelectionModeResolver.mode(for: [.command]) == .toggle, "Command pointer flags must toggle selection")
        try require(WorkbenchSelectionModeResolver.mode(for: [.shift]) == .extend, "Shift pointer flags must extend selection")
        try require(WorkbenchSelectionModeResolver.mode(for: [.command, .shift, .capsLock]) == .extend, "Shift must retain the existing range-selection precedence over Command and irrelevant flags")
        try require(ItemCardPresentation.accessibilityValue(selected: true, state: .completed) == "Completed, selected", "card accessibility value must express both completion and selection")
        try require(ItemCardPresentation.accessibilityValue(selected: false, state: .archived) == "Archived, not selected", "archived history cards must not be announced as active")
        try require(ItemCardPresentation.accessibilitySummary(markdown: "**Bold** [label](https://example.invalid)") == "Bold label", "card accessibility labels must use sanitized Markdown text")

        let harness = try CardInteractionHarness()
        defer { harness.close() }
        let initialBody = try harness.body(for: harness.first)
        let initialCircle = try harness.circle(for: harness.first)
        let initialContext = try harness.context(for: harness.first)
        try require(initialCircle.bounds.size == NSSize(width: 28, height: 28), "circle native hit target must be 28pt while its visual slot stays compact")
        try require(initialBody.bounds.width > 0 && initialBody.bounds.height > 0, "body native hit target must have a nonzero explicit frame")
        try require(initialContext.bounds.width > 0 && initialContext.bounds.height > 0, "context capture surface must retain its stable accessibility identifier and card-sized frame")

        try harness.clickBody(harness.first, downFlags: [], upFlags: [])
        try require(harness.model.selectedIDs == [harness.first.id], "plain body click must select exactly its card")
        let bodyOwnsKeyboardFocus = try harness.bodyOwnsKeyboardFocus(harness.first)
        try require(bodyOwnsKeyboardFocus, "plain body click must move keyboard focus from the composer to the selected card")
        let selectedBody = try harness.body(for: harness.first)
        try require(selectedBody.accessibilityValue() as? String == "Selected", "selected body accessibility value must update immediately")

        try harness.clickBody(harness.second, downFlags: [.command], upFlags: [])
        try require(harness.model.selectedIDs == [harness.first.id, harness.second.id], "mouse-down Command must survive a different mouse-up modifier state")

        try harness.performClickBody(harness.second)
        try require(harness.model.selectedIDs == [harness.second.id], "performClick after a Command pointer transaction must use replace instead of stale toggle")
        let accessibilityPressOwnsKeyboardFocus = try harness.bodyOwnsKeyboardFocus(harness.second)
        try require(accessibilityPressOwnsKeyboardFocus, "accessibility Press must move keyboard focus to the activated card")

        try harness.clickBody(harness.first, downFlags: [], upFlags: [])
        try harness.clickBody(harness.third, downFlags: [.shift], upFlags: [])
        try require(harness.model.selectedIDs == [harness.first.id, harness.second.id, harness.third.id], "mouse-down Shift must select the visible inclusive range from the existing selection anchor")

        harness.model.select(harness.second)
        try harness.clickCircle(harness.first, downFlags: [], upFlags: [])
        try require(harness.model.selectedIDs == [harness.first.id, harness.second.id], "circle must toggle exactly once without also selecting its card body")

        let circleEdgePoints = [
            NSPoint(x: 1, y: 14),
            NSPoint(x: 27, y: 14),
            NSPoint(x: 14, y: 1),
            NSPoint(x: 14, y: 27)
        ]
        for point in circleEdgePoints {
            harness.model.select(harness.second)
            try harness.clickCircle(harness.first, at: point)
            try require(harness.model.selectedIDs == [harness.first.id, harness.second.id], "each 28pt circle edge point must hit once without activating the body")
        }

        for _ in 0..<20 { try harness.clickBody(harness.first, downFlags: [], upFlags: []) }
        try require(harness.model.selectedIDs == [harness.first.id], "rapid body clicks must remain stable and commit once per mouse-up")

        harness.model.select(harness.second, mode: .toggle)
        harness.model.prepareContext(for: harness.first)
        try require(harness.model.selectedIDs == [harness.first.id, harness.second.id], "selected-card context must preserve the existing multi-selection")
        harness.model.prepareContext(for: harness.third)
        try require(harness.model.selectedIDs == [harness.third.id], "unselected-card context must establish a single-item scope")
        harness.model.moveSelected(to: harness.destination.id)
        try require(harness.model.document.items.first(where: { $0.id == harness.third.id })?.sectionID == harness.destination.id, "Move must use only the established contextual row")

    }

    static func writeVisualFixture(_ root: URL) throws {
        guard root.path.hasPrefix("/") else { throw CheckFailure.failed("fixture root must be absolute") }
        let manager = FileManager.default
        if manager.fileExists(atPath: root.appendingPathComponent("library.json").path) { throw CheckFailure.failed("fixture root already contains library.json") }
        if manager.fileExists(atPath: root.path), !(try manager.contentsOfDirectory(atPath: root.path)).isEmpty { throw CheckFailure.failed("fixture root must be empty") }
        let researchID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let configurationID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let sections = [try LibrarySection(id: researchID, name: "RESEARCH", sortOrder: 0), try LibrarySection(id: configurationID, name: "CONFIGURATION FORMATS", sortOrder: 1)]
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let items = [
            try LibraryItem(id: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!, kind: .prompt, text: "**Save this useful answer** for later and keep the *important* context.", createdAt: date, updatedAt: date, sectionID: researchID, sortOrder: 0),
            try LibraryItem(id: UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!, kind: .prompt, text: "Three things worth locking down before it ships:", createdAt: date, updatedAt: date, sectionID: configurationID, sortOrder: 0),
            try LibraryItem(id: UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!, kind: .prompt, text: "How should configuration migrations work?", createdAt: date, updatedAt: date, sectionID: configurationID, sortOrder: 1),
            try LibraryItem(id: UUID(uuidString: "DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD")!, kind: .prompt, text: "Should plugins own their configuration schema?", createdAt: date, updatedAt: date, sectionID: configurationID, sortOrder: 2)
        ]
        let repository = try JSONLibraryRepository(rootURL: root)
        try repository.save(LibraryDocument(revision: 1, sections: sections, items: items), expectedRevision: 0)
        print("fixture root=\(root.path) itemIDs=\(items.map { $0.id.uuidString }.joined(separator: ","))")
    }

    private static func literalV1(revision: Int) -> Data {
        Data("{\"schemaVersion\":1,\"revision\":\(revision),\"items\":[{\"id\":\"00000000-0000-0000-0000-000000000001\",\"kind\":\"prompt\",\"state\":\"active\",\"text\":\"legacy prompt\",\"createdAt\":1,\"updatedAt\":1},{\"id\":\"00000000-0000-0000-0000-000000000002\",\"kind\":\"snippet\",\"state\":\"active\",\"text\":\"legacy keep\",\"createdAt\":2,\"updatedAt\":2}]}".utf8)
    }
    private static func literalV2(revision: Int) -> Data {
        Data("{\"schemaVersion\":2,\"revision\":\(revision),\"sections\":[{\"id\":\"9B4EF8E0-917A-4F7C-95A1-4ED5EB0B4D01\",\"name\":\"INBOX\",\"sortOrder\":0},{\"id\":\"A5C8E4F6-26B4-4A3C-90B7-588B45542B02\",\"name\":\"KEEPS\",\"sortOrder\":1}],\"items\":[{\"id\":\"00000000-0000-0000-0000-000000000003\",\"kind\":\"prompt\",\"state\":\"active\",\"text\":\"legacy v2\",\"createdAt\":1,\"updatedAt\":1,\"sectionID\":\"9B4EF8E0-917A-4F7C-95A1-4ED5EB0B4D01\",\"sortOrder\":0}]}".utf8)
    }
    private static func decodedSchema(_ data: Data) throws -> Int {
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return object?["schemaVersion"] as? Int ?? -1
    }
    private static func fixtureDocument(revision: Int, text: String) throws -> LibraryDocument {
        let date = Date(timeIntervalSince1970: 1_700_000_001)
        let item = try LibraryItem(kind: .prompt, text: text, createdAt: date, updatedAt: date, sectionID: LibrarySectionID.inbox, sortOrder: 0)
        return LibraryDocument(revision: revision, items: [item])
    }
    private static func temporaryRoot(_ name: String) throws -> URL {
        let base = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("\(name)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }
    private static func permissions(of url: URL) -> Int { ((try? FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber)?.intValue) ?? -1 }
}
