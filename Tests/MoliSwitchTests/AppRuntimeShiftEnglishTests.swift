import Foundation
import XCTest

import MoliSwitchCore

@testable import MoliSwitchApp

final class AppRuntimeShiftEnglishTests: XCTestCase {
    private let notes = RunningApplicationInfo(bundleIdentifier: "com.apple.Notes", name: "Notes")
    private let photoshop = RunningApplicationInfo(bundleIdentifier: "com.adobe.Photoshop", name: "Photoshop")

    /// Shift is turned on, Shuangpin is selected and Notes is in front.
    @MainActor
    private func makeShiftFixture(
        rules: [(RunningApplicationInfo, ShiftEnglishOptions)] = [],
        excluded: [RunningApplicationInfo] = []
    ) -> RuntimeFixture {
        let fixture = makeFixture(
            shiftAppRules: rules.map {
                ShiftAppRule(bundleIdentifier: $0.0.bundleIdentifier, applicationName: $0.0.name, options: $0.1)
            },
            shiftExcludedApps: excluded.map {
                SlashCommandApp(bundleIdentifier: $0.bundleIdentifier, applicationName: $0.name)
            },
            sources: [TestInputSources.us, TestInputSources.shuangpin],
            current: TestInputSources.shuangpin
        )
        fixture.runtime.shiftEnglishEnabled = true
        fixture.runtime.applyRuleIfNeeded(for: notes)
        return fixture
    }

    @MainActor
    func testMonitorRunsOnlyWhileTurnedOn() {
        let fixture = makeFixture()
        XCTAssertFalse(fixture.keys.isRunning)
        XCTAssertFalse(fixture.runtime.shiftEnglishEnabled)

        fixture.runtime.shiftEnglishEnabled = true
        XCTAssertTrue(fixture.keys.isRunning)
        XCTAssertEqual(fixture.defaults.object(forKey: AppRuntime.shiftEnglishEnabledKey) as? Bool, true)

        fixture.runtime.shiftEnglishEnabled = false
        XCTAssertFalse(fixture.keys.isRunning)
    }

    @MainActor
    func testShiftedKeySwitchesToEnglishBeforeItIsTyped() async {
        let fixture = makeShiftFixture()

        fixture.keys.press(.printable, shifted: true)
        XCTAssertEqual(fixture.keys.heldKeys, [.printable])
        XCTAssertEqual(fixture.inputSources.current, TestInputSources.us)

        await waitUntil { fixture.keys.heldKeys.isEmpty }
        XCTAssertEqual(fixture.keys.typedKeys, [.printable])

        // More keys while Shift is held go straight through.
        fixture.keys.press(.printable, shifted: true)
        XCTAssertEqual(fixture.keys.typedKeys, [.printable, .printable])
        XCTAssertEqual(fixture.runtime.switchCount, 1)
    }

    @MainActor
    func testReleasingShiftSwitchesBack() async {
        let fixture = makeShiftFixture()
        fixture.keys.press(.printable, shifted: true)

        fixture.keys.releaseShift()
        await waitUntil { fixture.inputSources.current == TestInputSources.shuangpin }
        XCTAssertEqual(fixture.inputSources.current, TestInputSources.shuangpin)
        XCTAssertEqual(fixture.keys.typedKeys, [.printable])
        XCTAssertEqual(fixture.runtime.switchCount, 2)
    }

    @MainActor
    func testStaysInEnglishWhenTurnedOff() async {
        let fixture = makeShiftFixture()
        fixture.runtime.shiftRestoresOnRelease = false
        XCTAssertEqual(fixture.defaults.object(forKey: AppRuntime.shiftRestoresOnReleaseKey) as? Bool, false)

        fixture.keys.press(.printable, shifted: true)
        await waitUntil { fixture.keys.heldKeys.isEmpty }
        fixture.keys.releaseShift()
        fixture.keys.press(.printable)
        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(fixture.inputSources.current, TestInputSources.us)
        XCTAssertEqual(fixture.keys.typedKeys, [.printable, .printable])
        XCTAssertEqual(fixture.runtime.switchCount, 1)
    }

