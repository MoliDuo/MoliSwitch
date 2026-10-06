import Foundation
import XCTest

import MoliSwitchCore

@testable import MoliSwitchApp

final class AppRuntimeRulesTests: XCTestCase {
    private let terminal = makeInstalledApplication("Terminal", "com.apple.Terminal")
    private let safari = makeInstalledApplication("Safari", "com.apple.Safari")

    // MARK: - Loading

    @MainActor
    func testRulesAreLoadedAndEditingIsEnabled() async {
        let fixture = makeFixture(rules: [makeRule(bundleIdentifier: "com.apple.Terminal")])

        XCTAssertEqual(fixture.runtime.ruleSet.rules.count, 1)
        XCTAssertTrue(fixture.runtime.ruleEditingEnabled)
        XCTAssertFalse(fixture.runtime.hasStorageFailure)
        // Cold start loads the rules silently; only a manual reload reports it.
        XCTAssertNil(fixture.runtime.storageStatus)

        fixture.runtime.reloadRulesFromDisk()

        XCTAssertEqual(fixture.runtime.storageStatus, .rulesReloaded)
    }

    @MainActor
    func testDuplicatesFromDiskAreNormalisedToTheFirstRule() async {
        let first = makeRule(
            bundleIdentifier: "com.apple.Terminal",
            inputSourceName: "第一条"
        )
        let second = makeRule(
            bundleIdentifier: "com.apple.Terminal",
            inputSourceName: "第二条"
        )
        let fixture = makeFixture(rules: [first, second])

        XCTAssertEqual(fixture.runtime.ruleSet.rules, [first])
    }

    @MainActor
    func testRuleFileReadFailurePausesEditingAndKeepsInMemoryRules() async {
        let fixture = makeFixture(rules: [makeRule(bundleIdentifier: "com.apple.Terminal")])
        fixture.store.failLoading(with: FakeRuleStore.Failure(message: "unreadable"))

        fixture.runtime.reloadRulesFromDisk()

        XCTAssertFalse(fixture.runtime.ruleEditingEnabled)
        XCTAssertTrue(fixture.runtime.hasStorageFailure)
        XCTAssertEqual(fixture.runtime.storageStatus, .rulesReadFailure)
        XCTAssertEqual(
            fixture.runtime.storageStatus?.text,
            "规则读取失败，已暂停规则编辑；原文件未修改。"
        )
        // The rules already in memory are kept instead of being replaced by an
        // empty set that would then be written back over the file.
        XCTAssertEqual(fixture.runtime.ruleSet.rules.count, 1)
    }

    @MainActor
    func testEditingIsRejectedWhileRulesCannotBeRead() async {
        let fixture = makeFixture(rules: [])
        fixture.store.failLoading(with: FakeRuleStore.Failure(message: "unreadable"))
        fixture.runtime.reloadRulesFromDisk()

        fixture.runtime.setInputSourceID(TestInputSources.us.id, for: terminal)

        XCTAssertEqual(fixture.store.saveCount, 0)
        XCTAssertTrue(fixture.runtime.ruleSet.rules.isEmpty)
        XCTAssertEqual(fixture.runtime.storageStatus, .rulesReadFailure)
    }

    // MARK: - Saving

    @MainActor
    func testSaveFailureLeavesTheVisibleRulesUnchanged() async {
        let fixture = makeFixture(rules: [])
        fixture.store.failSaving(with: FakeRuleStore.Failure(message: "read-only volume"))

        fixture.runtime.setInputSourceID(TestInputSources.us.id, for: terminal)

        XCTAssertEqual(fixture.store.saveCount, 1)
        XCTAssertEqual(fixture.runtime.storageStatus, .rulesSaveFailure)
        XCTAssertEqual(
            fixture.runtime.storageStatus?.text,
            "规则保存失败，修改未生效。"
        )
        XCTAssertTrue(fixture.runtime.ruleSet.rules.isEmpty)
        XCTAssertTrue(fixture.store.rules.isEmpty)
    }

