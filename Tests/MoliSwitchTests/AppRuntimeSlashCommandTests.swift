import Foundation
import XCTest

import MoliSwitchCore

@testable import MoliSwitchApp

final class AppRuntimeSlashCommandTests: XCTestCase {
    private let claude = RunningApplicationInfo(bundleIdentifier: "com.anthropic.claudefordesktop", name: "Claude")
    private let notes = RunningApplicationInfo(bundleIdentifier: "com.apple.Notes", name: "Notes")
    private let terminal = RunningApplicationInfo(bundleIdentifier: "com.apple.Terminal", name: "Terminal")

    private let inputField = FieldSignature(role: "AXTextArea", ancestorRoles: ["AXGroup"])
    private let otherField = FieldSignature(role: "AXTextField", descriptor: "搜索")

    /// Claude is listed, Shuangpin is selected and the caret is in an empty field.
    @MainActor
    private func makeClaudeFixture(apps: [RunningApplicationInfo]? = nil) -> RuntimeFixture {
        let listed = (apps ?? [claude]).map {
            SlashCommandApp(bundleIdentifier: $0.bundleIdentifier, applicationName: $0.name)
        }
        let fixture = makeFixture(
            slashCommandApps: listed,
            sources: [TestInputSources.us, TestInputSources.shuangpin, TestInputSources.doubao],
            current: TestInputSources.shuangpin
        )
        fixture.fields.caretAtStart = true
        return fixture
    }

    /// Types a slash that starts a command and waits until it reached the application.
    @MainActor
    private func startCommand(_ fixture: RuntimeFixture) async {
        fixture.keys.press(.slash)
        await waitUntil { fixture.keys.heldKeys.isEmpty }
    }

    @MainActor
    func testMonitorRunsOnlyWhileAnApplicationIsListed() {
        let empty = makeFixture()
        XCTAssertFalse(empty.keys.isRunning)

        let fixture = makeClaudeFixture()
        XCTAssertTrue(fixture.keys.isRunning)

        fixture.runtime.removeSlashCommandApp(bundleIdentifier: claude.bundleIdentifier)
        XCTAssertFalse(fixture.keys.isRunning)
        XCTAssertTrue(fixture.slashCommandAppStore.apps.isEmpty)
    }

    @MainActor
    func testTurningTheFeatureOffStopsTheMonitor() {
        let fixture = makeClaudeFixture()

        fixture.runtime.slashCommandSwitchingEnabled = false

        XCTAssertFalse(fixture.keys.isRunning)
        XCTAssertEqual(fixture.defaults.object(forKey: AppRuntime.slashCommandSwitchingEnabledKey) as? Bool, false)
    }

    @MainActor
    func testMonitorWaitsForAccessibility() {
        let fixture = makeClaudeFixture()
        fixture.runtime.stop()
        XCTAssertFalse(fixture.keys.isRunning)

        let untrusted = makeFixture(slashCommandApps: [
            SlashCommandApp(bundleIdentifier: claude.bundleIdentifier, applicationName: claude.name),
        ])
        untrusted.fields.isTrusted = false
        untrusted.runtime.refreshAccessibilityTrust()
        XCTAssertFalse(untrusted.keys.isRunning)

        untrusted.fields.isTrusted = true
        untrusted.runtime.refreshAccessibilityTrust()
        XCTAssertTrue(untrusted.keys.isRunning)
    }

    @MainActor
    func testReportsWhenKeysCannotBeSeen() {
        let fixture = makeFixture()
        fixture.keys.canStart = false

        fixture.runtime.addSlashCommandApp(makeInstalledApplication("Claude", claude.bundleIdentifier))

        XCTAssertTrue(fixture.runtime.keyMonitoringUnavailable)

        fixture.keys.canStart = true
        fixture.runtime.refreshAccessibilityTrust()
        XCTAssertFalse(fixture.runtime.keyMonitoringUnavailable)
        XCTAssertTrue(fixture.keys.isRunning)
    }

