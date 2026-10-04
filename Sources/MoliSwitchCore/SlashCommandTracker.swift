import Foundation

/// A key pressed in the frontmost application, as far as slash commands care.
public enum SlashCommandKey: Equatable, Sendable {
    case slash
    /// Any other key that types a character.
    case printable
    case space
    case backspace
    /// Deletes more than one character, like ⌥⌫ or ⌘⌫, or deletes forward.
    case deleteMore
    /// Clears the whole input, like ⌃U or ⌃C.
    case clearLine
    case tab
    case returnKey
    case escape
    /// Arrows, function keys and shortcuts with ⌘, ⌃ or ⌥.
    case other
}

/// What a key press looked like, for the usage log.
public struct KeyDetail: Equatable, Sendable {
    public var keyCode: Int
    /// The characters of the keyboard layout underneath the input method, so
    /// the letters of the pinyin while typing Chinese.
    public var characters: String
    /// Held modifiers, for example ["shift", "cmd"].
    public var modifiers: [String]
    /// Whether secure input was on, as it is in password fields.
    public var isSecureInput: Bool

    public init(keyCode: Int, characters: String, modifiers: [String] = [], isSecureInput: Bool = false) {
        self.keyCode = keyCode
        self.characters = characters
        self.modifiers = modifiers
        self.isSecureInput = isSecureInput
    }
}

/// What the key monitor passes on: a key pressed, both Shift keys let go, or
/// a modifier key changed.
public enum MonitoredKeyEvent: Equatable, Sendable {
    /// shifted is set when Shift is held without ⌘, ⌃ or ⌥. category is set
    /// for the keys that type a character. detail is only for the usage log.
    case keyDown(SlashCommandKey, shifted: Bool, category: ShiftKeyCategory? = nil, detail: KeyDetail? = nil)
    case shiftReleased
    /// A modifier key (including Caps Lock) changed state, for the usage log.
    /// flags are the modifiers held now; capsLock is the Caps Lock state.
    case modifierChanged(keyCode: Int, flags: [String], capsLock: Bool)
}

/// Decides when a slash starts a command, which is typed with the English
/// input source, and when the command is over and the input source used
/// before it comes back.
///
/// A slash starts a command at the start of the input. Whether the caret is
/// there comes from Accessibility when the application tells; otherwise the
/// start of the input is assumed right after focus moved or Return, Escape or
/// a key clearing the input was pressed, until a character is typed. Right
/// after deleting, the input may be empty again: an input method types several
/// keys into one character, so the keys cannot be counted, and a slash then
/// starts a command too. When that guess was wrong, deleting the slash and
/// typing it again types it with the input source in use.
///
/// The command ends with Return, Escape, focus moving elsewhere, deleting
/// everything typed since the slash, or, when restoresOnSpace is set, a space
/// or Tab. Otherwise Tab completes a command and does not end it. The input
/// source is only switched back while the English one is still selected, so a
/// switch the user made in between is kept.
public struct SlashCommandTracker: Equatable, Sendable {
    public enum Decision: Equatable, Sendable {
        case pass
        /// Hold the slash back, switch to the English input source, then type it.
        case switchToEnglish(englishID: String)
        /// Switch back to the input source used before the command.
        case restore(inputSourceID: String)
    }

    /// Whether the caret is at the start of the input, as far as the keys tell.
    public enum InputStart: Equatable, Sendable {
        case yes
        case no
        /// Something was deleted since a character was typed.
        case afterDeleting
    }

    private enum State: Equatable, Sendable {
        case idle(start: InputStart)
        /// typedCount counts the characters typed since the slash, including
        /// it, while every key since is known to have typed one or deleted one.
        /// guessed is set when the command started right after deleting.
        case command(previousID: String, englishID: String, typedCount: Int?, guessed: Bool)
    }

    /// Whether a space or Tab ends a command, like Return does.
    public var restoresOnSpace: Bool
    private var state: State = .idle(start: .yes)

    public init(restoresOnSpace: Bool = false) {
        self.restoresOnSpace = restoresOnSpace
    }

    public var isInCommand: Bool {
        if case .command = state { return true }
        return false
    }

