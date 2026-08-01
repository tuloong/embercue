import Darwin
import Foundation

public final class JSONLibraryRepository: LibraryRepository {
    public static let maximumDocumentBytes = 64 * 1024 * 1024
    public static let dataDirectoryEnvironmentVariable = "EMBERCUE_DATA_DIRECTORY"

    public let rootURL: URL
    public let documentURL: URL
    public let backupURL: URL
    public let preSchema2BackupURL: URL
    public let preSchema3BackupURL: URL
    private let lockURL: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public static func defaultRootURL(fileManager: FileManager = .default, environment: [String: String] = ProcessInfo.processInfo.environment) throws -> URL {
        if let value = environment[dataDirectoryEnvironmentVariable] {
            guard !value.isEmpty else { throw LibraryRepositoryError.invalidStorageRoot("\(dataDirectoryEnvironmentVariable) is empty") }
            guard value.hasPrefix("/") else { throw LibraryRepositoryError.invalidStorageRoot("\(dataDirectoryEnvironmentVariable) must be an absolute path") }
            return URL(fileURLWithPath: value, isDirectory: true).standardizedFileURL
        }
        return try fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("Embercue", isDirectory: true)
    }

    public init(rootURL: URL? = nil, fileManager: FileManager = .default, environment: [String: String] = ProcessInfo.processInfo.environment) throws {
        self.fileManager = fileManager
        self.rootURL = try rootURL ?? Self.defaultRootURL(fileManager: fileManager, environment: environment)
        documentURL = self.rootURL.appendingPathComponent("library.json")
        backupURL = self.rootURL.appendingPathComponent("library.last-known-good.json")
        preSchema2BackupURL = self.rootURL.appendingPathComponent("library.pre-schema-2.json")
        preSchema3BackupURL = self.rootURL.appendingPathComponent("library.pre-schema-3.json")
        lockURL = self.rootURL.appendingPathComponent(".library.lock")
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .secondsSince1970
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        try ensureRootDirectory()
    }

    public func load() throws -> LibraryLoadResult {
        try withExclusiveLock {
            guard try pathExists(documentURL) else {
                if try pathExists(backupURL) {
                    if let backup = try? decodeDocument(at: backupURL) {
                        try writeData(backup.rawData, to: documentURL)
                        return LibraryLoadResult(document: backup.document, recoveryNotice: .restoredMissingPrimaryFromBackup)
                    }
                    let quarantinedBackup = try quarantineFile(at: backupURL, namePrefix: "library.last-known-good")
                    return LibraryLoadResult(document: LibraryDocument(), recoveryNotice: .startedEmptyWithQuarantinedBackup(quarantinedBackupFile: quarantinedBackup.lastPathComponent))
                }
                return LibraryLoadResult(document: LibraryDocument())
            }
            do {
                return LibraryLoadResult(document: try decodeDocument(at: documentURL).document)
            } catch {
                let quarantinedPrimary = try quarantineFile(at: documentURL, namePrefix: "library")
                if let backup = try? decodeDocument(at: backupURL) {
                    try writeData(backup.rawData, to: documentURL)
                    return LibraryLoadResult(document: backup.document, recoveryNotice: .recoveredFromBackup(quarantinedFile: quarantinedPrimary.lastPathComponent))
                }
                if try pathExists(backupURL) {
                    let quarantinedBackup = try quarantineFile(at: backupURL, namePrefix: "library.last-known-good")
                    let empty = LibraryDocument()
                    try writeDocument(empty, to: documentURL)
                    return LibraryLoadResult(document: empty, recoveryNotice: .startedEmptyWithQuarantinedPrimaryAndBackup(quarantinedPrimaryFile: quarantinedPrimary.lastPathComponent, quarantinedBackupFile: quarantinedBackup.lastPathComponent))
                }
                let empty = LibraryDocument()
                try writeDocument(empty, to: documentURL)
                return LibraryLoadResult(document: empty, recoveryNotice: .startedEmpty(quarantinedFile: quarantinedPrimary.lastPathComponent))
            }
        }
    }

