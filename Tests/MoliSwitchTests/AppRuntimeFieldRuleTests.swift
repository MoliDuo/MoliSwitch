import Foundation
import XCTest

import MoliSwitchCore

@testable import MoliSwitchApp

final class AppRuntimeFieldRuleTests: XCTestCase {
    private let wechat = RunningApplicationInfo(bundleIdentifier: "com.tencent.xinWeChat", name: "WeChat")
    private let safari = RunningApplicationInfo(bundleIdentifier: "com.apple.Safari", name: "Safari")

    private let searchField = FieldSignature(
        role: "AXTextField",
        subrole: "AXSearchField",
        descriptor: "搜索",
        ancestorRoles: ["AXGroup", "AXWindow"]
    )
    private let chatField = FieldSignature(role: "AXTextArea", ancestorRoles: ["AXScrollArea", "AXGroup"])
    private let addressBar = FieldSignature(role: "AXTextField", identifier: "WEB_BROWSER_ADDRESS_AND_SEARCH_FIELD")
    private let pageField = FieldSignature(role: "AXTextField", descriptor: "Search", isInWebArea: true)

    @MainActor
    private func searchRule(inputSourceID: String = AppRuntime.englishRuleID) -> FieldRule {
        FieldRule(
            bundleIdentifier: wechat.bundleIdentifier,
            applicationName: wechat.name,
            label: "搜索",
            signature: searchField,
            inputSourceID: inputSourceID,
            inputSourceName: "英文"
        )
    }

    /// WeChat uses Chinese, its search field English.
    @MainActor
    private func makeWeChatFixture(current: InputSource = TestInputSources.shuangpin) -> RuntimeFixture {
        makeFixture(
            rules: [
                makeRule(
                    bundleIdentifier: wechat.bundleIdentifier,
                    applicationName: wechat.name,
                    inputSourceID: AppRuntime.chineseRuleID,
                    inputSourceName: "中文"
                ),
            ],
            fieldRules: [searchRule()],
            sources: [TestInputSources.us, TestInputSources.shuangpin, TestInputSources.doubao],
            current: current
        )
    }

    @MainActor
    private func makeBrowserFixture() -> RuntimeFixture {
        makeFixture(
            sources: [TestInputSources.us, TestInputSources.shuangpin, TestInputSources.doubao],
            current: TestInputSources.shuangpin
        )
    }

    @MainActor
    func testFieldRuleWinsOverTheApplicationRuleAndFallsBackWhenFocusLeaves() async {
        let fixture = makeWeChatFixture()
        fixture.fields.focus(chatField)
        fixture.runtime.applyRuleIfNeeded(for: wechat)

        XCTAssertEqual(fixture.fields.observedBundleIdentifier, wechat.bundleIdentifier)
        XCTAssertEqual(fixture.inputSources.current, TestInputSources.shuangpin)

        fixture.fields.focus(searchField)
        XCTAssertEqual(fixture.inputSources.current, TestInputSources.us)

        fixture.fields.focus(chatField)
        XCTAssertEqual(fixture.inputSources.current, TestInputSources.shuangpin)
    }

    @MainActor
    func testActivatingWithFocusInTheFieldUsesItsRule() async {
        let fixture = makeWeChatFixture()
        fixture.fields.focus(searchField)

        fixture.runtime.applyRuleIfNeeded(for: wechat)

        XCTAssertEqual(fixture.inputSources.current, TestInputSources.us)
    }

    @MainActor
    func testManualSwitchInsideTheSameFieldIsKept() async {
        let fixture = makeWeChatFixture()
        fixture.fields.focus(searchField)
        fixture.runtime.applyRuleIfNeeded(for: wechat)

        fixture.inputSources.current = TestInputSources.shuangpin
        fixture.fields.focus(searchField)

        XCTAssertEqual(fixture.inputSources.current, TestInputSources.shuangpin)
    }