    @MainActor
    func testSuccessfulSavePublishesTheCandidateRules() async {
        let fixture = makeFixture(rules: [])

        fixture.runtime.setInputSourceID(TestInputSources.us.id, for: terminal)

        XCTAssertEqual(fixture.runtime.storageStatus, .rulesSaved)
        XCTAssertEqual(fixture.runtime.ruleSet.rules.count, 1)
        XCTAssertEqual(fixture.runtime.ruleSet.rules.first?.bundleIdentifier, "com.apple.Terminal")
        XCTAssertEqual(fixture.store.rules.map(\.bundleIdentifier), ["com.apple.Terminal"])
    }

    @MainActor
    func testSelectingDefaultRemovesTheRule() async {
        let fixture = makeFixture(rules: [makeRule(bundleIdentifier: "com.apple.Terminal")])

        fixture.runtime.setInputSourceID(
            AppRuntime.followDefaultInputSourceID,
            for: terminal
        )

        XCTAssertTrue(fixture.runtime.ruleSet.rules.isEmpty)
        XCTAssertTrue(fixture.store.rules.isEmpty)
    }

    @MainActor
    func testSelectingAnUnavailableInputSourceIsRejected() async {
        let fixture = makeFixture(rules: [])

        fixture.runtime.setInputSourceID("com.example.missing", for: terminal)

        XCTAssertEqual(fixture.store.saveCount, 0)
        XCTAssertTrue(fixture.runtime.ruleSet.rules.isEmpty)
        XCTAssertEqual(fixture.runtime.inputSourceStatus?.severity, .warning)
    }

    @MainActor
    func testSavedButUnavailableInputSourceStaysSelectableAndUnchanged() async {
        let saved = makeRule(
            bundleIdentifier: "com.apple.Terminal",
            inputSourceID: "com.example.gone",
            inputSourceName: "已卸载的输入法"
        )
        let fixture = makeFixture(rules: [saved])

        let choices = fixture.runtime.inputSourceChoices(for: terminal)

        XCTAssertTrue(
            choices.contains(
                InputSourceChoice(id: "com.example.gone", name: "不可用：已卸载的输入法")
            )
        )
        XCTAssertEqual(fixture.runtime.selectedInputSourceID(for: terminal), "com.example.gone")

        // Re-selecting the saved identifier keeps the existing rule untouched.
        fixture.runtime.setInputSourceID("com.example.gone", for: terminal)

        XCTAssertEqual(fixture.store.saveCount, 0)
        XCTAssertEqual(fixture.runtime.ruleSet.rules, [saved])
    }

    @MainActor
    func testSavedButUnavailableInputSourceWithoutANameFallsBackToItsIdentifier() async {
        let saved = makeRule(
            bundleIdentifier: "com.apple.Terminal",
            inputSourceID: "com.example.gone",
            inputSourceName: "   "
        )
        let fixture = makeFixture(rules: [saved])

        let choices = fixture.runtime.inputSourceChoices(for: terminal)

        XCTAssertTrue(
            choices.contains(
                InputSourceChoice(id: "com.example.gone", name: "不可用：com.example.gone")
            )
        )
    }

    // MARK: - Applications that only exist as rules

    @MainActor
    func testLeftoverRuleStaysVisibleAndRemainsEditable() async {
        let fixture = makeFixture(
            rules: [makeRule(bundleIdentifier: "com.example.ghost", applicationName: "Ghost")],
            installedApplications: [terminal]
        )
        await fixture.scan()

        XCTAssertEqual(
            fixture.runtime.displayApplications.map(\.bundleIdentifier),
            ["com.example.ghost", "com.apple.Terminal"]
        )

        guard
            let ghost = fixture.runtime.displayApplications
                .first(where: { $0.bundleIdentifier == "com.example.ghost" })
        else {
            return XCTFail("The leftover rule is missing from the application list")
        }

        XCTAssertFalse(ghost.isInstalled)
        XCTAssertNil(ghost.url)

        fixture.runtime.setInputSourceID(TestInputSources.abc.id, for: ghost)

        XCTAssertEqual(
            fixture.runtime.ruleSet.rule(forBundleIdentifier: "com.example.ghost")?.inputSourceID,
            TestInputSources.abc.id
        )

        fixture.runtime.setInputSourceID(AppRuntime.followDefaultInputSourceID, for: ghost)

        XCTAssertNil(fixture.runtime.ruleSet.rule(forBundleIdentifier: "com.example.ghost"))
        XCTAssertTrue(fixture.store.rules.isEmpty)
    }

