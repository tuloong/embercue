import Foundation

public struct LibraryDocument: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 3
    public var schemaVersion: Int
    public var revision: Int
    public var sections: [LibrarySection]
    public var items: [LibraryItem]

    public init(schemaVersion: Int = Self.currentSchemaVersion, revision: Int = 0, sections: [LibrarySection]? = nil, items: [LibraryItem] = []) {
        self.schemaVersion = schemaVersion
        self.revision = revision
        self.sections = sections ?? Self.builtInSections
        self.items = items
    }

    public static var builtInSections: [LibrarySection] {
        [
            try! LibrarySection(id: LibrarySectionID.inbox, name: "INBOX", sortOrder: 0),
            try! LibrarySection(id: LibrarySectionID.keeps, name: "KEEPS", sortOrder: 1)
        ]
    }

    public func items(in sectionID: UUID, states: Set<LibraryItemState> = [.active], matching search: String = "") -> [LibraryItem] {
        let needle = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return items.filter { item in
            item.sectionID == sectionID && states.contains(item.state) &&
                (needle.isEmpty || item.text.localizedCaseInsensitiveContains(needle))
        }.sorted { lhs, rhs in
            lhs.sortOrder == rhs.sortOrder ? lhs.id.uuidString < rhs.id.uuidString : lhs.sortOrder < rhs.sortOrder
        }
    }

    public func items(kind: LibraryItemKind? = nil, states: Set<LibraryItemState>, matching search: String = "") -> [LibraryItem] {
        let needle = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return items.filter { item in
            states.contains(item.state) && (kind == nil || item.kind == kind) &&
                (needle.isEmpty || item.text.localizedCaseInsensitiveContains(needle))
        }.sorted { lhs, rhs in
            lhs.createdAt == rhs.createdAt ? lhs.id.uuidString < rhs.id.uuidString : lhs.createdAt < rhs.createdAt
        }
    }

    public func validate() throws {
        guard schemaVersion == Self.currentSchemaVersion else { throw LibraryRepositoryError.invalidSchema(schemaVersion) }
        guard revision >= 0 && revision < Int.max else { throw LibraryRepositoryError.revisionOverflow }
        var sectionIDs = Set<UUID>()
        var sectionOrders = Set<Int64>()
        var normalizedNames = Set<String>()
        for section in sections {
            try LibrarySection.validate(name: section.name)
            guard section.sortOrder >= 0, sectionIDs.insert(section.id).inserted, sectionOrders.insert(section.sortOrder).inserted else {
                throw LibraryRepositoryError.invalidDocument("section identifiers and orders must be unique")
            }
            guard normalizedNames.insert(section.name.trimmingCharacters(in: .whitespacesAndNewlines).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)).inserted else {
                throw LibraryRepositoryError.invalidDocument("section names must be unique")
            }
        }
        var identifiers = Set<UUID>()
        var itemOrders = Set<String>()
        for item in items {
            guard identifiers.insert(item.id).inserted else { throw LibraryRepositoryError.invalidDocument("item identifiers must be unique") }
            guard sectionIDs.contains(item.sectionID) else { throw LibraryRepositoryError.invalidDocument("item section does not exist") }
            guard item.sortOrder >= 0, itemOrders.insert("\(item.sectionID.uuidString):\(item.sortOrder)").inserted else {
                throw LibraryRepositoryError.invalidDocument("item orders must be unique within a section")
            }
            try LibraryItem.validate(text: item.text, attachments: item.attachments)
            guard item.updatedAt >= item.createdAt else { throw LibraryRepositoryError.invalidDocument("item timestamps are out of order") }
        }
    }

    public init(from decoder: Decoder) throws { self = try LibrarySchemaCodec.decode(from: decoder) }
    public func encode(to encoder: Encoder) throws { try LibrarySchemaCodec.encode(self, to: encoder) }
}

public enum RecoveryNotice: Equatable, Sendable {
    case recoveredFromBackup(quarantinedFile: String)
    case restoredMissingPrimaryFromBackup
    case startedEmptyWithQuarantinedBackup(quarantinedBackupFile: String)
    case startedEmptyWithQuarantinedPrimaryAndBackup(quarantinedPrimaryFile: String, quarantinedBackupFile: String)
    case startedEmpty(quarantinedFile: String)

    public var message: String {
        switch self {
        case let .recoveredFromBackup(file): "Recovered your last known good library; the unreadable file was preserved as \(file)."
        case .restoredMissingPrimaryFromBackup: "Restored your library from the last known good backup after an interrupted recovery."
        case let .startedEmptyWithQuarantinedBackup(backup): "The last known good backup could not be read. Your live library is empty; the backup was preserved as \(backup)."
        case let .startedEmptyWithQuarantinedPrimaryAndBackup(primary, backup): "The unreadable library was preserved as \(primary), and the unreadable last known good backup was preserved as \(backup). A new empty library is ready."
        case let .startedEmpty(file): "The unreadable library was preserved as \(file). A new empty library is ready."
        }
    }
}

public struct LibraryLoadResult: Sendable {
    public let document: LibraryDocument
    public let recoveryNotice: RecoveryNotice?

    public init(document: LibraryDocument, recoveryNotice: RecoveryNotice? = nil) {
        self.document = document
        self.recoveryNotice = recoveryNotice
    }
}
