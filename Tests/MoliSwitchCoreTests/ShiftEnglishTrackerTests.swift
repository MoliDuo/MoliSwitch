import Foundation
import XCTest

@testable import MoliSwitchCore

final class ShiftEnglishTrackerTests: XCTestCase {
    private let chinese = "com.apple.inputmethod.SCIM.Shuangpin"
    private let english = "com.apple.keylayout.US"
    private let dvorak = "com.apple.keylayout.Dvorak"

    private func press(
        _ tracker: inout ShiftEnglishTracker,
        _ key: SlashCommandKey = .printable,
        shifted: Bool = true,
        current: String? = nil
    ) -> ShiftEnglishTracker.Decision {
        tracker.handle(key, shifted: shifted, currentID: current ?? chinese, englishID: english)
    }

    func testShiftedCharacterSwitchesToEnglish() {
        var tracker = ShiftEnglishTracker()
        XCTAssertEqual(press(&tracker), .switchToEnglish(englishID: english))
        XCTAssertTrue(tracker.isSwitched)

        // Further keys while Shift is still held are typed as they are.
        XCTAssertEqual(press(&tracker, current: english), .pass)
    }

    func testCharacterWithoutShiftDoesNothing() {
        var tracker = ShiftEnglishTracker()
        XCTAssertEqual(press(&tracker, shifted: false), .pass)
        XCTAssertFalse(tracker.isSwitched)
    }

    func testKeyboardLayoutsAndEnglishAreLeftAlone() {
        var tracker = ShiftEnglishTracker()
        XCTAssertEqual(press(&tracker, current: english), .pass)
        XCTAssertEqual(press(&tracker, current: dvorak), .pass)
        XCTAssertFalse(tracker.isSwitched)

        var withoutEnglish = ShiftEnglishTracker()
        XCTAssertEqual(withoutEnglish.handle(.printable, shifted: true, currentID: chinese, englishID: nil), .pass)
    }

    func testShiftWithKeysThatTypeNoCharacterDoesNothing() {
        for key: SlashCommandKey in [.returnKey, .tab, .space, .backspace, .escape, .other] {
            var tracker = ShiftEnglishTracker()
            XCTAssertEqual(press(&tracker, key), .pass, "\(key)")
            XCTAssertFalse(tracker.isSwitched)
        }
    }

    func testReleasingShiftSwitchesBack() {
        var tracker = ShiftEnglishTracker()
        _ = press(&tracker)
        XCTAssertEqual(tracker.shiftReleased(currentID: english), .restore(inputSourceID: chinese))
        XCTAssertFalse(tracker.isSwitched)
        XCTAssertEqual(tracker.shiftReleased(currentID: english), .pass)
    }

    func testReleasingShiftWithoutASwitchDoesNothing() {
        var tracker = ShiftEnglishTracker()
        XCTAssertEqual(tracker.shiftReleased(currentID: chinese), .pass)
    }

    func testManualSwitchIsKept() {
        var tracker = ShiftEnglishTracker()
        _ = press(&tracker)
        XCTAssertEqual(tracker.shiftReleased(currentID: dvorak), .pass)
        XCTAssertFalse(tracker.isSwitched)
    }

    func testKeyWithoutShiftEndsAMissedRelease() {
        var tracker = ShiftEnglishTracker()
        _ = press(&tracker)
        XCTAssertEqual(press(&tracker, shifted: false, current: english), .restore(inputSourceID: chinese))
        XCTAssertFalse(tracker.isSwitched)
    }

    func testCancelForgetsTheSwitch() {
        var tracker = ShiftEnglishTracker()
        _ = press(&tracker)
        tracker.cancel()
        XCTAssertFalse(tracker.isSwitched)
        XCTAssertEqual(tracker.shiftReleased(currentID: english), .pass)
    }
}