    @MainActor
    func testKeysTypedWhileSwitchingBackWaitForIt() async {
        let fixture = makeShiftFixture()
        fixture.keys.press(.printable, shifted: true)
        await waitUntil { fixture.keys.heldKeys.isEmpty }

        fixture.keys.releaseShift()
        fixture.keys.press(.printable)
        XCTAssertEqual(fixture.keys.heldKeys, [.printable])

        await waitUntil { fixture.keys.heldKeys.isEmpty }
        XCTAssertEqual(fixture.inputSources.current, TestInputSources.shuangpin)
        XCTAssertEqual(fixture.keys.typedKeys, [.printable, .printable])
    }

    @MainActor
    func testManualSwitchIsKept() async {
        let fixture = makeShiftFixture()
        fixture.keys.press(.printable, shifted: true)
        await waitUntil { fixture.keys.heldKeys.isEmpty }

        fixture.inputSources.current = TestInputSources.abc
        fixture.keys.releaseShift()
        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(fixture.inputSources.current, TestInputSources.abc)
    }

    @MainActor
    func testKeysWithoutACharacterAndPlainShiftAreLeftAlone() {
        let fixture = makeShiftFixture()

        fixture.keys.press(.returnKey, shifted: true)
        fixture.keys.press(.printable)
        fixture.keys.releaseShift()

        XCTAssertEqual(fixture.keys.typedKeys, [.returnKey, .printable])
        XCTAssertEqual(fixture.inputSources.current, TestInputSources.shuangpin)
    }

    @MainActor
    func testCategoriesNotChosenAreLeftAlone() async {
        let fixture = makeShiftFixture()
        fixture.runtime.shiftEnglishCategories = [.letter]
        XCTAssertEqual(fixture.defaults.stringArray(forKey: AppRuntime.shiftEnglishCategoriesKey), ["letter"])

        fixture.keys.press(.printable, shifted: true, category: .digit)
        XCTAssertEqual(fixture.keys.typedKeys, [.printable])
        XCTAssertEqual(fixture.inputSources.current, TestInputSources.shuangpin)

        fixture.keys.press(.printable, shifted: true, category: .letter)
        XCTAssertEqual(fixture.inputSources.current, TestInputSources.us)
    }

    @MainActor
    func testCategoriesAreReadFromDefaults() {
        let fixture = makeFixture(defaultsValues: [AppRuntime.shiftEnglishCategoriesKey: ["digit", "symbol"]])
        XCTAssertEqual(fixture.runtime.shiftEnglishCategories, [.digit, .symbol])
        XCTAssertEqual(makeFixture().runtime.shiftEnglishCategories, Set(ShiftKeyCategory.allCases))
    }

    @MainActor
    func testApplicationTurnedOffIsLeftAlone() {
        let fixture = makeShiftFixture(rules: [(notes, .off)])

        fixture.keys.press(.printable, shifted: true)

        XCTAssertEqual(fixture.keys.typedKeys, [.printable])
        XCTAssertEqual(fixture.inputSources.current, TestInputSources.shuangpin)
    }

    @MainActor
    func testApplicationRuleReplacesTheGlobalSettings() async {
        let digitsStay = ShiftEnglishOptions(categories: [.digit], restoresOnRelease: false)
        let fixture = makeShiftFixture(rules: [(notes, digitsStay)])

        fixture.keys.press(.printable, shifted: true, category: .letter)
        XCTAssertEqual(fixture.inputSources.current, TestInputSources.shuangpin)

        fixture.keys.press(.printable, shifted: true, category: .digit)
        XCTAssertEqual(fixture.inputSources.current, TestInputSources.us)
        await waitUntil { fixture.keys.heldKeys.isEmpty }

        // The rule does not switch back, although the global setting does.
        fixture.keys.releaseShift()
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(fixture.inputSources.current, TestInputSources.us)
    }

