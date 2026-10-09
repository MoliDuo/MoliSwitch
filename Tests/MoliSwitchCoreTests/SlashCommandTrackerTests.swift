import Foundation
import XCTest
@testable import MoliSwitchCore

final class SlashCommandTrackerTests: XCTestCase {
    private let chinese = "com.apple.inputmethod.SCIM.Shuangpin"
    private let english = "com.apple.keylayout.US"
    private let other = "com.bytedance.inputmethod.doubaoime.pinyin"

    /// Presses a key with the given input source selected.
    private func press(
        _ tracker: inout SlashCommandTracker,
        _ key: SlashCommandKey,
        current: String? = nil,
        caretAtStart: Bool? = nil
    ) -> SlashCommandTracker.Decision {
        tracker.handle(key, currentID: current ?? chinese, englishID: english, caretAtStart: { caretAtStart })
    }

    /// Starts a command and returns the tracker inside it.
    private func startedTracker(restoresOnSpace: Bool = false) -> SlashCommandTracker {
        var tracker = SlashCommandTracker(restoresOnSpace: restoresOnSpace)
        XCTAssertEqual(press(&tracker, .slash), .switchToEnglish(englishID: english))
        XCTAssertTrue(tracker.isInCommand)
        return tracker
    }

    func testSlashAtTheStartStartsACommand() {
        var tracker = SlashCommandTracker()
        XCTAssertEqual(press(&tracker, .slash, caretAtStart: true), .switchToEnglish(englishID: english))
    }

    func testSlashAfterTextDoesNothing() {
        var tracker = SlashCommandTracker()
        XCTAssertEqual(press(&tracker, .slash, caretAtStart: false), .pass)

        var guessed = SlashCommandTracker()
        XCTAssertEqual(press(&guessed, .printable), .pass)
        XCTAssertEqual(press(&guessed, .slash), .pass)
        XCTAssertFalse(guessed.isInCommand)
    }

    func testCaretPositionWinsOverTheGuess() {
        var tracker = SlashCommandTracker()
        XCTAssertEqual(press(&tracker, .printable), .pass)
        XCTAssertEqual(press(&tracker, .slash, caretAtStart: true), .switchToEnglish(englishID: english))
    }

    func testReturnAndEscapeStartANewInput() {
        var tracker = SlashCommandTracker()
        _ = press(&tracker, .printable)
        _ = press(&tracker, .returnKey)
        XCTAssertEqual(press(&tracker, .slash), .switchToEnglish(englishID: english))

        var escaped = SlashCommandTracker()
        _ = press(&escaped, .printable)
        _ = press(&escaped, .escape)
        XCTAssertEqual(press(&escaped, .slash), .switchToEnglish(englishID: english))
    }

    func testEnglishAndKeyboardLayoutsTypeTheSlashThemselves() {
        var tracker = SlashCommandTracker()
        XCTAssertEqual(press(&tracker, .slash, current: english), .pass)

        var abc = SlashCommandTracker()
        XCTAssertEqual(press(&abc, .slash, current: "com.apple.keylayout.ABC"), .pass)

        var withoutEnglish = SlashCommandTracker()
        let decision = withoutEnglish.handle(.slash, currentID: chinese, englishID: nil, caretAtStart: { true })
        XCTAssertEqual(decision, .pass)
    }

    func testReturnAndEscapeEndTheCommand() {
        for key in [SlashCommandKey.returnKey, .escape] {
            var tracker = startedTracker()
            XCTAssertEqual(press(&tracker, .printable, current: english), .pass)
            XCTAssertEqual(press(&tracker, key, current: english), .restore(inputSourceID: chinese))
            XCTAssertFalse(tracker.isInCommand)
            // The next input starts fresh.
            XCTAssertEqual(press(&tracker, .slash), .switchToEnglish(englishID: english))
        }
    }

    func testTabKeepsTheCommand() {
        var tracker = startedTracker()
        XCTAssertEqual(press(&tracker, .tab, current: english), .pass)
        XCTAssertTrue(tracker.isInCommand)
        XCTAssertEqual(press(&tracker, .returnKey, current: english), .restore(inputSourceID: chinese))
    }

    func testTabEndsTheCommandWhenSpaceDoes() {
        var tracker = startedTracker(restoresOnSpace: true)
        XCTAssertEqual(press(&tracker, .printable, current: english), .pass)
        XCTAssertEqual(press(&tracker, .tab, current: english), .restore(inputSourceID: chinese))
        XCTAssertFalse(tracker.isInCommand)
        // The completed command is text now, so a slash after it is not a command.
        XCTAssertEqual(press(&tracker, .slash), .pass)
    }

    func testSlashAfterDeletingStartsACommand() {
        var tracker = SlashCommandTracker()
        _ = press(&tracker, .printable)
        _ = press(&tracker, .printable)
        _ = press(&tracker, .backspace)
        XCTAssertEqual(press(&tracker, .slash), .switchToEnglish(englishID: english))

        var words = SlashCommandTracker()
        _ = press(&words, .printable)
        _ = press(&words, .deleteMore)
        XCTAssertEqual(press(&words, .slash), .switchToEnglish(englishID: english))
    }

    func testTypingAfterDeletingIsNotTheStart() {
        var tracker = SlashCommandTracker()
        _ = press(&tracker, .printable)
        _ = press(&tracker, .backspace)
        _ = press(&tracker, .printable)
        XCTAssertEqual(press(&tracker, .slash), .pass)
    }

    func testCaretPositionWinsOverDeleting() {
        var tracker = SlashCommandTracker()
        _ = press(&tracker, .printable)
        _ = press(&tracker, .backspace)
        XCTAssertEqual(press(&tracker, .slash, caretAtStart: false), .pass)
    }

