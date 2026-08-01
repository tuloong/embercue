import Foundation

public enum LibrarySectionID {
    // Fixed IDs make schema-v1 migration deterministic and auditable.
    public static let inbox = UUID(uuidString: "9B4EF8E0-917A-4F7C-95A1-4ED5EB0B4D01")!
    public static let keeps = UUID(uuidString: "A5C8E4F6-26B4-4A3C-90B7-588B45542B02")!
}

public struct LibrarySection: Codable, Equatable, Identifiable, Sendable {
    public static let maximumUTF8Bytes = 120

    public let id: UUID
    public var name: String
    public var sortOrder: Int64

    public init(id: UUID = UUID(), name: String, sortOrder: Int64) throws {
        try Self.validate(name: name)
        guard sortOrder >= 0 else { throw LibraryRepositoryError.invalidDocument("section sort order must be nonnegative") }
        self.id = id
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.sortOrder = sortOrder
    }

    public static func validate(name: String) throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw LibraryRepositoryError.invalidDocument("section names cannot be empty") }
        guard trimmed.lengthOfBytes(using: .utf8) <= maximumUTF8Bytes else {
            throw LibraryRepositoryError.invalidDocument("section names must be \(maximumUTF8Bytes) bytes or smaller")
        }
    }
}
