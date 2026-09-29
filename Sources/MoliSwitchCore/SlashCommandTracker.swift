import Foundation

/// A key pressed in the frontmost application, as far as slash commands care.
public enum SlashCommandKey: Equatable, Sendable {
    case slash
    /// Any other key that types a character.
    case printable
    case space
    case backspace
    case tab
    case returnKey
    case escape
    /// Arrows, function keys and shortcuts with ⌘, ⌃ or ⌥.
    case other
}

/// Decides when a slash starts a command, which is typed with the English
/// input source, and when the command is over and the input source used
/// before it comes back.
///
/// A slash starts a command at the start of the input. Whether the caret is
/// there comes from Accessibility when the application tells; otherwise the
/// start of the input is assumed right after focus moved or Return or Escape
/// was pressed, until a character is typed.
///
/// The command ends with Return, Escape, focus moving elsewhere, deleting
/// everything typed since the slash, or a space when restoresOnSpace is set.
/// Tab completes a command and does not end it. The input source is only
/// switched back while the English one is still selected, so a switch the user
/// made in between is kept.
public struct SlashCommandTracker: Equatable, Sendable {
    public enum Decision: Equatable, Sendable {
        case pass
        /// Hold the slash back, switch to the English input source, then type it.
        case switchToEnglish(englishID: String)
        /// Switch back to the input source used before the command.
        case restore(inputSourceID: String)
    }

    private enum State: Equatable, Sendable {
        case idle(atInputStart: Bool)
        /// typedCount counts the characters typed since the slash, including
        /// it, while every key since is known to have typed one or deleted one.
        case command(previousID: String, englishID: String, typedCount: Int?)
    }

    public var restoresOnSpace: Bool
    private var state: State = .idle(atInputStart: true)

    public init(restoresOnSpace: Bool = false) {
        self.restoresOnSpace = restoresOnSpace
    }

    public var isInCommand: Bool {
        if case .command = state { return true }
        return false
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
        case .idle(let atInputStart):
            return handleOutsideCommand(
                key,
                atInputStart: atInputStart,
                currentID: currentID,
                englishID: englishID,
                caretAtStart: caretAtStart
            )
        case .command(let previousID, let commandEnglishID, let typedCount):
            guard currentID == commandEnglishID else {
                // The user switched by hand; the command is theirs now.
                state = .idle(atInputStart: false)
                return handleOutsideCommand(
                    key,
                    atInputStart: false,
                    currentID: currentID,
                    englishID: englishID,
                    caretAtStart: caretAtStart
                )
            }
            return handleInCommand(key, previousID: previousID, englishID: commandEnglishID, typedCount: typedCount)
        }
    }

    /// Focus moved to another field, window or application.
    public mutating func focusChanged(currentID: String?) -> Decision {
        let previous = state
        state = .idle(atInputStart: true)

        if case .command(let previousID, let englishID, _) = previous, currentID == englishID {
            return .restore(inputSourceID: previousID)
        }
        return .pass
    }

    /// The switch to English did not happen, so there is no command to end.
    public mutating func cancelCommand() {
        state = .idle(atInputStart: false)
    }

    private mutating func handleOutsideCommand(
        _ key: SlashCommandKey,
        atInputStart: Bool,
        currentID: String?,
        englishID: String?,
        caretAtStart: () -> Bool?
    ) -> Decision {
        switch key {
        case .slash:
            state = .idle(atInputStart: false)
            guard
                let currentID,
                let englishID,
                currentID != englishID,
                !Self.isKeyboardLayout(currentID),
                caretAtStart() ?? atInputStart
            else {
                return .pass
            }
            state = .command(previousID: currentID, englishID: englishID, typedCount: 1)
            return .switchToEnglish(englishID: englishID)
        case .returnKey, .escape:
            state = .idle(atInputStart: true)
        case .printable, .space, .tab, .other:
            state = .idle(atInputStart: false)
        case .backspace:
            break
        }
        return .pass
    }

    private mutating func handleInCommand(
        _ key: SlashCommandKey,
        previousID: String,
        englishID: String,
        typedCount: Int?
    ) -> Decision {
        let end = Decision.restore(inputSourceID: previousID)

        switch key {
        case .returnKey, .escape:
            state = .idle(atInputStart: true)
            return end
        case .space where restoresOnSpace:
            state = .idle(atInputStart: false)
            return end
        case .slash, .printable, .space:
            state = .command(previousID: previousID, englishID: englishID, typedCount: typedCount.map { $0 + 1 })
        case .backspace:
            guard let typedCount else { return .pass }
            if typedCount <= 1 {
                // The slash itself was deleted.
                state = .idle(atInputStart: true)
                return end
            }
            state = .command(previousID: previousID, englishID: englishID, typedCount: typedCount - 1)
        case .tab, .other:
            // Completion, arrows and shortcuts change the text in ways that
            // cannot be counted.
            state = .command(previousID: previousID, englishID: englishID, typedCount: nil)
        }
        return .pass
    }
}
