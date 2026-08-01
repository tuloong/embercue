import Combine
import EmbercueCore
import Foundation

public enum WorkbenchPage: String, CaseIterable, Identifiable { case rail, history; public var id: String { rawValue } }

// Compatibility metadata for callers from the pre-section rail. The visible UI uses a capture section.
public enum CaptureKind: String, CaseIterable, Identifiable {
    case prompt, keep
    public var id: String { rawValue }
    var libraryKind: LibraryItemKind { self == .prompt ? .prompt : .snippet }
    public var label: String { self == .prompt ? "Prompt" : "Keep" }
}

public struct WorkbenchSectionSnapshot: Identifiable, Equatable {
    public let section: LibrarySection
    public let items: [LibraryItem]
    public var id: UUID { section.id }
}

public struct PendingAttachment: Identifiable, Equatable {
    public let sourceURL: URL
    public var id: URL { sourceURL }
    public var filename: String { sourceURL.lastPathComponent }
}

@MainActor
public final class WorkbenchModel: ObservableObject {
    @Published public private(set) var document: LibraryDocument
    @Published public var draft = ""
    @Published public var search = "" { didSet { pruneSelection() } }
    @Published public var page: WorkbenchPage = .rail { didSet { pruneSelection() } }
    @Published public var captureKind: CaptureKind = .prompt
    @Published public var captureSectionID: UUID
    @Published public private(set) var selectedIDs = Set<UUID>()
    @Published public private(set) var expandedIDs = Set<UUID>()
    @Published public private(set) var recentlyCompletedIDs = Set<UUID>()
    @Published public private(set) var inlineEditID: UUID?
    @Published public var inlineEditDraft = ""
    @Published public private(set) var focusRequest = 0
    @Published public private(set) var errorMessage: String?
    @Published public private(set) var successMessage: String?
    @Published public private(set) var recoveryMessage: String?
    @Published public private(set) var selectedTextCaptureStatus: SelectedTextCaptureStatus = .disabled
    @Published public var isCreatingSection = false
    @Published public var newSectionName = ""
    @Published public private(set) var pendingAttachments: [PendingAttachment] = []
    public var onDocumentChange: (() -> Void)?
    public var onOpenEditor: ((LibraryItem) -> Void)?
    public var onSelectedTextCaptureAction: (() -> Void)?

    private let engine: LibraryEngine
    private let clipboard: SystemClipboard
    private let attachmentStore: (any AttachmentStoring)?
    private let completionEchoExpiryScheduler: (@escaping @MainActor () -> Void) -> Void
    private var selectionAnchor: UUID?
    private var successNoticeGeneration = 0

    public init(
        engine: LibraryEngine,
        clipboard: SystemClipboard,
        attachmentStore: (any AttachmentStoring)? = nil,
        completionEchoExpiryScheduler: @escaping (@escaping @MainActor () -> Void) -> Void = { expiry in
            Task { @MainActor in
                do { try await Task.sleep(for: .milliseconds(900)) } catch { return }
                expiry()
            }
        }
    ) {
        self.engine = engine
        self.clipboard = clipboard
        self.attachmentStore = attachmentStore
        self.completionEchoExpiryScheduler = completionEchoExpiryScheduler
        let initialDocument = engine.document
        document = initialDocument
        captureSectionID = initialDocument.sections.sorted { $0.sortOrder < $1.sortOrder }.first?.id ?? LibrarySectionID.inbox
        recoveryMessage = engine.recoveryNotice?.message
    }

    public var sections: [WorkbenchSectionSnapshot] {
        document.sections.sorted { $0.sortOrder < $1.sortOrder }.map { section in
            let active = document.items(in: section.id, states: [.active], matching: search)
            let completionEchoes = document.items(in: section.id, states: [.completed], matching: search)
                .filter { recentlyCompletedIDs.contains($0.id) }
            return WorkbenchSectionSnapshot(section: section, items: (active + completionEchoes).sorted(by: sectionItemOrder))
        }.filter { !$0.items.isEmpty }
    }

    public var historyItems: [LibraryItem] {
        document.items.filter { $0.state != .active && matchesSearch($0) }.sorted(by: itemOrder)
    }

    public var visibleItems: [LibraryItem] {
        page == .rail ? sections.flatMap(\.items) : historyItems
    }

