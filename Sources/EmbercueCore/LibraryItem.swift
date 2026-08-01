import Foundation

public enum LibraryItemKind: String, Codable, CaseIterable, Sendable {
    case prompt
    case snippet
}

public enum LibraryItemState: String, Codable, CaseIterable, Sendable {
    case active
    case completed
    case archived
}

public enum LibraryValidationError: LocalizedError, Equatable, Sendable {
    case emptyText
    case textTooLarge(limit: Int)

    public var errorDescription: String? {
        switch self {
        case .emptyText: "Enter some text first."
        case let .textTooLarge(limit): "Items must be \(limit / 1024) KiB or smaller."
        }
    }
}

public struct LibraryItem: Codable, Equatable, Identifiable, Sendable {
    public static let maximumUTF8Bytes = 100 * 1024

    public let id: UUID
    public var kind: LibraryItemKind
    public var state: LibraryItemState
    public var text: String
    public var attachments: [LibraryAttachment]
    public let createdAt: Date
    public var updatedAt: Date
    public var sectionID: UUID
    public var sortOrder: Int64

    public init(id: UUID = UUID(), kind: LibraryItemKind, state: LibraryItemState = .active, text: String, attachments: [LibraryAttachment] = [], createdAt: Date = Date(), updatedAt: Date = Date(), sectionID: UUID = LibrarySectionID.inbox, sortOrder: Int64 = 0) throws {
        try Self.validate(text: text, attachments: attachments)
        guard sortOrder >= 0 else { throw LibraryRepositoryError.invalidDocument("item sort order must be nonnegative") }
        self.id = id
        self.kind = kind
        self.state = state
        self.text = text
        self.attachments = attachments
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.sectionID = sectionID
        self.sortOrder = sortOrder
    }

    public static func validate(text: String) throws {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LibraryValidationError.emptyText
        }
        guard text.lengthOfBytes(using: .utf8) <= maximumUTF8Bytes else {
            throw LibraryValidationError.textTooLarge(limit: maximumUTF8Bytes)
        }
    }

    public static func validate(text: String, attachments: [LibraryAttachment]) throws {
        guard attachments.count <= LibraryAttachment.maximumPerItem else { throw LibraryRepositoryError.invalidDocument("too many attachments") }
        guard Set(attachments.map(\.id)).count == attachments.count else { throw LibraryRepositoryError.invalidDocument("attachment identifiers must be unique") }
        try attachments.forEach { try $0.validate() }
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard !attachments.isEmpty else { throw LibraryValidationError.emptyText }
        } else {
            try validate(text: text)
        }
    }
}
