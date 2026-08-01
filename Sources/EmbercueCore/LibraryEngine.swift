import Foundation

@MainActor
public final class LibraryEngine {
    private let repository: any LibraryRepository
    private var storedDocument: LibraryDocument
    public private(set) var recoveryNotice: RecoveryNotice?

    public init(repository: any LibraryRepository) throws {
        self.repository = repository
        let result = try repository.load()
        storedDocument = result.document
        recoveryNotice = result.recoveryNotice
    }

    public var document: LibraryDocument { storedDocument }

    @discardableResult
    public func add(kind: LibraryItemKind, text: String, attachments: [LibraryAttachment] = [], to sectionID: UUID? = nil, now: Date = Date()) throws -> LibraryItem {
        let destination = sectionID ?? (kind == .prompt ? LibrarySectionID.inbox : LibrarySectionID.keeps)
        guard storedDocument.sections.contains(where: { $0.id == destination }) else { throw LibraryRepositoryError.sectionNotFound }
        let nextOrder = try nextItemOrder(in: destination, document: storedDocument)
        let item = try LibraryItem(kind: kind, text: text, attachments: attachments, createdAt: now, updatedAt: now, sectionID: destination, sortOrder: nextOrder)
        try mutate { $0.items.append(item) }
        return item
    }

    public func edit(_ id: UUID, text: String, now: Date = Date()) throws {
        try mutate { document in
            guard let index = document.items.firstIndex(where: { $0.id == id }) else { throw LibraryRepositoryError.itemNotFound }
            try LibraryItem.validate(text: text, attachments: document.items[index].attachments)
            document.items[index].text = text
            document.items[index].updatedAt = now
        }
    }

    public func complete(_ id: UUID, now: Date = Date()) throws { try complete([id], now: now) }
    public func complete(_ idsInDisplayOrder: [UUID], now: Date = Date()) throws {
        _ = try preflight(idsInDisplayOrder, in: storedDocument, requireActive: true)
        try mutate { document in
            for id in idsInDisplayOrder {
                guard let index = document.items.firstIndex(where: { $0.id == id }) else { throw LibraryRepositoryError.itemNotFound }
                document.items[index].state = .completed
                document.items[index].updatedAt = now
            }
        }
    }

    public func archive(_ id: UUID, now: Date = Date()) throws { try transition(id, to: .archived, now: now) }
    public func restore(_ id: UUID, now: Date = Date()) throws { try transition(id, to: .active, now: now) }

    public func move(_ idsInDisplayOrder: [UUID], to sectionID: UUID, now: Date = Date()) throws {
        guard storedDocument.sections.contains(where: { $0.id == sectionID }) else { throw LibraryRepositoryError.sectionNotFound }
        _ = try preflight(idsInDisplayOrder, in: storedDocument, requireActive: false)
        var nextOrder = try nextItemOrder(in: sectionID, document: storedDocument)
        try mutate { document in
            for id in idsInDisplayOrder {
                guard let index = document.items.firstIndex(where: { $0.id == id }) else { throw LibraryRepositoryError.itemNotFound }
                document.items[index].sectionID = sectionID
                document.items[index].sortOrder = nextOrder
                document.items[index].updatedAt = now
                guard nextOrder < Int64.max else { throw LibraryRepositoryError.sortOrderOverflow }
                nextOrder += 1
            }
        }
    }

    @discardableResult
    public func merge(_ idsInDisplayOrder: [UUID], now: Date = Date()) throws -> LibraryItem {
        guard idsInDisplayOrder.count >= 2 else { throw LibraryRepositoryError.invalidSelection("Select at least two notes to merge.") }
        let selected = try preflight(idsInDisplayOrder, in: storedDocument, requireActive: true)
        guard Set(selected.map(\.sectionID)).count == 1, let sectionID = selected.first?.sectionID else {
            throw LibraryRepositoryError.invalidSelection("Notes must be in the same section to merge.")
        }
        let text = selected.map(\.text).joined(separator: "\n\n")
        try LibraryItem.validate(text: text)
        let nextOrder = try nextItemOrder(in: sectionID, document: storedDocument)
        let merged = try LibraryItem(kind: selected.first!.kind, text: text, createdAt: now, updatedAt: now, sectionID: sectionID, sortOrder: nextOrder)
        try mutate { document in
            for id in idsInDisplayOrder {
                guard let index = document.items.firstIndex(where: { $0.id == id }) else { throw LibraryRepositoryError.itemNotFound }
                document.items[index].state = .archived
                document.items[index].updatedAt = now
            }
            document.items.append(merged)
        }
        return merged
    }

