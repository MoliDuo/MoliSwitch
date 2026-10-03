import Foundation
import XCTest

import MoliSwitchCore

@testable import MoliSwitchApp

final class AppRuntimeUsageLogTests: XCTestCase {
    private let notes = RunningApplicationInfo(bundleIdentifier: "com.apple.Notes", name: "Notes")

    private func string(_ event: UsageEvent, _ key: String) -> String? {
        if case .string(let value)? = event.fields[key] { return value }
        return nil
    }

    private func bool(_ event: UsageEvent, _ key: String) -> Bool? {
        if case .bool(let value)? = event.fields[key] { return value }
        return nil
    }

    @MainActor
    func testAppRuleLogsFocusAndSwitch() {
        let fixture = makeFixture(
            usageLogging: true,
            rules: [
                makeRule(
                    bundleIdentifier: notes.bundleIdentifier,
                    applicationName: "Notes",
                    inputSourceID: TestInputSources.abc.id,
                    inputSourceName: "ABC"
                )
            ]
        )

        fixture.runtime.applyRuleIfNeeded(for: notes)

        let focus = fixture.usage.events(named: "appFocus")
        XCTAssertEqual(focus.count, 1)
        XCTAssertEqual(string(focus[0], "app"), notes.bundleIdentifier)
        XCTAssertEqual(string(focus[0], "ruleKind"), "app")
        XCTAssertEqual(string(focus[0], "current"), TestInputSources.us.id)

        let switches = fixture.usage.events(named: "switch")
        XCTAssertEqual(switches.count, 1)
        XCTAssertEqual(string(switches[0], "reason"), "app")
        XCTAssertEqual(string(switches[0], "from"), TestInputSources.us.id)
        XCTAssertEqual(string(switches[0], "to"), TestInputSources.abc.id)
        XCTAssertEqual(bool(switches[0], "ok"), true)

        XCTAssertFalse(fixture.usage.events(named: "snapshot").isEmpty)
    }

    @MainActor
    func testFailedSwitchIsLoggedWithSnapshot() {
        let fixture = makeFixture(
            usageLogging: true,
            rules: [
                makeRule(
                    bundleIdentifier: notes.bundleIdentifier,
                    inputSourceID: TestInputSources.abc.id,
                    inputSourceName: "ABC"
                )
            ]
        )
        fixture.inputSources.selectionResult = false

        fixture.runtime.applyRuleIfNeeded(for: notes)

        let switches = fixture.usage.events(named: "switch")
        XCTAssertEqual(switches.count, 1)
        XCTAssertEqual(bool(switches[0], "ok"), false)
        XCTAssertTrue(
            fixture.usage.events(named: "snapshot").contains { string($0, "reason") == "switchFailed" }
        )
    }

    @MainActor
    func testRuleForCurrentInputSourceIsLoggedAsSkipped() {
        let fixture = makeFixture(
            usageLogging: true,
            rules: [makeRule(bundleIdentifier: notes.bundleIdentifier)]
        )

        fixture.runtime.applyRuleIfNeeded(for: notes)

        XCTAssertTrue(fixture.usage.events(named: "switch").isEmpty)
        let skipped = fixture.usage.events(named: "switchSkipped")
        XCTAssertEqual(skipped.count, 1)
        XCTAssertEqual(string(skipped[0], "reason"), "alreadyThere")
    }

    @MainActor
    func testOutsideSwitchIsManualAndOwnSwitchIsNot() {
        let fixture = makeFixture(
            usageLogging: true,
            rules: [
                makeRule(
                    bundleIdentifier: notes.bundleIdentifier,
                    inputSourceID: TestInputSources.abc.id,
                    inputSourceName: "ABC"
                )
            ]
        )
        fixture.runtime.start()
        fixture.runtime.applyRuleIfNeeded(for: notes)

        // The system reports the switch the app just made.
        fixture.inputSources.simulateSelection(of: TestInputSources.abc)
        XCTAssertTrue(fixture.usage.events(named: "manualSwitch").isEmpty)
        let reports = fixture.usage.events(named: "systemInputSourceChanged")
        XCTAssertEqual(reports.last.flatMap { bool($0, "ownSwitch") }, true)

        // The user switches by hand.
        fixture.inputSources.simulateSelection(of: TestInputSources.us)
        let manual = fixture.usage.events(named: "manualSwitch")
        XCTAssertEqual(manual.count, 1)
        XCTAssertEqual(string(manual[0], "from"), TestInputSources.abc.id)
        XCTAssertEqual(string(manual[0], "to"), TestInputSources.us.id)
        XCTAssertEqual(string(manual[0], "app"), notes.bundleIdentifier)
        XCTAssertNotNil(manual[0].fields["sinceFocusMs"])
        fixture.runtime.stop()
    }