    public func save(_ document: LibraryDocument, expectedRevision: Int) throws {
        try withExclusiveLock {
            try document.validate()
            guard expectedRevision >= 0 && expectedRevision < Int.max else { throw LibraryRepositoryError.revisionOverflow }
            guard document.revision == expectedRevision + 1 else { throw LibraryRepositoryError.saveFailed("invalid revision transition") }
            // Encode before touching any live/migration/backup file.  This is
            // particularly important for the first v1 -> v2 write: a rejected
            // candidate must not leave a migration snapshot behind.
            let candidateData = try encodedData(for: document)
            let actual = try currentRevision()
            guard actual == expectedRevision else { throw LibraryRepositoryError.revisionConflict(expected: expectedRevision, actual: actual) }
            guard try pathExists(documentURL) else {
                try writeData(candidateData, to: documentURL)
                return
            }

            let currentData = try readData(at: documentURL)
            let current = try decodeDocument(data: currentData)
            let priorBackupData = try pathExists(backupURL) ? readData(at: backupURL) : nil
            let hadPreSchema2Backup = try pathExists(preSchema2BackupURL)
            let hadPreSchema3Backup = try pathExists(preSchema3BackupURL)
            if hadPreSchema2Backup { try rejectSymlinkDestination(preSchema2BackupURL) }
            if hadPreSchema3Backup { try rejectSymlinkDestination(preSchema3BackupURL) }

            var createdPreSchema2Backup = false
            var createdPreSchema3Backup = false
            var replacedBackup = false
            do {
                if current.sourceSchemaVersion == 1 && !hadPreSchema2Backup {
                    try writeData(currentData, to: preSchema2BackupURL)
                    createdPreSchema2Backup = true
                }
                if current.sourceSchemaVersion < LibraryDocument.currentSchemaVersion && !hadPreSchema3Backup {
                    try writeData(currentData, to: preSchema3BackupURL)
                    createdPreSchema3Backup = true
                }
                try writeData(currentData, to: backupURL)
                replacedBackup = true
                try writeData(candidateData, to: documentURL)
            } catch {
                let rollbackFailures = rollbackFailedSave(
                    createdPreSchema2Backup: createdPreSchema2Backup,
                    createdPreSchema3Backup: createdPreSchema3Backup,
                    replacedBackup: replacedBackup,
                    priorBackupData: priorBackupData
                )
                if rollbackFailures.isEmpty { throw error }
                throw LibraryRepositoryError.saveFailed("\(error.localizedDescription); rollback failed: \(rollbackFailures.joined(separator: "; "))")
            }
        }
    }

    public func export(_ document: LibraryDocument, to destination: URL) throws {
        do {
            try withExclusiveLock {
                try document.validate()
                try validateExportDestination(destination)
                try writeData(try encodedData(for: document), to: destination)
            }
        } catch let error as LibraryRepositoryError {
            throw error
        } catch {
            throw LibraryRepositoryError.exportFailed(error.localizedDescription)
        }
    }

    private func withExclusiveLock<T>(_ body: () throws -> T) throws -> T {
        try ensureRootDirectory()
        let descriptor = open(lockURL.path, O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw LibraryRepositoryError.saveFailed(systemError()) }
        defer { _ = flock(descriptor, LOCK_UN); _ = close(descriptor) }
        try requireRegularFile(descriptor)
        guard fchmod(descriptor, S_IRUSR | S_IWUSR) == 0 else { throw LibraryRepositoryError.saveFailed(systemError()) }
        guard flock(descriptor, LOCK_EX) == 0 else { throw LibraryRepositoryError.saveFailed(systemError()) }
        return try body()
    }

