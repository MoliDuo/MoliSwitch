import Foundation
import XCTest
@testable import MoliSwitchCore

final class ShiftEnglishTrackerTests: XCTestCase {
    private let chinese = "com.apple.inputmethod.SCIM.Shuangpin"
    private let english = "com.apple.keylayout.US"
    private let dvorak = "com.apple.keylayout.Dvorak"

    private func press(
        _ tracker: inout ShiftEnglishTracker,
        _ category: ShiftKeyCategory? = .letter,
        shifted: Bool = true,
        current: String? = nil,
        options: ShiftEnglishOptions = .all
    ) -> ShiftEnglishTracker.Decision {
        tracker.handle(category, shifted: shifted, currentID: current ?? chinese, englishID: english, options: options)
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
        XCTAssertEqual(
            withoutEnglish.handle(.letter, shifted: true, currentID: chinese, englishID: nil, options: .all),
            .pass
        )
    }

    func testShiftWithKeysThatTypeNoCharacterDoesNothing() {
        var tracker = ShiftEnglishTracker()
        XCTAssertEqual(press(&tracker, nil), .pass)
        XCTAssertFalse(tracker.isSwitched)
    }

    func testEveryCategorySwitchesWhenChosen() {
        for category in ShiftKeyCategory.allCases {
            var tracker = ShiftEnglishTracker()
            XCTAssertEqual(press(&tracker, category), .switchToEnglish(englishID: english), "\(category)")
        }
    }

    func testCategoriesNotChosenAreLeftAlone() {
        let lettersOnly = ShiftEnglishOptions(categories: [.letter], restoresOnRelease: true)
        var tracker = ShiftEnglishTracker()

        XCTAssertEqual(press(&tracker, .digit, options: lettersOnly), .pass)
        XCTAssertEqual(press(&tracker, .symbol, options: lettersOnly), .pass)
        XCTAssertFalse(tracker.isSwitched)

        // A chosen key later in the same Shift switches.
        XCTAssertEqual(press(&tracker, .letter, options: lettersOnly), .switchToEnglish(englishID: english))
        // After that every key is typed in English until Shift is let go.
        XCTAssertEqual(press(&tracker, .digit, current: english, options: lettersOnly), .pass)
        XCTAssertTrue(tracker.isSwitched)
    }

    func testKeysAreChosenOneByOne() {
        // Only Shift + / (?) of the symbols.
        let question = ShiftEnglishOptions(keyCodes: [44], restoresOnRelease: true)
        var tracker = ShiftEnglishTracker()

        XCTAssertEqual(
            tracker.handle(
                .symbol,
                keyCode: 41,
                shifted: true,
                currentID: chinese,
                englishID: english,
                options: question
            ),
            .pass
        )
        XCTAssertEqual(
            tracker.handle(
                .symbol,
                keyCode: 44,
                shifted: true,
                currentID: chinese,
                englishID: english,
                options: question
            ),
            .switchToEnglish(englishID: english)
        )
    }

    func testKeysNotInTheTableFollowTheirCategory() {
        // 10 is the extra key of ISO keyboards, next to the left Shift.
        var tracker = ShiftEnglishTracker()
        let someSymbols = ShiftEnglishOptions(keyCodes: [44], restoresOnRelease: true)
        XCTAssertEqual(
            tracker.handle(
                .symbol,
                keyCode: 10,
                shifted: true,
                currentID: chinese,
                englishID: english,
                options: someSymbols
            ),
            .pass
        )
        let allSymbols = ShiftEnglishOptions(categories: [.symbol], restoresOnRelease: true)
        XCTAssertEqual(
            tracker.handle(
                .symbol,
                keyCode: 10,
                shifted: true,
                currentID: chinese,
                englishID: english,
                options: allSymbols
            ),
            .switchToEnglish(englishID: english)
        )
    }

    func testKeypadDigitsCountAsTheNumberRow() {
        let one = ShiftEnglishOptions(keyCodes: [18], restoresOnRelease: true)
        XCTAssertTrue(one.switches(keyCode: 83, category: .digit))
        XCTAssertFalse(one.switches(keyCode: 84, category: .digit))
    }

    func testCategoryStates() {
        var options = ShiftEnglishOptions(categories: [.letter], restoresOnRelease: true)
        XCTAssertEqual(options.state(of: .letter), .all)
        XCTAssertEqual(options.state(of: .symbol), .none)
        XCTAssertEqual(options.categories, [.letter])

        options.set(keyCode: 44, on: true)
        XCTAssertEqual(options.state(of: .symbol), .some)
        XCTAssertEqual(options.categories, [.letter])

        options.set(.symbol, on: true)
        XCTAssertEqual(options.categories, [.letter, .symbol])
        options.set(keyCode: 0, on: false)
        XCTAssertEqual(options.state(of: .letter), .some)
        XCTAssertEqual(options.categories, [.symbol])
    }

    func testEveryKeyIsInTheTableOnce() {
        XCTAssertEqual(ShiftKey.all.count, 47)
        XCTAssertEqual(Set(ShiftKey.all.map(\.keyCode)).count, 47)
        XCTAssertEqual(ShiftKey.keyCodes(in: .letter).count, 26)
        XCTAssertEqual(ShiftKey.keyCodes(in: .digit).count, 10)
        XCTAssertEqual(ShiftKey.label(forKeyCode: 44), "Shift + /（?）")
        XCTAssertEqual(ShiftKey.label(forKeyCode: 0), "Shift + A")
    }

    func testNothingSwitchesWhenOff() {
        var tracker = ShiftEnglishTracker()
        for category in ShiftKeyCategory.allCases {
            XCTAssertEqual(press(&tracker, category, options: .off), .pass)
        }
        XCTAssertFalse(tracker.isSwitched)
    }

    func testReleasingShiftSwitchesBack() {
        var tracker = ShiftEnglishTracker()
        _ = press(&tracker)
        XCTAssertEqual(tracker.shiftReleased(currentID: english), .restore(inputSourceID: chinese))
        XCTAssertFalse(tracker.isSwitched)
        XCTAssertEqual(tracker.shiftReleased(currentID: english), .pass)
    }

    func testStaysInEnglishWhenNotRestoringOnRelease() {
        var tracker = ShiftEnglishTracker()
        _ = press(&tracker, options: ShiftEnglishOptions(categories: [.letter], restoresOnRelease: false))
        XCTAssertEqual(tracker.shiftReleased(currentID: english), .pass)
        XCTAssertFalse(tracker.isSwitched)

        // The next switch follows its own options.
        _ = press(&tracker)
        XCTAssertEqual(tracker.shiftReleased(currentID: english), .restore(inputSourceID: chinese))
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
