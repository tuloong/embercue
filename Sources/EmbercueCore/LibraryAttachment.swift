import Foundation

public struct LibraryAttachment: Codable, Equatable, Identifiable, Sendable {
    public static let maximumPerItem = 8
    public static let maximumBytes = 20 * 1024 * 1024

    public let id: UUID
    public let storagePath: String
    public let filename: String
    public let byteCount: Int
    public let contentTypeIdentifier: String?

    public init(id: UUID = UUID(), storagePath: String, filename: String, byteCount: Int, contentTypeIdentifier: String? = nil) throws {
        guard byteCount >= 0 && byteCount <= Self.maximumBytes else { throw LibraryRepositoryError.dataTooLarge(limit: Self.maximumBytes) }
        guard !filename.isEmpty, filename.lengthOfBytes(using: .utf8) <= 255 else { throw LibraryRepositoryError.invalidDocument("attachment filename is invalid") }
        let expectedPath = "attachments/\(id.uuidString)"
        guard storagePath == expectedPath else { throw LibraryRepositoryError.invalidDocument("attachment path is not managed storage") }
        self.id = id
        self.storagePath = storagePath
        self.filename = filename
        self.byteCount = byteCount
        self.contentTypeIdentifier = contentTypeIdentifier
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            id: values.decode(UUID.self, forKey: .id),
            storagePath: values.decode(String.self, forKey: .storagePath),
            filename: values.decode(String.self, forKey: .filename),
            byteCount: values.decode(Int.self, forKey: .byteCount),
            contentTypeIdentifier: values.decodeIfPresent(String.self, forKey: .contentTypeIdentifier)
        )
    }

    public func validate() throws {
        _ = try Self(
            id: id,
            storagePath: storagePath,
            filename: filename,
            byteCount: byteCount,
            contentTypeIdentifier: contentTypeIdentifier
        )
    }
}
