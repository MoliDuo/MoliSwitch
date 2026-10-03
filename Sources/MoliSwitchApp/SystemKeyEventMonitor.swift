import AppKit
import Carbon.HIToolbox
import CoreGraphics
import MoliSwitchCore

/// Sees key presses in every application through a session event tap, which
/// needs the Accessibility permission. The kind of key is passed on, along with
/// the characters of the key for the usage log.
@MainActor
final class SystemKeyEventMonitor: KeyEventMonitoring {
    /// Set on the keys this monitor types itself, so they pass untouched.
    private static let replayMarker: Int64 = 0x4D6F_6C69
    /// Held keys are typed after this long even when nobody released them, so
    /// a missed release never swallows what the user typed.
    private static let maximumHoldDuration: Duration = .milliseconds(500)

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var handler: (@MainActor (MonitoredKeyEvent) -> Bool)?
    private var heldEvents: [CGEvent] = []
    private var shiftDown = false
    private var holdTimeout: Task<Void, Never>?

    var isRunning: Bool {
        tap != nil
    }

    @discardableResult
    func start(_ handler: @escaping @MainActor (MonitoredKeyEvent) -> Bool) -> Bool {
        self.handler = handler
        guard tap == nil else { return true }

        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard
            let created = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: CGEventMask(1) << CGEventType.keyDown.rawValue
                    | CGEventMask(1) << CGEventType.flagsChanged.rawValue,
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
        shiftDown = false
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
            // Keys pressed while the tap was off were not seen.
            Diagnostics.record(
                .slash, .error,
                "key tap disabled (\(type == .tapDisabledByTimeout ? "timeout" : "user input")), re-enabling"
            )
            if let tap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return false
        case .flagsChanged:
            // Modifier changes always go through; only letting go of Shift is
            // passed on.
            let shiftDown = event.flags.contains(.maskShift)
            if self.shiftDown && !shiftDown {
                _ = handler?(.shiftReleased)
            }
            self.shiftDown = shiftDown
            return false
        case .keyDown:
            break
        default:
            return false
        }

        guard event.getIntegerValueField(.eventSourceUserData) != Self.replayMarker else {
            return false
        }

        let flags = event.flags
        let shifted = flags.contains(.maskShift)
            && flags.isDisjoint(with: [.maskCommand, .maskControl, .maskAlternate])
        let key = Self.key(for: event)
        let detail = KeyDetail(
            keyCode: Int(event.getIntegerValueField(.keyboardEventKeycode)),
            characters: Self.characters(of: event),
            modifiers: Self.modifierNames(flags),
            isSecureInput: IsSecureEventInputEnabled()
        )
        let hold = handler?(
            .keyDown(key, shifted: shifted, category: Self.category(of: event, key: key), detail: detail)
        ) ?? false
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

    private static func modifierNames(_ flags: CGEventFlags) -> [String] {
        [(CGEventFlags.maskShift, "shift"), (.maskControl, "ctrl"), (.maskAlternate, "alt"), (.maskCommand, "cmd")]
            .filter { flags.contains($0.0) }
            .map(\.1)
    }

    // MARK: - Kinds of keys

    private enum KeyCode {
        static let returnKey: Int64 = 36
        static let tab: Int64 = 48
        static let space: Int64 = 49
        static let delete: Int64 = 51
        static let escape: Int64 = 53
        static let keypadEnter: Int64 = 76
        static let forwardDelete: Int64 = 117
        /// 1 to 9 and 0 on the number row, where they are on every layout.
        static let numberRow: Set<Int64> = [18, 19, 20, 21, 23, 22, 26, 28, 25, 29]
        /// 0 to 9 on the keypad.
        static let keypadDigits: Set<Int64> = [82, 83, 84, 85, 86, 87, 88, 89, 91, 92]
    }

    /// What ⌃U and ⌃C type, which clears the input in shells and coding agents.
    private static let clearLineCharacters: Set<String> = ["\u{15}", "\u{03}"]

    private static func key(for event: CGEvent) -> SlashCommandKey {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags

        if !flags.isDisjoint(with: [.maskCommand, .maskControl, .maskAlternate]) {
            switch keyCode {
            case KeyCode.delete where !flags.isDisjoint(with: [.maskCommand, .maskAlternate]),
                 KeyCode.forwardDelete:
                return .deleteMore
            default:
                let onlyControl = flags.intersection([.maskCommand, .maskControl, .maskAlternate]) == .maskControl
                return onlyControl && clearLineCharacters.contains(characters(of: event)) ? .clearLine : .other
            }
        }

        switch keyCode {
        case KeyCode.returnKey, KeyCode.keypadEnter: return .returnKey
        case KeyCode.escape: return .escape
        case KeyCode.tab: return .tab
        case KeyCode.delete: return .backspace
        case KeyCode.forwardDelete: return .deleteMore
        case KeyCode.space: return .space
        default: break
        }

        let text = characters(of: event)
        guard !text.isEmpty else { return .other }

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

    /// Which key typed the character, for the keys that type one.
    private static func category(of event: CGEvent, key: SlashCommandKey) -> ShiftKeyCategory? {
        guard key == .printable || key == .slash else { return nil }
        if characters(of: event).first?.isLetter == true {
            return .letter
        }
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        if KeyCode.numberRow.contains(keyCode) || KeyCode.keypadDigits.contains(keyCode) {
            return .digit
        }
        return .symbol
    }

    /// The characters of the keyboard layout underneath the input method,
    /// which is "/" for the slash key even while it would type "、".
    private static func characters(of event: CGEvent) -> String {
        var length = 0
        var characters = [UniChar](repeating: 0, count: 4)
        event.keyboardGetUnicodeString(
            maxStringLength: characters.count,
            actualStringLength: &length,
            unicodeString: &characters
        )
        return String(utf16CodeUnits: characters, count: min(length, characters.count))
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