    @MainActor
    func testSlashAtTheStartSwitchesToEnglishBeforeItIsTyped() async {
        let fixture = makeClaudeFixture()
        fixture.runtime.applyRuleIfNeeded(for: claude)

        fixture.keys.press(.slash)
        XCTAssertEqual(fixture.keys.heldKeys, [.slash])
        XCTAssertEqual(fixture.inputSources.current, TestInputSources.us)

        // Keys typed before the slash was released wait behind it.
        fixture.keys.press(.printable)
        XCTAssertEqual(fixture.keys.heldKeys, [.slash, .printable])

        await waitUntil { fixture.keys.heldKeys.isEmpty }
        XCTAssertEqual(fixture.keys.typedKeys, [.slash, .printable])
        XCTAssertEqual(fixture.runtime.switchCount, 1)
    }

    @MainActor
    func testSlashInOtherApplicationsIsLeftAlone() {
        let fixture = makeClaudeFixture()
        fixture.runtime.applyRuleIfNeeded(for: notes)

        fixture.keys.press(.slash)

        XCTAssertEqual(fixture.keys.typedKeys, [.slash])
        XCTAssertEqual(fixture.inputSources.current, TestInputSources.shuangpin)
        XCTAssertTrue(fixture.inputSources.selectedIDs.isEmpty)
    }

    @MainActor
    func testSlashAfterTextIsLeftAlone() {
        let fixture = makeClaudeFixture()
        fixture.runtime.applyRuleIfNeeded(for: claude)
        fixture.fields.caretAtStart = false

        fixture.keys.press(.slash)

        XCTAssertEqual(fixture.keys.typedKeys, [.slash])
        XCTAssertEqual(fixture.inputSources.current, TestInputSources.shuangpin)
    }

    @MainActor
    func testSlashWithEnglishSelectedIsLeftAlone() {
        let fixture = makeClaudeFixture()
        fixture.inputSources.current = TestInputSources.us
        fixture.runtime.applyRuleIfNeeded(for: claude)

        fixture.keys.press(.slash)

        XCTAssertEqual(fixture.keys.typedKeys, [.slash])
        XCTAssertTrue(fixture.inputSources.selectedIDs.isEmpty)
    }

    @MainActor
    func testFailedSwitchTypesTheSlashAnyway() {
        let fixture = makeClaudeFixture()
        fixture.runtime.applyRuleIfNeeded(for: claude)
        fixture.inputSources.selectionResult = false

        fixture.keys.press(.slash)

        XCTAssertEqual(fixture.keys.typedKeys, [.slash])
        XCTAssertEqual(fixture.inputSources.current, TestInputSources.shuangpin)
    }

    @MainActor
    func testReturnSwitchesBack() async {
        let fixture = makeClaudeFixture()
        fixture.runtime.applyRuleIfNeeded(for: claude)
        await startCommand(fixture)

        fixture.keys.press([.printable, .printable, .space, .printable, .tab])
        XCTAssertEqual(fixture.inputSources.current, TestInputSources.us)

        fixture.keys.press(.returnKey)
        XCTAssertEqual(fixture.keys.typedKeys.last, .returnKey)
        await waitUntil { fixture.inputSources.current == TestInputSources.shuangpin }
        XCTAssertEqual(fixture.inputSources.current, TestInputSources.shuangpin)
        XCTAssertEqual(fixture.runtime.switchCount, 2)
    }

    @MainActor
    func testSpaceSwitchesBackWhenTurnedOn() async {
        let fixture = makeClaudeFixture()
        fixture.runtime.slashCommandRestoresOnSpace = true
        fixture.runtime.applyRuleIfNeeded(for: claude)
        await startCommand(fixture)

        fixture.keys.press([.printable, .space])

        await waitUntil { fixture.inputSources.current == TestInputSources.shuangpin }
        XCTAssertEqual(fixture.inputSources.current, TestInputSources.shuangpin)
        XCTAssertEqual(fixture.defaults.bool(forKey: AppRuntime.slashCommandRestoresOnSpaceKey), true)
    }

