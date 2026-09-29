import Foundation
import XCTest

import MoliSwitchCore

@testable import MoliSwitchApp

final class AppRuntimeShiftEnglishTests: XCTestCase {
    private let notes = RunningApplicationInfo(bundleIdentifier: "com.apple.Notes", name: "Notes")
    private let photoshop = RunningApplicationInfo(bundleIdentifier: "com.adobe.Photoshop", name: "Photoshop")

    /// Shift is turned on, Shuangpin is selected and Notes is in front.
    @MainActor
    private func makeShiftFixture(excluded: [RunningApplicationInfo] = []) -> RuntimeFixture {
        let fixture = makeFixture(
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
    func testExcludedApplicationIsLeftAlone() {
        let fixture = makeShiftFixture(excluded: [notes])

        fixture.keys.press(.printable, shifted: true)

        XCTAssertEqual(fixture.keys.typedKeys, [.printable])
        XCTAssertEqual(fixture.inputSources.current, TestInputSources.shuangpin)
    }

    @MainActor
    func testExcludingAndIncludingApplications() {
        let fixture = makeShiftFixture()
        let application = makeInstalledApplication("Photoshop", photoshop.bundleIdentifier)
        XCTAssertTrue(fixture.runtime.usesShiftEnglish(application))

        fixture.runtime.setUsesShiftEnglish(false, for: application)
        XCTAssertFalse(fixture.runtime.usesShiftEnglish(application))
        XCTAssertEqual(fixture.shiftExcludedAppStore.apps.map(\.bundleIdentifier), [photoshop.bundleIdentifier])

        fixture.runtime.applyRuleIfNeeded(for: photoshop)
        fixture.keys.press(.printable, shifted: true)
        XCTAssertEqual(fixture.inputSources.current, TestInputSources.shuangpin)

        fixture.runtime.setUsesShiftEnglish(true, for: application)
        XCTAssertTrue(fixture.shiftExcludedAppStore.apps.isEmpty)
    }

    @MainActor
    func testExcludedApplicationsCountAsConfigured() {
        let fixture = makeShiftFixture(excluded: [photoshop])
        fixture.runtime.applicationListScope = .configured

        XCTAssertEqual(
            fixture.runtime.filteredInstalledApplications.map(\.bundleIdentifier),
            [photoshop.bundleIdentifier]
        )
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
    func testUnreadableListPausesEditing() {
        let fixture = makeFixture()
        fixture.shiftExcludedAppStore.failLoading(with: FakeRuleStore.Failure(message: "broken"))
        fixture.runtime.reloadRulesFromDisk()

        XCTAssertFalse(fixture.runtime.shiftExcludedAppEditingEnabled)
        XCTAssertTrue(fixture.runtime.hasStorageFailure)
        XCTAssertEqual(fixture.runtime.storageStatus, .shiftExcludedAppsReadFailure)

        fixture.runtime.setUsesShiftEnglish(false, for: makeInstalledApplication("Notes", notes.bundleIdentifier))
        XCTAssertTrue(fixture.shiftExcludedAppStore.apps.isEmpty)
    }
}