    @MainActor
    func testLeftoverRuleWithoutANameFallsBackToItsBundleIdentifier() async {
        let fixture = makeFixture(
            rules: [
                makeRule(
                    bundleIdentifier: "com.example.ghost",
                    applicationName: "   "
                )
            ],
            installedApplications: []
        )

        XCTAssertEqual(fixture.runtime.displayApplications.first?.name, "com.example.ghost")
    }

    @MainActor
    func testApplicationsWithOnlyFieldRulesAreListedAndConfigured() async {
        let fieldRule = FieldRule(
            bundleIdentifier: "com.tencent.xinWeChat",
            applicationName: "WeChat",
            label: "搜索",
            signature: FieldSignature(role: "AXTextField"),
            inputSourceID: AppRuntime.englishRuleID,
            inputSourceName: "英文"
        )
        let fixture = makeFixture(fieldRules: [fieldRule], installedApplications: [terminal])
        await fixture.scan()

        fixture.runtime.applicationListScope = .configured
        XCTAssertEqual(
            fixture.runtime.filteredInstalledApplications.map(\.bundleIdentifier),
            ["com.tencent.xinWeChat"]
        )
        let wechat = fixture.runtime.filteredInstalledApplications[0]
        XCTAssertEqual(fixture.runtime.fieldRules(for: wechat.bundleIdentifier), [fieldRule])
        XCTAssertEqual(fixture.runtime.extrasSummary(for: wechat), "1 个输入框")
        XCTAssertNil(fixture.runtime.extrasSummary(for: terminal))
    }

    @MainActor
    func testTerminalsWithProgramsAreConfigured() async {
        let fixture = makeFixture(
            commandRules: [CommandRule(command: "claude", inputSourceID: AppRuntime.chineseRuleID, inputSourceName: "中文")],
            installedApplications: [terminal]
        )
        await fixture.scan()

        fixture.runtime.applicationListScope = .configured
        XCTAssertEqual(
            fixture.runtime.filteredInstalledApplications.map(\.bundleIdentifier),
            ["com.apple.Terminal"]
        )
        XCTAssertTrue(fixture.runtime.supportsTerminal(bundleIdentifier: terminal.bundleIdentifier))
        XCTAssertEqual(fixture.runtime.extrasSummary(for: terminal), "1 个终端程序")
    }

    @MainActor
    func testScopeFilteringUsesInstalledStateForLeftoverRules() async {
        let fixture = makeFixture(
            rules: [makeRule(bundleIdentifier: "com.example.ghost", applicationName: "Ghost")],
            installedApplications: [terminal]
        )
        await fixture.scan()

        fixture.runtime.applicationListScope = .unconfigured
        XCTAssertEqual(
            fixture.runtime.filteredInstalledApplications.map(\.bundleIdentifier),
            ["com.apple.Terminal"]
        )

        fixture.runtime.applicationListScope = .configured
        XCTAssertEqual(
            fixture.runtime.filteredInstalledApplications.map(\.bundleIdentifier),
            ["com.example.ghost"]
        )

        fixture.runtime.applicationListScope = .all
        XCTAssertEqual(
            fixture.runtime.filteredInstalledApplications.map(\.bundleIdentifier),
            ["com.example.ghost", "com.apple.Terminal"]
        )
    }

    // MARK: - Preferences

    @MainActor
    func testMenuBarIconPreferenceIsPersisted() async {
        let fixture = makeFixture()

        XCTAssertTrue(fixture.runtime.showMenuBarIcon)

        fixture.runtime.showMenuBarIcon = false

        XCTAssertEqual(
            fixture.defaults.object(forKey: AppRuntime.showMenuBarIconKey) as? Bool,
            false
        )

        let reloaded = UserDefaults(suiteName: fixture.suiteName)
        XCTAssertEqual(
            reloaded?.object(forKey: AppRuntime.showMenuBarIconKey) as? Bool,
            false
        )
    }

    // MARK: - Launch at login