    private func ensureRootDirectory() throws {
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: rootURL.path, isDirectory: &isDirectory) {
            guard isDirectory.boolValue else { throw LibraryRepositoryError.invalidStorageRoot("path is not a directory") }
            let values = try rootURL.resourceValues(forKeys: [.isSymbolicLinkKey])
            guard values.isSymbolicLink != true else { throw LibraryRepositoryError.invalidStorageRoot("symbolic links are not accepted") }
        } else {
            try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        }
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: rootURL.path)
    }

    private func currentRevision() throws -> Int {
        guard try pathExists(documentURL) else { return 0 }
        return try decodeDocument(at: documentURL).document.revision
    }

    private struct DecodedDocument {
        let document: LibraryDocument
        let rawData: Data
        let sourceSchemaVersion: Int
    }

    private func decodeDocument(at url: URL) throws -> DecodedDocument {
        try decodeDocument(data: readData(at: url))
    }

    private func decodeDocument(data: Data) throws -> DecodedDocument {
        let decoded = try LibrarySchemaCodec.decode(data: data, decoder: decoder)
        return DecodedDocument(document: decoded.document, rawData: data, sourceSchemaVersion: decoded.sourceSchemaVersion)
    }

    private func readData(at url: URL) throws -> Data {
        let descriptor = open(url.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { throw LibraryRepositoryError.invalidDocument("could not open \(url.lastPathComponent): \(systemError())") }
        defer { _ = close(descriptor) }
        var info = stat()
        guard fstat(descriptor, &info) == 0 else { throw LibraryRepositoryError.invalidDocument(systemError()) }
        guard isRegularFile(info) else { throw LibraryRepositoryError.invalidDocument("storage file is not regular") }
        guard info.st_size >= 0 && info.st_size <= off_t(Self.maximumDocumentBytes) else { throw LibraryRepositoryError.dataTooLarge(limit: Self.maximumDocumentBytes) }
        let expected = Int(info.st_size)
        var data = Data(count: expected)
        let bytesRead = try data.withUnsafeMutableBytes { buffer -> Int in
            guard let base = buffer.baseAddress else { return 0 }
            var offset = 0
            while offset < expected {
                let count = Darwin.read(descriptor, base.advanced(by: offset), expected - offset)
                if count < 0 {
                    if errno == EINTR { continue }
                    throw LibraryRepositoryError.invalidDocument(systemError())
                }
                guard count > 0 else { throw LibraryRepositoryError.invalidDocument("storage file changed while reading") }
                offset += count
            }
            return offset
        }
        guard bytesRead == expected else { throw LibraryRepositoryError.invalidDocument("storage file changed while reading") }
        guard fstat(descriptor, &info) == 0, info.st_size == off_t(expected), isRegularFile(info) else {
            throw LibraryRepositoryError.invalidDocument("storage file changed while reading")
        }
        return data
    }

    private func encodedData(for document: LibraryDocument) throws -> Data {
        let data = try encoder.encode(document)
        guard data.count <= Self.maximumDocumentBytes else { throw LibraryRepositoryError.dataTooLarge(limit: Self.maximumDocumentBytes) }
        return data
    }

    private func writeDocument(_ document: LibraryDocument, to destination: URL) throws {
        try document.validate()
        try writeData(try encodedData(for: document), to: destination)
    }

    /// The primary write is atomic (`rename` after an fsynced temporary), so a
    /// failed write leaves `documentURL` at `currentData`.  Side files are
    /// explicitly restored here; a rollback error is surfaced rather than
    /// pretending the migration was side-effect free.
    private func rollbackFailedSave(createdPreSchema2Backup: Bool, createdPreSchema3Backup: Bool, replacedBackup: Bool, priorBackupData: Data?) -> [String] {
        var failures: [String] = []
        if createdPreSchema2Backup {
            do { try removeRegularFileIfPresent(preSchema2BackupURL) }
            catch { failures.append("remove migration snapshot: \(error.localizedDescription)") }
        }
        if createdPreSchema3Backup {
            do { try removeRegularFileIfPresent(preSchema3BackupURL) }
            catch { failures.append("remove schema-3 migration snapshot: \(error.localizedDescription)") }
        }
        if replacedBackup {
            do {
                if let priorBackupData {
                    try writeData(priorBackupData, to: backupURL)
                } else {
                    try removeRegularFileIfPresent(backupURL)
                }
            } catch {
                failures.append("restore ordinary backup: \(error.localizedDescription)")
            }
        }
        return failures
    }

    private func removeRegularFileIfPresent(_ url: URL) throws {
        guard let info = try lstatIfExists(url) else { return }
        guard isRegularFile(info) else { throw LibraryRepositoryError.invalidDocument("destination is not a regular file") }
        guard unlink(url.path) == 0 else { throw LibraryRepositoryError.saveFailed(systemError()) }
    }

    private func writeData(_ data: Data, to destination: URL) throws {
        guard data.count <= Self.maximumDocumentBytes else { throw LibraryRepositoryError.dataTooLarge(limit: Self.maximumDocumentBytes) }
        let parent = destination.deletingLastPathComponent()
        try fileManager.createDirectory(at: parent, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try rejectSymlinkDestination(destination)
        let temporary = parent.appendingPathComponent(".\(destination.lastPathComponent).\(UUID().uuidString).tmp")
        var descriptor = open(temporary.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw LibraryRepositoryError.saveFailed(systemError()) }
        defer {
            if descriptor >= 0 { _ = close(descriptor) }
            _ = unlink(temporary.path)
        }
        guard fchmod(descriptor, S_IRUSR | S_IWUSR) == 0 else { throw LibraryRepositoryError.saveFailed(systemError()) }
        try writeAll(data, to: descriptor)
        guard fsync(descriptor) == 0 else { throw LibraryRepositoryError.saveFailed(systemError()) }
        guard close(descriptor) == 0 else { throw LibraryRepositoryError.saveFailed(systemError()) }
        descriptor = -1
        try rejectSymlinkDestination(destination)
        guard rename(temporary.path, destination.path) == 0 else { throw LibraryRepositoryError.saveFailed(systemError()) }
    }

    private func validateExportDestination(_ destination: URL) throws {
        let candidates = [destination.standardizedFileURL, destination.resolvingSymlinksInPath()].map(\.path)
        let reserved = [documentURL, backupURL, preSchema2BackupURL, preSchema3BackupURL, lockURL].flatMap { [$0.standardizedFileURL.path, $0.resolvingSymlinksInPath().path] }
        guard candidates.allSatisfy({ !reserved.contains($0) }) else { throw LibraryRepositoryError.reservedExportDestination }
    }

    private func quarantineFile(at source: URL, namePrefix: String) throws -> URL {
        let formatter = ISO8601DateFormatter()
        let stamped = formatter.string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let quarantine = rootURL.appendingPathComponent("\(namePrefix).quarantine-\(stamped)-\(UUID().uuidString.prefix(8)).json")
        guard rename(source.path, quarantine.path) == 0 else { throw LibraryRepositoryError.saveFailed(systemError()) }
        if let info = try lstatIfExists(quarantine), isRegularFile(info) {
            try setOwnerOnlyPermissions(on: quarantine)
        }
        return quarantine
    }

    private func pathExists(_ url: URL) throws -> Bool { try lstatIfExists(url) != nil }

    private func rejectSymlinkDestination(_ url: URL) throws {
        if let info = try lstatIfExists(url), !isRegularFile(info) {
            throw LibraryRepositoryError.invalidDocument("destination is not a regular file")
        }
    }

    private func lstatIfExists(_ url: URL) throws -> stat? {
        var info = stat()
        if lstat(url.path, &info) == 0 { return info }
        if errno == ENOENT { return nil }
        throw LibraryRepositoryError.saveFailed(systemError())
    }

    private func requireRegularFile(_ descriptor: Int32) throws {
        var info = stat()
        guard fstat(descriptor, &info) == 0, isRegularFile(info) else { throw LibraryRepositoryError.saveFailed("lock is not a regular file") }
    }

    private func isRegularFile(_ info: stat) -> Bool { (info.st_mode & S_IFMT) == S_IFREG }

    private func setOwnerOnlyPermissions(on url: URL) throws {
        let descriptor = open(url.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { throw LibraryRepositoryError.saveFailed(systemError()) }
        defer { _ = close(descriptor) }
        try requireRegularFile(descriptor)
        guard fchmod(descriptor, S_IRUSR | S_IWUSR) == 0 else { throw LibraryRepositoryError.saveFailed(systemError()) }
    }

    private func writeAll(_ data: Data, to descriptor: Int32) throws {
        try data.withUnsafeBytes { buffer in
            guard let base = buffer.baseAddress else { return }
            var offset = 0
            while offset < data.count {
                let count = Darwin.write(descriptor, base.advanced(by: offset), data.count - offset)
                if count < 0 {
                    if errno == EINTR { continue }
                    throw LibraryRepositoryError.saveFailed(systemError())
                }
                guard count > 0 else { throw LibraryRepositoryError.saveFailed("short write") }
                offset += count
            }
        }
    }

    private func systemError() -> String { String(cString: strerror(errno)) }
}
