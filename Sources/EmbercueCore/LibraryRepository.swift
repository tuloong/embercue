import Foundation

public enum LibraryRepositoryError: LocalizedError, Equatable, Sendable {
    case revisionConflict(expected: Int, actual: Int)
    case itemNotFound
    case sectionNotFound
    case invalidSelection(String)
    case duplicateSectionName
    case nonEmptySection
    case sortOrderOverflow
    case invalidSchema(Int)
    case revisionOverflow
    case invalidDocument(String)
    case dataTooLarge(limit: Int)
    case invalidStorageRoot(String)
    case reservedExportDestination
    case saveFailed(String)
    case exportFailed(String)

    public var errorDescription: String? {
        switch self {
        case let .revisionConflict(expected, actual): "Library changed elsewhere (expected revision \(expected), found \(actual)). Reload before trying again."
        case .itemNotFound: "That library item no longer exists."
        case .sectionNotFound: "That section no longer exists."
        case let .invalidSelection(reason): reason
        case .duplicateSectionName: "A section with that name already exists."
        case .nonEmptySection: "Move or archive the notes in this section before removing it."
        case .sortOrderOverflow: "This section cannot accept another note until its order is repaired."
        case let .invalidSchema(version): "Library schema \(version) is not supported by this version of Embercue."
        case .revisionOverflow: "The library revision is outside Embercue's supported range."
        case let .invalidDocument(reason): "The library document is invalid: \(reason)"
        case let .dataTooLarge(limit): "The library document exceeds the \(limit / 1024 / 1024) MiB safety limit."
        case let .invalidStorageRoot(reason): "Embercue cannot use its data directory: \(reason)"
        case .reservedExportDestination: "Choose an export destination outside Embercue's managed library files."
        case let .saveFailed(reason): "Embercue could not save your change: \(reason)"
        case let .exportFailed(reason): "Embercue could not export the library: \(reason)"
        }
    }
}

public protocol LibraryRepository {
    func load() throws -> LibraryLoadResult
    func save(_ document: LibraryDocument, expectedRevision: Int) throws
    func export(_ document: LibraryDocument, to destination: URL) throws
}