    func testSlashTypedAgainAfterAWrongGuessIsLeftAlone() {
        var tracker = SlashCommandTracker()
        _ = press(&tracker, .printable)
        _ = press(&tracker, .backspace)
        XCTAssertEqual(press(&tracker, .slash), .switchToEnglish(englishID: english))
        XCTAssertEqual(press(&tracker, .backspace, current: english), .restore(inputSourceID: chinese))
        XCTAssertEqual(press(&tracker, .slash), .pass)
    }

    func testSlashTypedAgainAtTheStartStartsACommandAgain() {
        var tracker = startedTracker()
        XCTAssertEqual(press(&tracker, .backspace, current: english), .restore(inputSourceID: chinese))
        XCTAssertEqual(press(&tracker, .slash), .switchToEnglish(englishID: english))
    }

    func testClearingTheLine() {
        var tracker = SlashCommandTracker()
        _ = press(&tracker, .printable)
        _ = press(&tracker, .clearLine)
        XCTAssertEqual(press(&tracker, .slash), .switchToEnglish(englishID: english))
        XCTAssertEqual(press(&tracker, .printable, current: english), .pass)
        XCTAssertEqual(press(&tracker, .clearLine, current: english), .restore(inputSourceID: chinese))
        XCTAssertFalse(tracker.isInCommand)
        XCTAssertEqual(press(&tracker, .slash), .switchToEnglish(englishID: english))
    }

    func testDeletingWordsInACommandStopsCounting() {
        var tracker = startedTracker()
        _ = press(&tracker, .printable, current: english)
        XCTAssertEqual(press(&tracker, .deleteMore, current: english), .pass)
        XCTAssertEqual(press(&tracker, .backspace, current: english), .pass)
        XCTAssertTrue(tracker.isInCommand)
    }

    func testSpaceEndsTheCommandOnlyWhenTurnedOn() {
        var tracker = startedTracker()
        XCTAssertEqual(press(&tracker, .space, current: english), .pass)
        XCTAssertTrue(tracker.isInCommand)

        var restoring = startedTracker(restoresOnSpace: true)
        XCTAssertEqual(press(&restoring, .printable, current: english), .pass)
        XCTAssertEqual(press(&restoring, .space, current: english), .restore(inputSourceID: chinese))
        XCTAssertFalse(restoring.isInCommand)
    }

    func testDeletingTheSlashEndsTheCommand() {
        var tracker = startedTracker()
        _ = press(&tracker, .printable, current: english)
        _ = press(&tracker, .space, current: english)
        XCTAssertEqual(press(&tracker, .backspace, current: english), .pass)
        XCTAssertEqual(press(&tracker, .backspace, current: english), .pass)
        XCTAssertEqual(press(&tracker, .backspace, current: english), .restore(inputSourceID: chinese))
        XCTAssertFalse(tracker.isInCommand)
    }

    func testBackspaceStopsCountingAfterKeysThatCannotBeCounted() {
        var tracker = startedTracker()
        _ = press(&tracker, .tab, current: english)
        XCTAssertEqual(press(&tracker, .backspace, current: english), .pass)
        XCTAssertEqual(press(&tracker, .backspace, current: english), .pass)
        XCTAssertTrue(tracker.isInCommand)
    }

    func testFocusChangeEndsTheCommand() {
        var tracker = startedTracker()
        XCTAssertEqual(tracker.focusChanged(currentID: english), .restore(inputSourceID: chinese))
        XCTAssertFalse(tracker.isInCommand)

        var idle = SlashCommandTracker()
        _ = press(&idle, .printable)
        XCTAssertEqual(idle.focusChanged(currentID: chinese), .pass)
        XCTAssertEqual(press(&idle, .slash), .switchToEnglish(englishID: english))
    }

    func testManualSwitchIsKept() {
        var tracker = startedTracker()
        XCTAssertEqual(press(&tracker, .returnKey, current: other), .pass)
        XCTAssertFalse(tracker.isInCommand)

        var focused = startedTracker()
        XCTAssertEqual(focused.focusChanged(currentID: other), .pass)
    }

    func testCancelledCommandIsForgotten() {
        var tracker = startedTracker()
        tracker.cancelCommand()
        XCTAssertFalse(tracker.isInCommand)
        XCTAssertEqual(press(&tracker, .returnKey, current: english), .pass)
    }

    func testAppListKeepsEachApplicationOnceInNameOrder() {
        var list = SlashCommandAppList(normalizing: [
            SlashCommandApp(bundleIdentifier: "com.tinyspeck.slackmacgap", applicationName: "Slack"),
            SlashCommandApp(bundleIdentifier: "com.anthropic.claudefordesktop", applicationName: "Claude"),
            SlashCommandApp(bundleIdentifier: "com.tinyspeck.slackmacgap", applicationName: "Slack 2"),
            SlashCommandApp(bundleIdentifier: " ", applicationName: "Blank"),
        ])
        XCTAssertEqual(list.apps.map(\.applicationName), ["Claude", "Slack"])

        list.insert(SlashCommandApp(bundleIdentifier: "com.hnc.Discord", applicationName: "Discord"))
        XCTAssertEqual(list.apps.map(\.applicationName), ["Claude", "Discord", "Slack"])
        XCTAssertNotNil(list.remove(bundleIdentifier: "com.hnc.Discord"))
        XCTAssertNil(list.remove(bundleIdentifier: "com.hnc.Discord"))
    }

    func testTerminalsDoNotReportTheCaret() {
        XCTAssertFalse(SlashCommandApp.reportsCaretPosition(bundleIdentifier: "com.apple.Terminal"))
        XCTAssertTrue(SlashCommandApp.reportsCaretPosition(bundleIdentifier: "com.anthropic.claudefordesktop"))
    }
}