    @MainActor
    func testWithoutAccessibilityTheApplicationRuleApplies() async {
        let fixture = makeWeChatFixture(current: TestInputSources.us)
        fixture.fields.isTrusted = false
        fixture.fields.focus(searchField)

        fixture.runtime.applyRuleIfNeeded(for: wechat)

        XCTAssertNil(fixture.fields.observedBundleIdentifier)
        XCTAssertEqual(fixture.inputSources.current, TestInputSources.shuangpin)
        XCTAssertFalse(fixture.runtime.accessibilityTrusted)
    }

    @MainActor
    func testApplicationsWithoutFieldRulesAreNotObserved() async {
        let fixture = makeWeChatFixture()

        fixture.runtime.applyRuleIfNeeded(
            for: RunningApplicationInfo(bundleIdentifier: "com.apple.Notes", name: "Notes")
        )

        XCTAssertNil(fixture.fields.observedBundleIdentifier)
    }

    @MainActor
    func testAddressBarSwitchesToEnglishAndReturnsToThePreviousInputSource() async {
        let fixture = makeBrowserFixture()
        fixture.fields.focus(pageField)
        fixture.runtime.applyRuleIfNeeded(for: safari)
        XCTAssertEqual(fixture.inputSources.current, TestInputSources.shuangpin)

        fixture.fields.focus(addressBar)
        XCTAssertEqual(fixture.inputSources.current, TestInputSources.us)

        // Safari has no rule of its own, so the page gets back what it had.
        fixture.fields.focus(pageField)
        XCTAssertEqual(fixture.inputSources.current, TestInputSources.shuangpin)
    }

    @MainActor
    func testLeavingTheAddressBarKeepsAManualSwitch() async {
        let fixture = makeBrowserFixture()
        fixture.fields.focus(pageField)
        fixture.runtime.applyRuleIfNeeded(for: safari)
        fixture.fields.focus(addressBar)

        fixture.inputSources.current = TestInputSources.doubao
        fixture.fields.focus(pageField)

        XCTAssertEqual(fixture.inputSources.current, TestInputSources.doubao)
    }

    @MainActor
    func testAddressBarUsesTheChosenInputSourceAndCanBeTurnedOff() async {
        let fixture = makeBrowserFixture()
        fixture.runtime.addressBarInputSourceSelection = TestInputSources.abc.id
        fixture.inputSources.sources.append(TestInputSources.abc)
        fixture.runtime.reloadInputSources()
        fixture.fields.focus(addressBar)
        fixture.runtime.applyRuleIfNeeded(for: safari)
        XCTAssertEqual(fixture.inputSources.current, TestInputSources.abc)
        XCTAssertEqual(
            fixture.defaults.string(forKey: AppRuntime.addressBarInputSourceIDKey),
            TestInputSources.abc.id
        )

        fixture.runtime.addressBarSwitchingEnabled = false
        XCTAssertNil(fixture.fields.observedBundleIdentifier)

        fixture.inputSources.current = TestInputSources.shuangpin
        fixture.runtime.applyRuleIfNeeded(for: safari)
        XCTAssertEqual(fixture.inputSources.current, TestInputSources.shuangpin)
    }

    @MainActor
    func testRememberingTheFocusedFieldSavesTheCurrentInputSourceAsARole() async {
        let fixture = makeBrowserFixture()
        fixture.fields.focus(searchField)
        fixture.runtime.applyRuleIfNeeded(for: wechat)
        fixture.inputSources.current = TestInputSources.us

        XCTAssertEqual(
            fixture.runtime.fieldCaptureState(),
            .ready(applicationName: "WeChat", inputSourceName: "U.S.")
        )
        XCTAssertTrue(fixture.runtime.rememberFocusedField())

        let saved = fixture.fieldStore.rules
        XCTAssertEqual(saved.count, 1)
        XCTAssertEqual(saved.first?.label, "搜索")
        XCTAssertEqual(saved.first?.inputSourceID, AppRuntime.englishRuleID)
        XCTAssertEqual(saved.first?.signature, searchField)
        XCTAssertEqual(fixture.fields.observedBundleIdentifier, wechat.bundleIdentifier)

        // Remembering the same field again replaces its input source.
        fixture.inputSources.current = TestInputSources.doubao
        XCTAssertTrue(fixture.runtime.rememberFocusedField())
        XCTAssertEqual(fixture.fieldStore.rules.count, 1)
        XCTAssertEqual(fixture.fieldStore.rules.first?.inputSourceID, TestInputSources.doubao.id)
        XCTAssertEqual(fixture.inputSources.current, TestInputSources.doubao)
    }

