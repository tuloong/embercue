#if canImport(XCTest)
import EmbercueCore
import Foundation
import XCTest

@MainActor
final class EmbercueCoreTests: XCTestCase {
    func testValidationStateTransitionsAndSaveRollback() throws {
        let repository = MemoryRepository()
        let engine = try LibraryEngine(repository: repository)
        XCTAssertThrowsError(try engine.add(kind: .prompt, text: " \n"))
        let item = try engine.add(kind: .prompt, text: String(repeating: "x", count: LibraryItem.maximumUTF8Bytes))
        XCTAssertEqual(engine.document.items[0].state, .active)
        try engine.complete(item.id)
        XCTAssertEqual(engine.document.items[0].state, .completed)
        repository.fail = true
        let before = engine.document
        XCTAssertThrowsError(try engine.restore(item.id))
        XCTAssertEqual(engine.document, before)
    }

    func testRevisionRecoveryAndMalformedQuarantine() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("EmbercueXCTest-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = try JSONLibraryRepository(rootURL: root)
        let date = Date(timeIntervalSince1970: 1)
        let document = LibraryDocument(revision: 1, items: [try LibraryItem(kind: .prompt, text: "one", createdAt: date, updatedAt: date)])
        try repository.save(document, expectedRevision: 0)
        XCTAssertThrowsError(try repository.save(document, expectedRevision: 0))
        try Data("invalid".utf8).write(to: repository.documentURL)
        let recovered = try repository.load()
        XCTAssertEqual(recovered.document, document)
        XCTAssertNotNil(recovered.recoveryNotice)
        XCTAssertEqual(try repository.load().document, document)
        let malformed = "{\"schemaVersion\":1,\"revision\":-1,\"items\":[]}"
        try Data(malformed.utf8).write(to: repository.documentURL)
        XCTAssertNotNil(try repository.load().recoveryNotice)
    }

    func testRevisionOverflowIsTypedAndQuarantined() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("EmbercueXCTest-Overflow-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = try JSONLibraryRepository(rootURL: root)
        XCTAssertThrowsError(try repository.save(LibraryDocument(revision: Int.max), expectedRevision: Int.max)) { error in
            XCTAssertEqual(error as? LibraryRepositoryError, .revisionOverflow)
        }
        try Data("{\"schemaVersion\":1,\"revision\":\(Int.max),\"items\":[]}".utf8).write(to: repository.documentURL)
        XCTAssertNotNil(try repository.load().recoveryNotice)
        let memory = MemoryRepository()
        memory.document = LibraryDocument(revision: Int.max)
        let engine = try LibraryEngine(repository: memory)
        XCTAssertThrowsError(try engine.add(kind: .prompt, text: "never")) { error in
            XCTAssertEqual(error as? LibraryRepositoryError, .revisionOverflow)
        }
    }

