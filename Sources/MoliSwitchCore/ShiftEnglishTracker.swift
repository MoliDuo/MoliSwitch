import Foundation

/// Decides when a character typed with Shift held switches to the English
/// input source, and when letting go of Shift switches back.
///
/// Only keys that type a character count: Shift with Return, Tab, space or an
/// arrow, and Shift pressed on its own, are left to the application and the
/// input method. Nothing happens while a keyboard layout is selected, which
/// types Shift keys itself. The input source used before is only switched back
/// while the English one is still selected, so a switch the user made in
/// between is kept.
public struct ShiftEnglishTracker: Equatable, Sendable {
    public enum Decision: Equatable, Sendable {
        case pass
        /// Hold the key back, switch to the English input source, then type it.
        case switchToEnglish(englishID: String)
        /// Switch back to the input source used before Shift was held.
        case restore(inputSourceID: String)
    }

    private enum State: Equatable, Sendable {
        case idle
        case switched(previousID: String, englishID: String)
    }

    private var state: State = .idle

    public init() {}

    public var isSwitched: Bool {
        state != .idle
    }

    /// - Parameters:
    ///   - shifted: Whether Shift is held without ⌘, ⌃ or ⌥.
    ///   - currentID: The input source selected now.
    ///   - englishID: The English input source, if one is set up.
    public mutating func handle(
        _ key: SlashCommandKey,
        shifted: Bool,
        currentID: String?,
        englishID: String?
    ) -> Decision {
        if case .switched = state {
            // Normally Shift was let go before; when that was missed, the first
            // key without Shift ends it.
            return shifted ? .pass : shiftReleased(currentID: currentID)
        }

        guard
            shifted,
            key == .printable,
            let currentID,
            let englishID,
            currentID != englishID,
            !SlashCommandTracker.isKeyboardLayout(currentID)
        else {
            return .pass
        }

        state = .switched(previousID: currentID, englishID: englishID)
        return .switchToEnglish(englishID: englishID)
    }

    public mutating func shiftReleased(currentID: String?) -> Decision {
        guard case .switched(let previousID, let englishID) = state else { return .pass }
        state = .idle
        return currentID == englishID ? .restore(inputSourceID: previousID) : .pass
    }

    /// Forgets the switch without switching back, for example when another
    /// application became active and its own rule decides.
    public mutating func cancel() {
        state = .idle
    }
}
