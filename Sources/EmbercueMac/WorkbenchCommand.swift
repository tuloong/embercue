import Foundation

public enum WorkbenchCommand: String, CaseIterable, Sendable {
    case copy
    case copyAsList
    case markDone
    case expand
    case edit
    case editInNewWindow
    case mergeNotes
    case restore
}

public enum WorkbenchSelectionMode: Sendable {
    case replace
    case toggle
    case extend
}
