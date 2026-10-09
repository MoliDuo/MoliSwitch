import Foundation
import MoliSwitchCore
import XCTest
@testable import MoliSwitchApp

final class AppRuntimeInputRoleTests: XCTestCase {
    private let terminal = makeInstalledApplication("Terminal", "com.apple.Terminal")

    @MainActor
    private func makeRoleFixture(rules: [AppRule] = []) -> RuntimeFixture {
        makeFixture(
            rules: rules,
            sources: [TestInputSources.us, TestInputSources.shuangpin, TestInputSources.doubao],
            current: TestInputSources.shuangpin
        )
    }

    @MainActor
    private func activateTerminal(in fixture: RuntimeFixture) {
        fixture.runtime.applyRuleIfNeeded(
            for: RunningApplicationInfo(bundleIdentifier: "com.apple.Terminal", name: "Terminal")
        )
    }

    @MainActor
    func testRolesAreDetectedAutomatically() {
        let fixture = makeRoleFixture()

        XCTAssertEqual(fixture.runtime.effectiveChineseInputSource, TestInputSources.shuangpin)
        XCTAssertEqual(fixture.runtime.effectiveEnglishInputSource, TestInputSources.us)
        XCTAssertEqual(
            fixture.runtime.ruleRoleChoices.map(\.name),
            ["中文（Shuangpin – Simplified）", "英文（U.S.）"]
        )
        // Input sources that no role covers are offered on their own.
        XCTAssertEqual(
            fixture.runtime.inputSourceChoices(for: terminal).map(\.id),
            [TestInputSources.doubao.id]
        )
    }

    @MainActor
    func testExternalSwitchUpdatesTheCurrentInputSource() {
        let fixture = makeRoleFixture()
        fixture.runtime.start()
        defer { fixture.runtime.stop() }

        fixture.inputSources.simulateSelection(of: TestInputSources.doubao)
        XCTAssertEqual(fixture.runtime.currentInputSource, TestInputSources.doubao)
    }

    @MainActor
    func testRoleRuleSwitchesToTheRoleInputSource() {
        let fixture = makeRoleFixture()

        fixture.runtime.setInputSourceID(AppRuntime.englishRuleID, for: terminal)
        XCTAssertEqual(fixture.store.rules.first?.inputSourceID, AppRuntime.englishRuleID)
        XCTAssertEqual(fixture.store.rules.first?.inputSourceName, "英文")

        activateTerminal(in: fixture)
        XCTAssertEqual(fixture.inputSources.current, TestInputSources.us)
        XCTAssertEqual(fixture.runtime.switchCount, 1)

        // The rule follows the setting instead of a fixed input source.
        fixture.runtime.englishInputSourceSelection = TestInputSources.shuangpin.id
        activateTerminal(in: fixture)
        XCTAssertEqual(fixture.inputSources.current, TestInputSources.shuangpin)
    }

    @MainActor
    func testRuleNamingTheRoleInputSourceIsShownAsTheRole() {
        let fixture = makeRoleFixture(rules: [
            makeRule(
                bundleIdentifier: "com.apple.Terminal",
                inputSourceID: TestInputSources.shuangpin.id,
                inputSourceName: TestInputSources.shuangpin.name
            ),
        ])

        XCTAssertEqual(fixture.runtime.selectedInputSourceID(for: terminal), AppRuntime.chineseRuleID)
        XCTAssertEqual(fixture.store.saveCount, 0)
    }

    @MainActor
    func testChangingARoleKeepsRulesThatWereShownAsIt() {
        let fixture = makeRoleFixture(rules: [
            makeRule(
                bundleIdentifier: "com.apple.Terminal",
                inputSourceID: TestInputSources.us.id,
                inputSourceName: TestInputSources.us.name
            ),
        ])

        fixture.runtime.englishInputSourceSelection = TestInputSources.shuangpin.id

        XCTAssertEqual(fixture.store.rules.first?.inputSourceID, AppRuntime.englishRuleID)
        XCTAssertEqual(fixture.runtime.selectedInputSourceID(for: terminal), AppRuntime.englishRuleID)
        XCTAssertEqual(
            fixture.defaults.string(forKey: AppRuntime.englishInputSourceIDKey),
            TestInputSources.shuangpin.id
        )
    }

    @MainActor
    func testMissingRoleInputSourceReportsAWarning() {
        let fixture = makeFixture(
            rules: [
                makeRule(
                    bundleIdentifier: "com.apple.Terminal",
                    inputSourceID: AppRuntime.chineseRuleID,
                    inputSourceName: "中文"
                ),
            ],
            current: TestInputSources.us
        )

        XCTAssertNil(fixture.runtime.effectiveChineseInputSource)

        activateTerminal(in: fixture)

        XCTAssertEqual(fixture.inputSources.current, TestInputSources.us)
        XCTAssertEqual(fixture.inputSources.selectRequestCount, 0)
        XCTAssertEqual(fixture.runtime.inputSourceStatus?.severity, .warning)
        XCTAssertEqual(fixture.runtime.ruleRoleChoices.first?.name, "中文（未设置）")
    }
}

final class ChineseInputSourceDetectionTests: XCTestCase {
    private let wetype = InputSource(id: "com.tencent.inputmethod.wetype.pinyin", name: "微信输入法")
    private let sogou = InputSource(id: "com.sogou.inputmethod.sogou.pinyin", name: "搜狗拼音")

    @MainActor
    func testAppleChineseInputMethodIsPreferredOverThirdPartyOnes() {
        // Third-party names sort before "Shuangpin", which used to decide the result.
        let fixture = makeFixture(
            sources: [TestInputSources.us, TestInputSources.shuangpin, wetype, sogou],
            current: TestInputSources.us
        )

        XCTAssertEqual(fixture.runtime.detectedChineseInputSource, TestInputSources.shuangpin)
    }

    @MainActor
    func testThirdPartyInputMethodIsDetectedWithoutAnAppleOne() {
        let fixture = makeFixture(
            sources: [TestInputSources.us, wetype],
            current: TestInputSources.us
        )

        XCTAssertEqual(fixture.runtime.detectedChineseInputSource, wetype)

        fixture.runtime.setInputSourceID(
            AppRuntime.chineseRuleID,
            for: makeInstalledApplication("Terminal", "com.apple.Terminal")
        )
        fixture.runtime.applyRuleIfNeeded(
            for: RunningApplicationInfo(bundleIdentifier: "com.apple.Terminal", name: "Terminal")
        )

        XCTAssertEqual(fixture.inputSources.current, wetype)
    }

    @MainActor
    func testRejectedSwitchIsReported() {
        let fixture = makeFixture(
            rules: [
                makeRule(
                    bundleIdentifier: "com.apple.Terminal",
                    inputSourceID: TestInputSources.abc.id,
                    inputSourceName: TestInputSources.abc.name
                ),
            ],
            current: TestInputSources.us
        )
        fixture.inputSources.selectionResult = false

        fixture.runtime.applyRuleIfNeeded(
            for: RunningApplicationInfo(bundleIdentifier: "com.apple.Terminal", name: "Terminal")
        )

        XCTAssertEqual(fixture.inputSources.current, TestInputSources.us)
        XCTAssertEqual(fixture.runtime.inputSourceStatus?.severity, .warning)
        XCTAssertEqual(fixture.runtime.switchCount, 0)
    }
}
