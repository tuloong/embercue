import Carbon
import Foundation

public protocol GlobalHotKeying: AnyObject {
    func start(action: @escaping @Sendable () -> Void) throws
    func stop()
}

@MainActor
public final class HotKeyAvailabilityCoordinator {
    private let hotKey: GlobalHotKeying
    public private(set) var menuFallbackAvailable = false

    public init(hotKey: GlobalHotKeying) { self.hotKey = hotKey }

    public func composeMenuFallback(_ compose: () -> Void) {
        compose()
        menuFallbackAvailable = true
    }

    public func start(action: @escaping @Sendable () -> Void) -> Error? {
        do {
            try hotKey.start(action: action)
            return nil
        } catch {
            hotKey.stop()
            return error
        }
    }

    public func stop() { hotKey.stop() }
}

public enum GlobalHotKeyError: LocalizedError, Equatable {
    case eventHandler(OSStatus)
    case registration(OSStatus)

    public var errorDescription: String? {
        switch self {
        case let .eventHandler(status): "Embercue could not prepare its shortcut (Carbon status \(status))."
        case let .registration(status): "Control-Command-J is unavailable (Carbon status \(status)); use the menu bar instead."
        }
    }
}

public final class CarbonGlobalHotKey: GlobalHotKeying {
    private static let signature: OSType = 0x454D4252 // EMBR
    private var hotKey: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var action: (@Sendable () -> Void)?

    public init() {}
    deinit { stop() }

    public func start(action: @escaping @Sendable () -> Void) throws {
        stop()
        self.action = action
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let handlerStatus = InstallEventHandler(
            GetEventDispatcherTarget(),
            { _, _, userData in
                guard let userData else { return OSStatus(eventNotHandledErr) }
                let owner = Unmanaged<CarbonGlobalHotKey>.fromOpaque(userData).takeUnretainedValue()
                owner.action?()
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )
        guard handlerStatus == noErr else {
            self.action = nil
            throw GlobalHotKeyError.eventHandler(handlerStatus)
        }
        let identifier = EventHotKeyID(signature: Self.signature, id: 1)
        let registrationStatus = RegisterEventHotKey(UInt32(kVK_ANSI_J), UInt32(controlKey | cmdKey), identifier, GetEventDispatcherTarget(), 0, &hotKey)
        guard registrationStatus == noErr else {
            stop()
            throw GlobalHotKeyError.registration(registrationStatus)
        }
    }

    public func stop() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
        hotKey = nil
        eventHandler = nil
        action = nil
    }
}
