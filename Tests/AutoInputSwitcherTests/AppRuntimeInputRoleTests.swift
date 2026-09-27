import Foundation
import XCTest

import AutoInputSwitcherCore

@testable import AutoInputSwitcherApp

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
    func testRolesAreDetectedAutomatically() async {
        let fixture = makeRoleFixture()

        XCTAssertEqual(fixture.runtime.effectiveChineseInputSource, TestInputSources.shuangpin)
        XCTAssertEqual(fixture.runtime.effectiveEnglishInputSource, TestInputSources.us)
        XCTAssertEqual(fixture.runtime.effectiveVoiceInputSource, TestInputSources.doubao)
        XCTAssertEqual(
            fixture.runtime.ruleRoleChoices.map(\.name),
            ["中文（Shuangpin – Simplified）", "英文（U.S.）"]
        )
        // Every input source is covered by a role, so nothing else is offered.
        XCTAssertEqual(fixture.runtime.inputSourceChoices(for: terminal), [])
    }

    @MainActor
    func testRoleRuleSwitchesToTheRoleInputSource() async {
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
    func testRuleNamingTheRoleInputSourceIsShownAsTheRole() async {
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
    func testChangingARoleKeepsRulesThatWereShownAsIt() async {
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
    func testMissingRoleInputSourceReportsAWarning() async {
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