    /// A short description of the state for diagnostics, without any text.
    public var stateDescription: String {
        switch state {
        case .idle(let start):
            return "idle(\(start))"
        case .command(_, _, let typedCount, let guessed):
            return "command(typed: \(typedCount.map(String.init) ?? "?"), guessed: \(guessed))"
        }
    }

    /// Input sources that are keyboard layouts type a slash themselves.
    public static func isKeyboardLayout(_ inputSourceID: String) -> Bool {
        inputSourceID.contains(".keylayout.")
    }

    /// - Parameters:
    ///   - currentID: The input source selected now.
    ///   - englishID: The English input source, if one is set up.
    ///   - caretAtStart: Asked only for a slash outside a command: whether the
    ///     caret is at the start of the input, or nil when unknown.
    public mutating func handle(
        _ key: SlashCommandKey,
        currentID: String?,
        englishID: String?,
        caretAtStart: () -> Bool?
    ) -> Decision {
        switch state {
        case .idle(let start):
            return handleOutsideCommand(
                key,
                start: start,
                currentID: currentID,
                englishID: englishID,
                caretAtStart: caretAtStart
            )
        case .command(let previousID, let commandEnglishID, let typedCount, let guessed):
            guard currentID == commandEnglishID else {
                // The user switched by hand; the command is theirs now.
                state = .idle(start: .no)
                return handleOutsideCommand(
                    key,
                    start: .no,
                    currentID: currentID,
                    englishID: englishID,
                    caretAtStart: caretAtStart
                )
            }
            return handleInCommand(
                key,
                previousID: previousID,
                englishID: commandEnglishID,
                typedCount: typedCount,
                guessed: guessed
            )
        }
    }

    /// Focus moved to another field, window or application.
    public mutating func focusChanged(currentID: String?) -> Decision {
        let previous = state
        state = .idle(start: .yes)

        if case .command(let previousID, let englishID, _, _) = previous, currentID == englishID {
            return .restore(inputSourceID: previousID)
        }
        return .pass
    }

    /// The switch to English did not happen, so there is no command to end.
    public mutating func cancelCommand() {
        state = .idle(start: .no)
    }

    private mutating func handleOutsideCommand(
        _ key: SlashCommandKey,
        start: InputStart,
        currentID: String?,
        englishID: String?,
        caretAtStart: () -> Bool?
    ) -> Decision {
        switch key {
        case .slash:
            state = .idle(start: .no)
            guard
                let currentID,
                let englishID,
                currentID != englishID,
                !Self.isKeyboardLayout(currentID)
            else {
                return .pass
            }
            let guessed: Bool
            if let known = caretAtStart() {
                guard known else { return .pass }
                guessed = false
            } else {
                guard start != .no else { return .pass }
                guessed = start == .afterDeleting
            }
            state = .command(previousID: currentID, englishID: englishID, typedCount: 1, guessed: guessed)
            return .switchToEnglish(englishID: englishID)
        case .returnKey, .escape, .clearLine:
            state = .idle(start: .yes)
        case .printable, .space, .tab, .other:
            state = .idle(start: .no)
        case .backspace, .deleteMore:
            if start == .no {
                state = .idle(start: .afterDeleting)
            }
        }
        return .pass
    }

    private mutating func handleInCommand(
        _ key: SlashCommandKey,
        previousID: String,
        englishID: String,
        typedCount: Int?,
        guessed: Bool
    ) -> Decision {
        let end = Decision.restore(inputSourceID: previousID)
        func stay(typedCount: Int?) {
            state = .command(previousID: previousID, englishID: englishID, typedCount: typedCount, guessed: guessed)
        }

        switch key {
        case .returnKey, .escape, .clearLine:
            state = .idle(start: .yes)
            return end
        case .space where restoresOnSpace, .tab where restoresOnSpace:
            state = .idle(start: .no)
            return end
        case .slash, .printable, .space:
            stay(typedCount: typedCount.map { $0 + 1 })
        case .backspace:
            guard let typedCount else { return .pass }
            if typedCount <= 1 {
                // The slash itself was deleted. After a wrong guess, the slash
                // typed next is meant for the text.
                state = .idle(start: guessed ? .no : .yes)
                return end
            }
            stay(typedCount: typedCount - 1)
        case .tab, .deleteMore, .other:
            // Completion, arrows, shortcuts and deleting words change the text
            // in ways that cannot be counted.
            stay(typedCount: nil)
        }
        return .pass
    }
}