    @MainActor
    func testLaunchAtLoginWaitingForApprovalIsNotRegisteredAgain() async {
        let fixture = makeFixture()
        fixture.loginItems.status = .requiresApproval
        fixture.runtime.refreshLaunchAtLoginStatus()

        fixture.runtime.setLaunchAtLoginEnabled(true)

        XCTAssertEqual(fixture.loginItems.registerCount, 0)
        XCTAssertEqual(fixture.runtime.launchAtLoginStatus, .requiresApproval)
        XCTAssertEqual(fixture.runtime.loginStatus?.severity, .warning)
        XCTAssertFalse(fixture.runtime.isLaunchAtLoginEnabled)
    }

    @MainActor
    func testLaunchAtLoginCanBeUnregisteredWhileWaitingForApproval() async {
        let fixture = makeFixture()
        fixture.loginItems.status = .requiresApproval
        fixture.runtime.refreshLaunchAtLoginStatus()

        fixture.runtime.setLaunchAtLoginEnabled(false)

        XCTAssertEqual(fixture.loginItems.unregisterCount, 1)
        XCTAssertEqual(fixture.runtime.launchAtLoginStatus, .notRegistered)
    }

    @MainActor
    func testLaunchAtLoginRegistrationFailureIsReported() async {
        let fixture = makeFixture()
        fixture.loginItems.registerError = FakeRuleStore.Failure(message: "denied")

        fixture.runtime.setLaunchAtLoginEnabled(true)

        XCTAssertEqual(fixture.loginItems.registerCount, 1)
        XCTAssertEqual(fixture.runtime.loginStatus?.severity, .error)
    }

    @MainActor
    func testLaunchAtLoginSystemSettingsEntryIsAvailable() async {
        let fixture = makeFixture()

        fixture.runtime.openLoginItemsSystemSettings()

        XCTAssertEqual(fixture.loginItems.openSystemSettingsCount, 1)
    }

    // MARK: - Lifecycle

    @MainActor
    func testStopIsIdempotent() async {
        let fixture = makeFixture()

        fixture.runtime.stop()
        fixture.runtime.stop()

        XCTAssertEqual(fixture.inputSources.stopMonitoringCount, 1)
    }

    @MainActor
    func testStopCancelsAnInFlightScanWithoutPublishingIt() async {
        let fixture = makeFixture(installedApplications: [terminal], scanDelay: 0.3)

        fixture.runtime.refreshApplications()
        XCTAssertTrue(fixture.runtime.isScanning)

        fixture.runtime.stop()
        XCTAssertFalse(fixture.runtime.isScanning)

        // Wait long enough for the detached scan to finish on its own.
        try? await Task.sleep(for: .milliseconds(500))

        XCTAssertEqual(fixture.scanner.scanCount, 1)
        XCTAssertTrue(fixture.runtime.installedApplications.isEmpty)
    }

    // MARK: - Status line

    @MainActor
    func testStorageErrorIsNotClearedByUnrelatedActivity() async {
        let fixture = makeFixture(
            rules: [],
            installedApplications: [terminal]
        )
        fixture.store.failSaving(with: FakeRuleStore.Failure(message: "read-only volume"))
        fixture.runtime.setInputSourceID(TestInputSources.us.id, for: terminal)

        fixture.runtime.refreshApplications()
        await waitUntil { !fixture.runtime.isScanning }

        XCTAssertEqual(fixture.runtime.storageStatus, .rulesSaveFailure)
        XCTAssertEqual(fixture.runtime.primaryStatus, .rulesSaveFailure)

        // A later successful save clears only the storage entry.
        fixture.store.failSaving(with: nil)
        fixture.runtime.setInputSourceID(TestInputSources.abc.id, for: terminal)

        XCTAssertEqual(fixture.runtime.storageStatus, .rulesSaved)
        XCTAssertEqual(fixture.runtime.primaryStatus, .rulesSaved)
        XCTAssertEqual(fixture.runtime.primaryStatus?.severity, .info)
    }

    @MainActor
    func testStatusTextFallsBackToTheVisibleApplicationCount() async {
        let fixture = makeFixture(installedApplications: [terminal, safari])

        fixture.runtime.refreshApplications()
        await waitUntil { !fixture.runtime.isScanning }

        XCTAssertEqual(fixture.runtime.statusText, "显示 2 个应用")
    }
}