    public var isSearching: Bool { !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    public var hasHistoryItems: Bool { document.items.contains(where: { $0.state != .active }) }
    public var inlineNotice: String? { errorMessage ?? recoveryMessage ?? successMessage }
    public var inlineNoticeIsSuccess: Bool { errorMessage == nil && recoveryMessage == nil && successMessage != nil }
    public var captureSection: LibrarySection? { document.sections.first(where: { $0.id == captureSectionID }) }

    public func requestComposerFocus() { focusRequest &+= 1 }
    public func setSelectedTextCaptureStatus(_ status: SelectedTextCaptureStatus) { selectedTextCaptureStatus = status }
    public func clearCompletionEcho() { recentlyCompletedIDs.removeAll() }
    public func isInlineEditing(_ item: LibraryItem) -> Bool { inlineEditID == item.id }
    public func beginInlineEdit(_ item: LibraryItem) { inlineEditID = item.id; inlineEditDraft = item.text }
    public func cancelInlineEdit() { inlineEditID = nil; inlineEditDraft = "" }
    @discardableResult public func saveInlineEdit() -> Bool {
        guard let id = inlineEditID, let item = document.items.first(where: { $0.id == id }) else { return false }
        let draft = inlineEditDraft
        edit(item, text: draft)
        if errorMessage == nil { cancelInlineEdit(); return true }
        return false
    }
    public func toggleExpanded(_ item: LibraryItem) {
        if expandedIDs.contains(item.id) { expandedIDs.remove(item.id) } else { expandedIDs.insert(item.id) }
    }

    public func select(_ item: LibraryItem, mode: WorkbenchSelectionMode = .replace) {
        let ordered = visibleItems.map(\.id)
        switch mode {
        case .replace:
            selectedIDs = [item.id]
            selectionAnchor = item.id
        case .toggle:
            if selectedIDs.contains(item.id) { selectedIDs.remove(item.id) } else { selectedIDs.insert(item.id) }
            selectionAnchor = item.id
        case .extend:
            guard let anchor = selectionAnchor, let start = ordered.firstIndex(of: anchor), let end = ordered.firstIndex(of: item.id) else {
                selectedIDs = [item.id]; selectionAnchor = item.id; return
            }
            selectedIDs = Set(ordered[min(start, end)...max(start, end)])
        }
        if selectedIDs.isEmpty { clearCompletionEcho() }
    }

    public func toggleCircle(_ item: LibraryItem) { select(item, mode: .toggle) }
    public func prepareContext(for item: LibraryItem) {
        if !isSelected(item) { select(item) }
    }
    public func selectedDisplayItems() -> [LibraryItem] { visibleItems.filter { selectedIDs.contains($0.id) } }
    public var canMergeSelection: Bool {
        let items = selectedDisplayItems()
        return items.count >= 2 && items.allSatisfy { $0.state == .active } && Set(items.map(\.sectionID)).count == 1
    }
    public func isSelected(_ item: LibraryItem) -> Bool { selectedIDs.contains(item.id) }
    public func isExpanded(_ item: LibraryItem) -> Bool { expandedIDs.contains(item.id) }
    public func isCompletionEcho(_ item: LibraryItem) -> Bool { recentlyCompletedIDs.contains(item.id) || item.state == .completed }

    public func submitDraft() {
        let text = draft
        if pendingAttachments.isEmpty, let sectionName = composerSectionName(in: text) {
            perform {
                let section = try engine.createSection(name: sectionName)
                captureSectionID = section.id
                draft = ""
                page = .rail
            }
            return
        }
        perform {
            let attachments = try importPendingAttachments()
            do {
                _ = try engine.add(kind: captureKind.libraryKind, text: text, attachments: attachments, to: captureSectionID)
            } catch {
                attachments.forEach { attachmentStore?.remove($0) }
                throw error
            }
            draft = ""; pendingAttachments = []; page = .rail
        }
    }
    public func addPendingAttachments(urls: [URL]) {
        guard let attachmentStore else { errorMessage = "Attachments are unavailable in this library."; return }
        let new = urls.filter { url in !pendingAttachments.contains(where: { $0.sourceURL == url }) }
        guard pendingAttachments.count + new.count <= LibraryAttachment.maximumPerItem else { errorMessage = "Attach at most \(LibraryAttachment.maximumPerItem) files to one card."; return }
        do {
            try new.forEach { try attachmentStore.validateSource(at: $0) }
            pendingAttachments.append(contentsOf: new.map(PendingAttachment.init(sourceURL:)))
            errorMessage = nil
        } catch { errorMessage = error.localizedDescription }
    }
    public func removePendingAttachment(_ attachment: PendingAttachment) { pendingAttachments.removeAll { $0.id == attachment.id } }
    public func attachmentURL(for attachment: LibraryAttachment) -> URL? { attachmentStore?.url(for: attachment) }
    public func queueDraft() { captureKind = .prompt; captureSectionID = LibrarySectionID.inbox; submitDraft() }
    public func keepDraft() { captureKind = .keep; captureSectionID = LibrarySectionID.keeps; submitDraft() }
    public func keepClipboard() {
        guard let text = clipboard.readPlainText() else { errorMessage = "The clipboard does not contain plain text."; return }
        let destination = document.sections.contains(where: { $0.id == LibrarySectionID.keeps }) ? LibrarySectionID.keeps : captureSectionID
        perform { _ = try engine.add(kind: .snippet, text: text, to: destination); page = .rail }
    }
    public func captureSelectedText(_ text: String) {
        perform { _ = try engine.add(kind: .prompt, text: text, to: captureSectionID); page = .rail }
    }

    @discardableResult public func copy(_ item: LibraryItem) -> Bool { copy(items: [item]) }
    @discardableResult public func copySelected() -> Bool { copy(items: selectedDisplayItems()) }
    @discardableResult public func copyAsList() -> Bool {
        let items = selectedDisplayItems()
        guard !items.isEmpty else { errorMessage = "Select one or more notes first."; return false }
        let textItems = items.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let fileURLs = items.flatMap(\.attachments).compactMap(attachmentURL(for:))
        guard fileURLs.count == items.flatMap(\.attachments).count else { errorMessage = "An attachment is unavailable in private storage."; return false }
        let text = textItems.isEmpty ? nil : LibraryListFormatter.numberedList(textItems)
        guard clipboard.write(ClipboardPayload(text: text, fileURLs: fileURLs)) else { errorMessage = "Embercue could not write to the clipboard."; return false }
        do {
            try engine.complete(items.map(\.id))
            document = engine.document
            recentlyCompletedIDs.formUnion(items.map(\.id))
            errorMessage = nil
            showSuccess("Copied × \(items.count)")
            onDocumentChange?()
            return true
        } catch {
            errorMessage = "Copied the list, but could not mark the notes done: \(error.localizedDescription)"
            return false
        }
    }

    public func execute(_ command: WorkbenchCommand) {
        let items = selectedDisplayItems()
        switch command {
        case .copy: _ = copy(items: items)
        case .copyAsList: _ = copyAsList()
        case .markDone: if items.allSatisfy({ $0.state == .active }) { completeSelected() }
        case .expand: if let item = items.first, items.count == 1 { toggleExpanded(item) }
        case .edit: if let item = items.first, items.count == 1 { beginInlineEdit(item) }
        case .editInNewWindow: if let item = items.first, items.count == 1 { onOpenEditor?(item) }
        case .mergeNotes: mergeSelected()
        case .restore: if let item = items.first, items.count == 1 { restore(item) }
        }
    }

    public func completeSelected() {
        let items = selectedDisplayItems(); guard !items.isEmpty else { return }
        perform {
            let ids = items.map(\.id)
            try engine.complete(ids)
            recentlyCompletedIDs.formUnion(ids)
            completionEchoExpiryScheduler { [weak self] in
                guard let self else { return }
                self.recentlyCompletedIDs.subtract(ids)
                self.pruneSelection()
            }
        }
    }
    public func moveSelected(to sectionID: UUID) {
        let items = selectedDisplayItems(); guard !items.isEmpty else { return }
        perform { try engine.move(items.map(\.id), to: sectionID) }
    }
    public func mergeSelected() {
        let items = selectedDisplayItems(); guard items.count >= 2 else { return }
        perform { let merged = try engine.merge(items.map(\.id)); selectedIDs = [merged.id]; selectionAnchor = merged.id }
    }
    public func edit(_ item: LibraryItem, text: String) { perform { try engine.edit(item.id, text: text) } }
    public func done(_ item: LibraryItem) { select(item); completeSelected() }
    public func archive(_ item: LibraryItem) { perform { try engine.archive(item.id) } }
    public func restore(_ item: LibraryItem) {
        perform {
            try engine.restore(item.id)
            recentlyCompletedIDs.remove(item.id)
        }
    }
    public func export(to destination: URL) { perform { try engine.export(to: destination) } }
    public func createSection(name: String) { perform { let section = try engine.createSection(name: name); captureSectionID = section.id } }
    public func requestNewSection() { newSectionName = ""; isCreatingSection = true }
    public func createRequestedSection() {
        let name = newSectionName
        createSection(name: name)
        if errorMessage == nil { newSectionName = ""; isCreatingSection = false }
    }
    public func show(error: Error) { errorMessage = error.localizedDescription }
    public func dismissError() { errorMessage = nil }
    public func dismissRecovery() { recoveryMessage = nil }
    public func dismissNotice() { errorMessage = nil; recoveryMessage = nil; successMessage = nil }

    @discardableResult public func handleShortcut(_ shortcut: RailShortcut) -> Bool {
        let items = selectedDisplayItems()
        guard !items.isEmpty else { return false }
        switch shortcut {
        case .copy: execute(.copy)
        case .copyAsList: execute(.copyAsList)
        case .markDone: execute(.markDone)
        case .edit:
            guard items.count == 1 else { return false }
            execute(.edit)
        case .editInNewWindow: execute(.editInNewWindow)
        case .mergeNotes: execute(.mergeNotes)
        }
        return true
    }

    private func copy(items: [LibraryItem]) -> Bool {
        guard !items.isEmpty else { errorMessage = "Select a note first."; return false }
        guard clipboard.writePlainText(items.map(\.text).joined(separator: "\n\n")) else { errorMessage = "Embercue could not write to the clipboard."; return false }
        errorMessage = nil; return true
    }
    private func showSuccess(_ message: String) {
        successNoticeGeneration &+= 1
        let generation = successNoticeGeneration
        successMessage = message
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard let self, self.successNoticeGeneration == generation else { return }
            self.successMessage = nil
        }
    }
    private func importPendingAttachments() throws -> [LibraryAttachment] {
        guard !pendingAttachments.isEmpty else { return [] }
        guard let attachmentStore else { throw LibraryRepositoryError.invalidDocument("attachments are unavailable in this library") }
        var imported: [LibraryAttachment] = []
        do {
            for pending in pendingAttachments { imported.append(try attachmentStore.importFile(at: pending.sourceURL)) }
            return imported
        } catch {
            imported.forEach { attachmentStore.remove($0) }
            throw error
        }
    }
    private func matchesSearch(_ item: LibraryItem) -> Bool { !isSearching || item.text.localizedCaseInsensitiveContains(search.trimmingCharacters(in: .whitespacesAndNewlines)) }
    private func itemOrder(_ lhs: LibraryItem, _ rhs: LibraryItem) -> Bool {
        lhs.createdAt == rhs.createdAt ? lhs.id.uuidString < rhs.id.uuidString : lhs.createdAt < rhs.createdAt
    }
    private func sectionItemOrder(_ lhs: LibraryItem, _ rhs: LibraryItem) -> Bool {
        lhs.sortOrder == rhs.sortOrder ? lhs.id.uuidString < rhs.id.uuidString : lhs.sortOrder < rhs.sortOrder
    }
    /// A section command is deliberately narrow: only a single leading `# `
    /// changes composer semantics. Other Markdown remains ordinary note text.
    private func composerSectionName(in draft: String) -> String? {
        guard draft.hasPrefix("# "), !draft.contains("\n") else { return nil }
        let name = String(draft.dropFirst(2))
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return name
    }
    private func pruneSelection() {
        let visible = Set(visibleItems.map(\.id)); selectedIDs.formIntersection(visible)
        if let selectionAnchor, !visible.contains(selectionAnchor) { self.selectionAnchor = nil }
        if selectedIDs.isEmpty { clearCompletionEcho() }
    }
    private func perform(_ operation: () throws -> Void) {
        do { try operation(); document = engine.document; pruneSelection(); errorMessage = nil; onDocumentChange?() }
        catch { errorMessage = error.localizedDescription }
    }
}