    func testMissingPrimaryRestoresBackupAndReservedExportsAreRejected() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("EmbercueXCTest-MissingPrimary-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = try JSONLibraryRepository(rootURL: root)
        let date = Date(timeIntervalSince1970: 1)
        let original = LibraryDocument(revision: 1, items: [try LibraryItem(kind: .prompt, text: "backup", createdAt: date, updatedAt: date)])
        try repository.save(original, expectedRevision: 0)
        var current = original
        current.revision = 2
        try repository.save(current, expectedRevision: 1)
        try FileManager.default.removeItem(at: repository.documentURL)
        let recovered = try repository.load()
        XCTAssertEqual(recovered.document, original)
        if case .restoredMissingPrimaryFromBackup = recovered.recoveryNotice {} else { XCTFail("Expected missing-primary recovery") }
        let engine = try LibraryEngine(repository: repository)
        _ = try engine.add(kind: .prompt, text: "mutate")
        let relaunchRepository = try JSONLibraryRepository(rootURL: root)
        XCTAssertEqual(try relaunchRepository.load().document.revision, 2)

        let primaryBefore = try Data(contentsOf: repository.documentURL)
        for target in [repository.documentURL, repository.backupURL, root.appendingPathComponent(".library.lock")] {
            XCTAssertThrowsError(try repository.export(original, to: target)) { error in
                XCTAssertEqual(error as? LibraryRepositoryError, .reservedExportDestination)
            }
        }
        let alias = root.appendingPathComponent("primary-alias.json")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: repository.documentURL)
        XCTAssertThrowsError(try repository.export(original, to: alias)) { error in
            XCTAssertEqual(error as? LibraryRepositoryError, .reservedExportDestination)
        }
        XCTAssertEqual(try Data(contentsOf: repository.documentURL), primaryBefore)
        let external = root.appendingPathComponent("external.json")
        try repository.export(original, to: external)
        XCTAssertEqual(try JSONDecoder.document.decode(LibraryDocument.self, from: Data(contentsOf: external)), original)
    }

    func testUnreadableBackupWithoutPrimaryIsQuarantinedBeforeBackupRotation() throws {
        let invalidBackupRoot = FileManager.default.temporaryDirectory.appendingPathComponent("EmbercueXCTest-UnreadableBackup-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: invalidBackupRoot) }
        let invalidBackupRepository = try JSONLibraryRepository(rootURL: invalidBackupRoot)
        let invalidBytes = Data("invalid backup".utf8)
        try invalidBytes.write(to: invalidBackupRepository.backupURL)

        let result = try invalidBackupRepository.load()
        XCTAssertEqual(result.document, LibraryDocument())
        guard case let .startedEmptyWithQuarantinedBackup(quarantinedBackupFile) = result.recoveryNotice else { return XCTFail("Expected quarantined unreadable-backup notice") }
        let quarantinedBackup = invalidBackupRoot.appendingPathComponent(quarantinedBackupFile)
        XCTAssertEqual(try Data(contentsOf: quarantinedBackup), invalidBytes)
        XCTAssertEqual(filePermissions(at: quarantinedBackup), 0o600)
        XCTAssertFalse(FileManager.default.fileExists(atPath: invalidBackupRepository.backupURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: invalidBackupRepository.documentURL.path))
        let engine = try LibraryEngine(repository: invalidBackupRepository)
        _ = try engine.add(kind: .prompt, text: "first mutation")
        _ = try engine.add(kind: .prompt, text: "second mutation")
        let activeBackup = try JSONDecoder.document.decode(LibraryDocument.self, from: Data(contentsOf: invalidBackupRepository.backupURL))
        XCTAssertEqual(activeBackup.revision, 1)
        XCTAssertEqual(activeBackup.items.map(\.text), ["first mutation"])
        let relaunched = try JSONLibraryRepository(rootURL: invalidBackupRoot).load().document
        XCTAssertEqual(relaunched.revision, 2)
        XCTAssertEqual(relaunched.items.map(\.text), ["first mutation", "second mutation"])

        let firstLaunchRoot = FileManager.default.temporaryDirectory.appendingPathComponent("EmbercueXCTest-FirstLaunch-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: firstLaunchRoot) }
        let firstLaunchResult = try JSONLibraryRepository(rootURL: firstLaunchRoot).load()
        XCTAssertEqual(firstLaunchResult.document, LibraryDocument())
        XCTAssertNil(firstLaunchResult.recoveryNotice)
    }

    func testCorruptPrimaryAndBackupAreQuarantinedBeforeBackupRotation() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("EmbercueXCTest-CorruptBoth-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = try JSONLibraryRepository(rootURL: root)
        let invalidPrimary = Data("invalid primary".utf8)
        let invalidBackup = Data("invalid backup".utf8)
        try invalidPrimary.write(to: repository.documentURL)
        try invalidBackup.write(to: repository.backupURL)

        let result = try repository.load()
        XCTAssertEqual(result.document, LibraryDocument())
        guard case let .startedEmptyWithQuarantinedPrimaryAndBackup(quarantinedPrimaryFile, quarantinedBackupFile) = result.recoveryNotice else { return XCTFail("Expected dual quarantine notice") }
        let quarantinedPrimary = root.appendingPathComponent(quarantinedPrimaryFile)
        let quarantinedBackup = root.appendingPathComponent(quarantinedBackupFile)
        XCTAssertEqual(try Data(contentsOf: quarantinedPrimary), invalidPrimary)
        XCTAssertEqual(try Data(contentsOf: quarantinedBackup), invalidBackup)
        XCTAssertEqual(filePermissions(at: quarantinedPrimary), 0o600)
        XCTAssertEqual(filePermissions(at: quarantinedBackup), 0o600)
        XCTAssertFalse(FileManager.default.fileExists(atPath: repository.backupURL.path))
        XCTAssertEqual(try repository.load().document, LibraryDocument())
        let engine = try LibraryEngine(repository: repository)
        _ = try engine.add(kind: .prompt, text: "first mutation")
        _ = try engine.add(kind: .prompt, text: "second mutation")
        let activeBackup = try JSONDecoder.document.decode(LibraryDocument.self, from: Data(contentsOf: repository.backupURL))
        XCTAssertEqual(activeBackup.revision, 1)
        XCTAssertEqual(activeBackup.items.map(\.text), ["first mutation"])
        let relaunched = try JSONLibraryRepository(rootURL: root).load().document
        XCTAssertEqual(relaunched.revision, 2)
        XCTAssertEqual(relaunched.items.map(\.text), ["first mutation", "second mutation"])
    }
}

private func filePermissions(at url: URL) -> Int {
    (try? FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber)?.intValue ?? -1
}

private final class MemoryRepository: LibraryRepository {
    var document = LibraryDocument()
    var fail = false
    func load() throws -> LibraryLoadResult { LibraryLoadResult(document: document) }
    func save(_ document: LibraryDocument, expectedRevision: Int) throws {
        if fail { throw LibraryRepositoryError.saveFailed("injected") }
        self.document = document
    }
    func export(_ document: LibraryDocument, to destination: URL) throws {}
}

private extension JSONDecoder {
    static var document: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }
}
#else
// Command Line Tools on the author host omit XCTest and Swift Testing. EmbercueChecks executes
// the same core failure/recovery contract until this XCTest suite can run on a full Xcode host.
enum EmbercueCoreTestTarget {}
#endif
