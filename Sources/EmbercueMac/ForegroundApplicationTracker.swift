import AppKit

public protocol ForegroundApplication: AnyObject {
    var bundleIdentifier: String? { get }
    var processIdentifier: pid_t { get }
    var isTerminated: Bool { get }
    func activate()
}

extension NSRunningApplication: ForegroundApplication {
    public func activate() { activate(options: []) }
}

public final class ForegroundApplicationTracker {
    private let frontmostApplication: () -> (any ForegroundApplication)?
    private let ownProcessIdentifier: pid_t
    private var previousApplication: (any ForegroundApplication)?

    public init(frontmostApplication: @escaping () -> (any ForegroundApplication)? = { NSWorkspace.shared.frontmostApplication }, ownProcessIdentifier: pid_t = ProcessInfo.processInfo.processIdentifier) {
        self.frontmostApplication = frontmostApplication
        self.ownProcessIdentifier = ownProcessIdentifier
    }

    public func capturePreviousApplication(ignoring ownBundleIdentifier: String? = Bundle.main.bundleIdentifier) {
        previousApplication = nil
        guard let application = frontmostApplication(),
              application.bundleIdentifier != ownBundleIdentifier,
              application.processIdentifier != ownProcessIdentifier,
              !application.isTerminated else { return }
        previousApplication = application
    }

    public func reactivatePreviousApplication() {
        defer { previousApplication = nil }
        guard let previousApplication, !previousApplication.isTerminated else { return }
        previousApplication.activate()
    }
}