    @MainActor
    func testDeletingTheSlashSwitchesBack() async {
        let fixture = makeClaudeFixture()
        fixture.runtime.applyRuleIfNeeded(for: claude)
        await startCommand(fixture)

        fixture.keys.press([.printable, .backspace])
        try? await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(fixture.inputSources.current, TestInputSources.us)

        fixture.keys.press(.backspace)
        await waitUntil { fixture.inputSources.current == TestInputSources.shuangpin }
        XCTAssertEqual(fixture.inputSources.current, TestInputSources.shuangpin)
    }

    @MainActor
    func testManualSwitchDuringCommandIsKept() async {
        let fixture = makeClaudeFixture()
        fixture.runtime.applyRuleIfNeeded(for: claude)
        await startCommand(fixture)

        fixture.inputSources.simulateSelection(of: TestInputSources.doubao)
        fixture.keys.press(.returnKey)
        try? await Task.sleep(for: .milliseconds(30))

        XCTAssertEqual(fixture.inputSources.current, TestInputSources.doubao)
    }

    @MainActor
    func testLeavingTheFieldSwitchesBack() async {
        let fixture = makeClaudeFixture()
        fixture.fields.focus(inputField)
        fixture.runtime.applyRuleIfNeeded(for: claude)
        XCTAssertEqual(fixture.fields.observedBundleIdentifier, claude.bundleIdentifier)
        await startCommand(fixture)

        fixture.fields.focus(otherField)

        XCTAssertEqual(fixture.inputSources.current, TestInputSources.shuangpin)
    }

    @MainActor
    func testSwitchingApplicationsSwitchesBack() async {
        let fixture = makeClaudeFixture()
        fixture.runtime.applyRuleIfNeeded(for: claude)
        await startCommand(fixture)

        fixture.runtime.applyRuleIfNeeded(for: notes)

        XCTAssertEqual(fixture.inputSources.current, TestInputSources.shuangpin)
    }

    @MainActor
    func testTerminalGuessesTheStartOfTheLineFromKeys() async {
        let fixture = makeClaudeFixture(apps: [terminal])
        // A terminal reports the caret at the end of its scrollback.
        fixture.fields.caretAtStart = false
        fixture.runtime.applyRuleIfNeeded(for: terminal)

        await startCommand(fixture)
        XCTAssertEqual(fixture.inputSources.current, TestInputSources.us)

        fixture.keys.press(.returnKey)
        await waitUntil { fixture.inputSources.current == TestInputSources.shuangpin }

        fixture.keys.press([.printable, .slash])
        XCTAssertEqual(fixture.inputSources.current, TestInputSources.shuangpin)
    }

    @MainActor
    func testAddingAnApplicationIsSaved() {
        let fixture = makeFixture()

        fixture.runtime.addSlashCommandApp(makeInstalledApplication("Claude", claude.bundleIdentifier))
        fixture.runtime.addSlashCommandApp(makeInstalledApplication("Claude", claude.bundleIdentifier))

        XCTAssertEqual(
            fixture.slashCommandAppStore.apps,
            [SlashCommandApp(bundleIdentifier: claude.bundleIdentifier, applicationName: "Claude")]
        )
        XCTAssertTrue(fixture.keys.isRunning)
    }

    @MainActor
    func testUnreadableListPausesEditing() {
        let fixture = makeFixture()
        fixture.slashCommandAppStore.failLoading(with: FakeRuleStore.Failure(message: "broken"))
        fixture.runtime.reloadRulesFromDisk()

        XCTAssertFalse(fixture.runtime.slashCommandAppEditingEnabled)
        XCTAssertTrue(fixture.runtime.hasStorageFailure)
        XCTAssertEqual(fixture.runtime.storageStatus, .slashCommandAppsReadFailure)

        fixture.runtime.addSlashCommandApp(makeInstalledApplication("Claude", claude.bundleIdentifier))
        XCTAssertTrue(fixture.slashCommandAppStore.apps.isEmpty)
    }
}