    @MainActor
    func testSettingAndClearingApplicationRules() {
        let fixture = makeShiftFixture()
        let application = makeInstalledApplication("Photoshop", photoshop.bundleIdentifier)
        XCTAssertNil(fixture.runtime.shiftOptions(for: application))

        fixture.runtime.setShiftOptions(.off, for: application)
        XCTAssertEqual(fixture.runtime.shiftOptions(for: application), .off)
        XCTAssertEqual(fixture.shiftAppRuleStore.rules.map(\.bundleIdentifier), [photoshop.bundleIdentifier])

        fixture.runtime.applyRuleIfNeeded(for: photoshop)
        fixture.keys.press(.printable, shifted: true)
        XCTAssertEqual(fixture.inputSources.current, TestInputSources.shuangpin)

        fixture.runtime.setShiftOptions(nil, for: application)
        XCTAssertNil(fixture.runtime.shiftOptions(for: application))
        XCTAssertTrue(fixture.shiftAppRuleStore.rules.isEmpty)
    }

    @MainActor
    func testApplicationsWithRulesCountAsConfigured() {
        let fixture = makeShiftFixture(rules: [(photoshop, .all)])
        fixture.runtime.applicationListScope = .configured

        XCTAssertEqual(
            fixture.runtime.filteredInstalledApplications.map(\.bundleIdentifier),
            [photoshop.bundleIdentifier]
        )
    }

    @MainActor
    func testExcludedApplicationsAreCarriedOverOnce() {
        let fixture = makeShiftFixture(excluded: [notes])

        XCTAssertEqual(fixture.shiftAppRuleStore.rules.map(\.bundleIdentifier), [notes.bundleIdentifier])
        XCTAssertEqual(fixture.shiftAppRuleStore.rules.first?.options, .off)
        XCTAssertTrue(fixture.defaults.bool(forKey: AppRuntime.shiftExcludedAppsMigratedKey))
        XCTAssertEqual(fixture.shiftExcludedAppStore.apps.map(\.bundleIdentifier), [notes.bundleIdentifier])

        fixture.keys.press(.printable, shifted: true)
        XCTAssertEqual(fixture.inputSources.current, TestInputSources.shuangpin)

        // Turning Shift back on in Notes is not undone by the next load.
        fixture.runtime.setShiftOptions(nil, for: makeInstalledApplication("Notes", notes.bundleIdentifier))
        fixture.runtime.reloadRulesFromDisk()
        XCTAssertTrue(fixture.runtime.shiftAppRules.rules.isEmpty)
    }

    @MainActor
    func testSwitchingApplicationsForgetsTheSwitch() {
        let fixture = makeShiftFixture()
        fixture.keys.press(.printable, shifted: true)

        fixture.runtime.applyRuleIfNeeded(for: photoshop)
        fixture.keys.releaseShift()

        XCTAssertEqual(fixture.inputSources.current, TestInputSources.us)
    }

    @MainActor
    func testUnreadableRulesPauseEditing() {
        let fixture = makeFixture()
        fixture.shiftAppRuleStore.failLoading(with: FakeRuleStore.Failure(message: "broken"))
        fixture.runtime.reloadRulesFromDisk()

        XCTAssertFalse(fixture.runtime.shiftAppRuleEditingEnabled)
        XCTAssertTrue(fixture.runtime.hasStorageFailure)
        XCTAssertEqual(fixture.runtime.storageStatus, .shiftAppRulesReadFailure)

        fixture.runtime.setShiftOptions(.off, for: makeInstalledApplication("Notes", notes.bundleIdentifier))
        XCTAssertTrue(fixture.shiftAppRuleStore.rules.isEmpty)
    }

    @MainActor
    func testUnreadableOldListIsTriedAgainLater() {
        let fixture = makeFixture()
        XCTAssertTrue(fixture.defaults.bool(forKey: AppRuntime.shiftExcludedAppsMigratedKey))

        let broken = makeFixture(shiftExcludedApps: [SlashCommandApp(bundleIdentifier: notes.bundleIdentifier, applicationName: "Notes")])
        broken.defaults.removeObject(forKey: AppRuntime.shiftExcludedAppsMigratedKey)
        broken.runtime.setShiftOptions(nil, for: makeInstalledApplication("Notes", notes.bundleIdentifier))
        broken.shiftExcludedAppStore.failLoading(with: FakeRuleStore.Failure(message: "broken"))
        broken.runtime.reloadRulesFromDisk()

        XCTAssertTrue(broken.runtime.shiftAppRuleEditingEnabled)
        XCTAssertFalse(broken.defaults.bool(forKey: AppRuntime.shiftExcludedAppsMigratedKey))
    }
}
