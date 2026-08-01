import Darwin
import Foundation
import UniformTypeIdentifiers

public protocol AttachmentStoring: AnyObject {
    func validateSource(at url: URL) throws
    func importFile(at url: URL) throws -> LibraryAttachment
    func url(for attachment: LibraryAttachment) -> URL?
    func remove(_ attachment: LibraryAttachment)
}

public final class AttachmentStore: AttachmentStoring {
    public let rootURL: URL
    private let fileManager: FileManager

    public init(rootURL: URL, fileManager: FileManager = .default) throws {
        self.rootURL = rootURL.appendingPathComponent("attachments", isDirectory: true)
        self.fileManager = fileManager
        try ensureRoot()
    }

    public func validateSource(at url: URL) throws { _ = try readSource(at: url) }

    public func importFile(at url: URL) throws -> LibraryAttachment {
        let source = try readSource(at: url)
        let id = UUID()
        let destination = rootURL.appendingPathComponent(id.uuidString)
        let descriptor = open(destination.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw LibraryRepositoryError.saveFailed(String(cString: strerror(errno))) }
        do {
            defer { _ = close(descriptor) }
            try source.withUnsafeBytes { raw in
                guard let base = raw.baseAddress else { return }
                var offset = 0
                while offset < source.count {
                    let result = Darwin.write(descriptor, base.advanced(by: offset), source.count - offset)
                    if result < 0 { if errno == EINTR { continue }; throw LibraryRepositoryError.saveFailed(String(cString: strerror(errno))) }
                    guard result > 0 else { throw LibraryRepositoryError.saveFailed("short attachment write") }
                    offset += result
                }
            }
            guard fsync(descriptor) == 0 else { throw LibraryRepositoryError.saveFailed(String(cString: strerror(errno))) }
            let type = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType?.identifier
            return try LibraryAttachment(id: id, storagePath: "attachments/\(id.uuidString)", filename: url.lastPathComponent, byteCount: source.count, contentTypeIdentifier: type)
        } catch {
            _ = unlink(destination.path)
            throw error
        }
    }

    public func url(for attachment: LibraryAttachment) -> URL? {
        guard (try? LibraryAttachment(id: attachment.id, storagePath: attachment.storagePath, filename: attachment.filename, byteCount: attachment.byteCount, contentTypeIdentifier: attachment.contentTypeIdentifier)) != nil else { return nil }
        let candidate = rootURL.deletingLastPathComponent().appendingPathComponent(attachment.storagePath).standardizedFileURL
        guard candidate.deletingLastPathComponent() == rootURL else { return nil }
        var info = stat()
        guard lstat(candidate.path, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG else { return nil }
        return candidate
    }

    public func remove(_ attachment: LibraryAttachment) {
        guard let url = url(for: attachment) else { return }
        _ = unlink(url.path)
    }

    private func ensureRoot() throws {
        let parent = rootURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: parent, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        var info = stat()
        if lstat(rootURL.path, &info) == 0 {
            guard (info.st_mode & S_IFMT) == S_IFDIR else { throw LibraryRepositoryError.invalidStorageRoot("attachments path is not a directory") }
        } else if errno == ENOENT {
            try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        } else { throw LibraryRepositoryError.invalidStorageRoot(String(cString: strerror(errno))) }
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: rootURL.path)
    }

    private func readSource(at url: URL) throws -> Data {
        let descriptor = open(url.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { throw LibraryRepositoryError.invalidDocument("attachment could not be opened") }
        defer { _ = close(descriptor) }
        var info = stat()
        guard fstat(descriptor, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG else { throw LibraryRepositoryError.invalidDocument("attachments must be regular files") }
        guard info.st_size >= 0 && info.st_size <= off_t(LibraryAttachment.maximumBytes) else { throw LibraryRepositoryError.dataTooLarge(limit: LibraryAttachment.maximumBytes) }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: false)
        let data = try handle.readToEnd() ?? Data()
        guard data.count == Int(info.st_size) else { throw LibraryRepositoryError.invalidDocument("attachment changed while reading") }
        return data
    }
}