    @MainActor
    func testCaptureStateExplainsWhatIsMissing() async {
        let fixture = makeBrowserFixture()
        fixture.runtime.applyRuleIfNeeded(for: wechat)
        XCTAssertEqual(fixture.runtime.fieldCaptureState(), .noField)

        fixture.fields.isTrusted = false
        XCTAssertEqual(fixture.runtime.fieldCaptureState(), .needsAccessibility)
        XCTAssertFalse(fixture.runtime.rememberFocusedField())
        XCTAssertTrue(fixture.fieldStore.rules.isEmpty)
    }

    @MainActor
    func testEditingAndRemovingAFieldRule() async {
        let fixture = makeWeChatFixture()
        let id = searchRule().id
        let ruleID = fixture.runtime.fieldRuleSet.rules[0].id
        XCTAssertNotEqual(id, ruleID)

        fixture.runtime.setInputSourceID(AppRuntime.chineseRuleID, forFieldRule: ruleID)
        fixture.runtime.renameFieldRule(ruleID, to: "  联系人搜索 ")
        fixture.runtime.renameFieldRule(ruleID, to: " ")

        XCTAssertEqual(fixture.fieldStore.rules.first?.inputSourceID, AppRuntime.chineseRuleID)
        XCTAssertEqual(fixture.fieldStore.rules.first?.label, "联系人搜索")
        XCTAssertEqual(fixture.runtime.fieldRuleGroups.map(\.applicationName), ["WeChat"])

        fixture.runtime.removeFieldRule(ruleID)
        XCTAssertTrue(fixture.fieldStore.rules.isEmpty)
    }

    @MainActor
    func testUnreadableFieldRulesPauseEditing() async {
        let fixture = makeWeChatFixture()
        fixture.fieldStore.failLoading(with: CocoaError(.fileReadCorruptFile))

        fixture.runtime.reloadRulesFromDisk()

        XCTAssertFalse(fixture.runtime.fieldRuleEditingEnabled)
        XCTAssertTrue(fixture.runtime.hasStorageFailure)
        XCTAssertEqual(fixture.runtime.storageStatus, .fieldRulesReadFailure)
        fixture.runtime.removeFieldRule(fixture.runtime.fieldRuleSet.rules[0].id)
        XCTAssertEqual(fixture.fieldStore.rules.count, 1)
    }

    @MainActor
    func testChangingARoleKeepsFieldRulesAndTheAddressBarShownAsIt() async {
        let fixture = makeWeChatFixture()
        fixture.runtime.setInputSourceID(TestInputSources.us.id, forFieldRule: fixture.runtime.fieldRuleSet.rules[0].id)
        fixture.runtime.addressBarInputSourceSelection = TestInputSources.us.id
        XCTAssertEqual(fixture.fieldStore.rules.first?.inputSourceID, TestInputSources.us.id)

        fixture.runtime.englishInputSourceSelection = TestInputSources.shuangpin.id

        XCTAssertEqual(fixture.fieldStore.rules.first?.inputSourceID, AppRuntime.englishRuleID)
        XCTAssertEqual(fixture.fieldStore.rules.first?.inputSourceName, "英文")
        XCTAssertEqual(fixture.runtime.addressBarInputSourceSelection, AppRuntime.englishRuleID)
    }
}