    @MainActor
    func testShiftKeysAndSwitchAreLogged() async {
        let fixture = makeFixture(
            usageLogging: true,
            sources: [TestInputSources.us, TestInputSources.shuangpin],
            current: TestInputSources.shuangpin
        )
        fixture.runtime.shiftEnglishEnabled = true
        fixture.runtime.applyRuleIfNeeded(for: notes)

        fixture.keys.press(.printable, shifted: true)
        await waitUntil { fixture.keys.heldKeys.isEmpty }
        fixture.keys.releaseShift()
        await waitUntil { fixture.inputSources.current == TestInputSources.shuangpin }

        let keys = fixture.usage.events(named: "key")
        XCTAssertEqual(keys.count, 1)
        XCTAssertEqual(bool(keys[0], "shifted"), true)
        XCTAssertEqual(fixture.usage.events(named: "shiftRelease").count, 1)
        let reasons = fixture.usage.events(named: "switch").compactMap { string($0, "reason") }
        XCTAssertEqual(reasons, ["shift", "shiftRestore"])
    }

    @MainActor
    func testNothingIsLoggedWhenTurnedOff() {
        let fixture = makeFixture(
            usageLogging: true,
            rules: [makeRule(bundleIdentifier: notes.bundleIdentifier, inputSourceID: TestInputSources.abc.id)],
            defaultsValues: [AppRuntime.usageLoggingEnabledKey: true]
        )
        fixture.runtime.usageLoggingEnabled = false
        let before = fixture.usage.events.count

        fixture.runtime.applyRuleIfNeeded(for: notes)

        XCTAssertEqual(fixture.usage.events.count, before)
        XCTAssertFalse(fixture.usage.isEnabled)
        XCTAssertEqual(fixture.defaults.object(forKey: AppRuntime.usageLoggingEnabledKey) as? Bool, false)
    }

    @MainActor
    func testKeyLogsCharactersExceptInSecureInput() {
        let fixture = makeFixture(usageLogging: true)
        fixture.runtime.applyRuleIfNeeded(for: notes)

        fixture.keys.press(.printable, detail: KeyDetail(keyCode: 0, characters: "a"))
        fixture.keys.press(.printable, detail: KeyDetail(keyCode: 1, characters: "s", isSecureInput: true))

        let keys = fixture.usage.events(named: "key")
        XCTAssertEqual(string(keys[0], "chars"), "a")
        XCTAssertNil(keys[1].fields["chars"])
        XCTAssertEqual(bool(keys[1], "redacted"), true)
    }

    @MainActor
    func testReturnLogsTextOfFocusedField() {
        let fixture = makeFixture(usageLogging: true)
        fixture.runtime.applyRuleIfNeeded(for: notes)
        fixture.fields.details = ["identifier": "box", "value": "你好", "secure": false]

        fixture.keys.press(.returnKey, detail: KeyDetail(keyCode: 36, characters: "\r"))

        let texts = fixture.usage.events(named: "fieldText")
        XCTAssertEqual(texts.count, 1)
        XCTAssertEqual(string(texts[0], "value"), "你好")
        XCTAssertEqual(string(texts[0], "reason"), "return")
    }

    @MainActor
    func testSecureFieldTextIsNotLogged() {
        let fixture = makeFixture(usageLogging: true)
        fixture.runtime.applyRuleIfNeeded(for: notes)
        fixture.fields.details = ["value": "hunter2", "secure": true]

        fixture.keys.press(.returnKey, detail: KeyDetail(keyCode: 36, characters: "\r"))

        XCTAssertTrue(fixture.usage.events(named: "fieldText").isEmpty)
    }
}
