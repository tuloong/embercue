import Foundation

public enum LibrarySchemaCodec {
    struct SchemaHeader: Decodable { let schemaVersion: Int }
    private struct V1Document: Decodable {
        let schemaVersion: Int
        let revision: Int
        let items: [V1Item]
    }
    private struct V1Item: Decodable {
        let id: UUID
        let kind: LibraryItemKind
        let state: LibraryItemState
        let text: String
        let createdAt: Date
        let updatedAt: Date
    }
    private struct V2Document: Codable {
        let schemaVersion: Int
        let revision: Int
        let sections: [LibrarySection]
        let items: [LibraryItem]
    }
    private struct V2Item: Decodable {
        let id: UUID; let kind: LibraryItemKind; let state: LibraryItemState; let text: String
        let createdAt: Date; let updatedAt: Date; let sectionID: UUID; let sortOrder: Int64
    }
    private struct LegacyV2Document: Decodable { let schemaVersion: Int; let revision: Int; let sections: [LibrarySection]; let items: [V2Item] }

    public static func decode(data: Data, decoder: JSONDecoder) throws -> (document: LibraryDocument, sourceSchemaVersion: Int) {
        let header = try decoder.decode(SchemaHeader.self, from: data)
        switch header.schemaVersion {
        case 1:
            let legacy = try decoder.decode(V1Document.self, from: data)
            guard legacy.revision >= 0 && legacy.revision < Int.max else { throw LibraryRepositoryError.revisionOverflow }
            let grouped = Dictionary(grouping: legacy.items, by: \.kind)
            var mapped: [LibraryItem] = []
            for kind in LibraryItemKind.allCases {
                let sectionID = kind == .prompt ? LibrarySectionID.inbox : LibrarySectionID.keeps
                let ordered = (grouped[kind] ?? []).sorted { lhs, rhs in
                    lhs.createdAt == rhs.createdAt ? lhs.id.uuidString < rhs.id.uuidString : lhs.createdAt < rhs.createdAt
                }
                for (index, item) in ordered.enumerated() {
                    mapped.append(try LibraryItem(id: item.id, kind: item.kind, state: item.state, text: item.text, createdAt: item.createdAt, updatedAt: item.updatedAt, sectionID: sectionID, sortOrder: Int64(index)))
                }
            }
            let document = LibraryDocument(revision: legacy.revision, sections: LibraryDocument.builtInSections, items: mapped)
            try document.validate()
            return (document, 1)
        case 2:
            let legacy = try decoder.decode(LegacyV2Document.self, from: data)
            let items = try legacy.items.map { try LibraryItem(id: $0.id, kind: $0.kind, state: $0.state, text: $0.text, createdAt: $0.createdAt, updatedAt: $0.updatedAt, sectionID: $0.sectionID, sortOrder: $0.sortOrder) }
            let document = LibraryDocument(schemaVersion: LibraryDocument.currentSchemaVersion, revision: legacy.revision, sections: legacy.sections, items: items)
            try document.validate()
            return (document, 2)
        case LibraryDocument.currentSchemaVersion:
            let current = try decoder.decode(V2Document.self, from: data)
            let document = LibraryDocument(schemaVersion: current.schemaVersion, revision: current.revision, sections: current.sections, items: current.items)
            try document.validate()
            return (document, LibraryDocument.currentSchemaVersion)
        default:
            throw LibraryRepositoryError.invalidSchema(header.schemaVersion)
        }
    }

    static func decode(from decoder: Decoder) throws -> LibraryDocument {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let version = try container.decode(Int.self, forKey: .schemaVersion)
        guard version == LibraryDocument.currentSchemaVersion else { throw LibraryRepositoryError.invalidSchema(version) }
        let document = LibraryDocument(schemaVersion: version, revision: try container.decode(Int.self, forKey: .revision), sections: try container.decode([LibrarySection].self, forKey: .sections), items: try container.decode([LibraryItem].self, forKey: .items))
        try document.validate()
        return document
    }

    static func encode(_ document: LibraryDocument, to encoder: Encoder) throws {
        try document.validate()
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(document.schemaVersion, forKey: .schemaVersion)
        try container.encode(document.revision, forKey: .revision)
        try container.encode(document.sections, forKey: .sections)
        try container.encode(document.items, forKey: .items)
    }

    private enum CodingKeys: String, CodingKey { case schemaVersion, revision, sections, items }
}
