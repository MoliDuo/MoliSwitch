import AppKit
import CoreGraphics
import MoliSwitchCore

/// Sees key presses in every application through a session event tap, which
/// needs the Accessibility permission. Only which kind of key was pressed is
/// passed on, never what was typed.
@MainActor
final class SystemKeyEventMonitor: KeyEventMonitoring {
    /// Set on the keys this monitor types itself, so they pass untouched.
    private static let replayMarker: Int64 = 0x4D6F_6C69
    /// Held keys are typed after this long even when nobody released them, so
    /// a missed release never swallows what the user typed.
    private static let maximumHoldDuration: Duration = .milliseconds(500)

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var handler: (@MainActor (SlashCommandKey) -> Bool)?
    private var heldEvents: [CGEvent] = []
    private var holdTimeout: Task<Void, Never>?

    var isRunning: Bool {
        tap != nil
    }

    @discardableResult
    func start(_ handler: @escaping @MainActor (SlashCommandKey) -> Bool) -> Bool {
        self.handler = handler
        guard tap == nil else { return true }

        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard
            let created = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: CGEventMask(1) << CGEventType.keyDown.rawValue,
                callback: keyEventCallback,
                userInfo: refcon
            )
        else {
            self.handler = nil
            return false
        }

        let source = CFMachPortCreateRunLoopSource(nil, created, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: created, enable: true)
        tap = created
        runLoopSource = source
        return true
    }

    func stop() {
        releaseHeldKeys()
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        tap = nil
        runLoopSource = nil
        handler = nil
    }

    func releaseHeldKeys() {
        holdTimeout?.cancel()
        holdTimeout = nil

        let events = heldEvents
        heldEvents = []
        for event in events {
            type(event)
        }
    }

    private var isHolding: Bool {
        !heldEvents.isEmpty
    }

    private func type(_ keyDown: CGEvent) {
        keyDown.setIntegerValueField(.eventSourceUserData, value: Self.replayMarker)
        keyDown.post(tap: .cghidEventTap)

        if let keyUp = keyDown.copy() {
            keyUp.type = .keyUp
            keyUp.post(tap: .cghidEventTap)
        }
    }

    /// Returns true to drop the event.
    fileprivate func handle(_ type: CGEventType, _ event: CGEvent) -> Bool {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return false
        case .keyDown:
            break
        default:
            return false
        }

        guard event.getIntegerValueField(.eventSourceUserData) != Self.replayMarker else {
            return false
        }

        let hold = handler?(Self.key(for: event)) ?? false
        guard hold || isHolding, let copy = event.copy() else {
            return false
        }

        if !isHolding {
            holdTimeout = Task { [weak self] in
                try? await Task.sleep(for: Self.maximumHoldDuration)
                guard !Task.isCancelled else { return }
                self?.releaseHeldKeys()
            }
        }
        heldEvents.append(copy)
        return true
    }

    // MARK: - Kinds of keys

    private enum KeyCode {
        static let returnKey: Int64 = 36
        static let tab: Int64 = 48
        static let space: Int64 = 49
        static let delete: Int64 = 51
        static let escape: Int64 = 53
        static let keypadEnter: Int64 = 76
    }

    private static func key(for event: CGEvent) -> SlashCommandKey {
        if !event.flags.isDisjoint(with: [.maskCommand, .maskControl, .maskAlternate]) {
            return .other
        }

        switch event.getIntegerValueField(.keyboardEventKeycode) {
        case KeyCode.returnKey, KeyCode.keypadEnter: return .returnKey
        case KeyCode.escape: return .escape
        case KeyCode.tab: return .tab
        case KeyCode.delete: return .backspace
        case KeyCode.space: return .space
        default: break
        }

        // The character of the keyboard layout underneath the input method,
        // which is "/" for the slash key even while it would type "、".
        var length = 0
        var characters = [UniChar](repeating: 0, count: 4)
        event.keyboardGetUnicodeString(
            maxStringLength: characters.count,
            actualStringLength: &length,
            unicodeString: &characters
        )
        guard length > 0 else { return .other }

        let text = String(utf16CodeUnits: characters, count: min(length, characters.count))
        if text == "/" {
            return .slash
        }
        // Control characters, and the private use area where AppKit puts the
        // arrow and function keys.
        guard let scalar = text.unicodeScalars.first, scalar.value >= 0x20, scalar.value != 0x7F,
              !(0xF700...0xF8FF).contains(scalar.value)
        else {
            return .other
        }
        return .printable
    }
}

/// The tap's run loop source is on the main run loop, so the callback runs on
/// the main thread.
private let keyEventCallback: CGEventTapCallBack = { _, type, event, refcon in
    // The address is passed as an integer, which may cross into the main actor.
    guard let address = refcon.map(UInt.init(bitPattern:)) else {
        return Unmanaged.passUnretained(event)
    }
    // The event stays on the main thread, where it came in.
    nonisolated(unsafe) let mainThreadEvent = event
    let drop = MainActor.assumeIsolated {
        guard let pointer = UnsafeMutableRawPointer(bitPattern: address) else { return false }
        return Unmanaged<SystemKeyEventMonitor>.fromOpaque(pointer).takeUnretainedValue()
            .handle(type, mainThreadEvent)
    }
    return drop ? nil : Unmanaged.passUnretained(event)
}