    @discardableResult
    public func createSection(name: String) throws -> LibrarySection {
        try LibrarySection.validate(name: name)
        let normalized = normalizedSectionName(name)
        guard !storedDocument.sections.contains(where: { normalizedSectionName($0.name) == normalized }) else { throw LibraryRepositoryError.duplicateSectionName }
        let order = try nextSectionOrder(in: storedDocument)
        let section = try LibrarySection(name: name, sortOrder: order)
        try mutate { $0.sections.append(section) }
        return section
    }

    public func renameSection(_ id: UUID, name: String) throws {
        try LibrarySection.validate(name: name)
        let normalized = normalizedSectionName(name)
        guard !storedDocument.sections.contains(where: { $0.id != id && normalizedSectionName($0.name) == normalized }) else { throw LibraryRepositoryError.duplicateSectionName }
        try mutate { document in
            guard let index = document.sections.firstIndex(where: { $0.id == id }) else { throw LibraryRepositoryError.sectionNotFound }
            document.sections[index].name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    public func removeEmptySection(_ id: UUID) throws {
        guard !storedDocument.items.contains(where: { $0.sectionID == id }) else { throw LibraryRepositoryError.nonEmptySection }
        try mutate { document in
            guard let index = document.sections.firstIndex(where: { $0.id == id }) else { throw LibraryRepositoryError.sectionNotFound }
            document.sections.remove(at: index)
        }
    }

    public func export(to destination: URL) throws { try repository.export(storedDocument, to: destination) }

    private func transition(_ id: UUID, to state: LibraryItemState, now: Date) throws {
        try mutate { document in
            guard let index = document.items.firstIndex(where: { $0.id == id }) else { throw LibraryRepositoryError.itemNotFound }
            document.items[index].state = state
            document.items[index].updatedAt = now
        }
    }

    private func preflight(_ ids: [UUID], in document: LibraryDocument, requireActive: Bool) throws -> [LibraryItem] {
        guard !ids.isEmpty, Set(ids).count == ids.count else { throw LibraryRepositoryError.invalidSelection("Selection must contain unique notes.") }
        let selected = try ids.map { id -> LibraryItem in
            guard let item = document.items.first(where: { $0.id == id }) else { throw LibraryRepositoryError.itemNotFound }
            guard !requireActive || item.state == .active else { throw LibraryRepositoryError.invalidSelection("Only active notes can be completed or merged.") }
            return item
        }
        return selected
    }

    private func nextItemOrder(in sectionID: UUID, document: LibraryDocument) throws -> Int64 {
        guard let maximum = document.items.filter({ $0.sectionID == sectionID }).map(\.sortOrder).max() else { return 0 }
        guard maximum < Int64.max else { throw LibraryRepositoryError.sortOrderOverflow }
        return maximum + 1
    }

    private func nextSectionOrder(in document: LibraryDocument) throws -> Int64 {
        guard let maximum = document.sections.map(\.sortOrder).max() else { return 0 }
        guard maximum < Int64.max else { throw LibraryRepositoryError.sortOrderOverflow }
        return maximum + 1
    }

    private func normalizedSectionName(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }

    private func mutate(_ change: (inout LibraryDocument) throws -> Void) throws {
        var candidate = storedDocument
        try change(&candidate)
        guard storedDocument.revision < Int.max else { throw LibraryRepositoryError.revisionOverflow }
        candidate.revision += 1
        try candidate.validate()
        try repository.save(candidate, expectedRevision: storedDocument.revision)
        storedDocument = candidate
    }
}
