import Foundation
import XCTest

import AutoInputSwitcherCore

@testable import AutoInputSwitcherApp

final class AppRuntimeDefaultInputSourceTests: XCTestCase {
    private let terminal = makeInstalledApplication("Terminal", "com.apple.Terminal")

    @MainActor
    private func makeDefaultFixture(rules: [AppRule] = []) -> RuntimeFixture {
        makeFixture(
            rules: rules,
            sources: [TestInputSources.us, TestInputSources.shuangpin],
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
    func testDefaultIsNoSwitchSoApplicationsWithoutARuleAreLeftAlone() async {
        let fixture = makeDefaultFixture()

        XCTAssertEqual(fixture.runtime.defaultInputSourceSelection, AppRuntime.noSwitchInputSourceID)
        XCTAssertEqual(fixture.runtime.followDefaultChoiceTitle, "默认（不切换）")

        activateTerminal(in: fixture)

        XCTAssertEqual(fixture.inputSources.selectRequestCount, 0)
        XCTAssertEqual(fixture.inputSources.current, TestInputSources.shuangpin)
    }

    @MainActor
    func testApplicationWithoutARuleSwitchesToTheDefaultRole() async {
        let fixture = makeDefaultFixture()
        fixture.runtime.defaultInputSourceSelection = AppRuntime.englishRuleID

        XCTAssertEqual(fixture.runtime.followDefaultChoiceTitle, "默认（英文）")
        XCTAssertEqual(
            fixture.defaults.string(forKey: AppRuntime.defaultInputSourceIDKey),
            AppRuntime.englishRuleID
        )

        activateTerminal(in: fixture)

        XCTAssertEqual(fixture.inputSources.current, TestInputSources.us)
        XCTAssertEqual(fixture.runtime.switchCount, 1)
    }

    @MainActor
    func testApplicationWithoutARuleSwitchesToTheDefaultInputSource() async {
        let fixture = makeFixture(current: TestInputSources.us)
        fixture.runtime.defaultInputSourceSelection = TestInputSources.abc.id

        XCTAssertEqual(fixture.runtime.followDefaultChoiceTitle, "默认（ABC）")

        activateTerminal(in: fixture)

        XCTAssertEqual(fixture.inputSources.current, TestInputSources.abc)
    }

    @MainActor
    func testApplicationRuleWinsOverTheDefault() async {
        let fixture = makeDefaultFixture(rules: [
            makeRule(
                bundleIdentifier: "com.apple.Terminal",
                inputSourceID: TestInputSources.shuangpin.id,
                inputSourceName: TestInputSources.shuangpin.name
            ),
        ])
        fixture.inputSources.current = TestInputSources.us
        fixture.runtime.defaultInputSourceSelection = AppRuntime.englishRuleID

        activateTerminal(in: fixture)

        XCTAssertEqual(fixture.inputSources.current, TestInputSources.shuangpin)
    }

    @MainActor
    func testNoSwitchRuleIsStoredAndKeepsTheDefaultAway() async {
        let fixture = makeDefaultFixture()
        fixture.runtime.defaultInputSourceSelection = AppRuntime.englishRuleID

        fixture.runtime.setInputSourceID(AppRuntime.noSwitchInputSourceID, for: terminal)

        XCTAssertEqual(fixture.store.rules.first?.inputSourceID, AppRuntime.noSwitchInputSourceID)
        XCTAssertEqual(fixture.store.rules.first?.inputSourceName, "不切换")
        XCTAssertEqual(
            fixture.runtime.selectedInputSourceID(for: terminal),
            AppRuntime.noSwitchInputSourceID
        )
        XCTAssertFalse(
            fixture.runtime.inputSourceChoices(for: terminal)
                .contains { $0.id == AppRuntime.noSwitchInputSourceID }
        )

        activateTerminal(in: fixture)

        XCTAssertEqual(fixture.inputSources.selectRequestCount, 0)
        XCTAssertEqual(fixture.inputSources.current, TestInputSources.shuangpin)
    }

    @MainActor
    func testFollowingTheDefaultRemovesTheNoSwitchRule() async {
        let fixture = makeDefaultFixture(rules: [
            makeRule(
                bundleIdentifier: "com.apple.Terminal",
                inputSourceID: AppRuntime.noSwitchInputSourceID,
                inputSourceName: "不切换"
            ),
        ])

        fixture.runtime.setInputSourceID(AppRuntime.followDefaultInputSourceID, for: terminal)

        XCTAssertTrue(fixture.store.rules.isEmpty)
        XCTAssertEqual(
            fixture.runtime.selectedInputSourceID(for: terminal),
            AppRuntime.followDefaultInputSourceID
        )
    }

    @MainActor
    func testChangingARoleKeepsTheDefaultThatWasShownAsIt() async {
        let fixture = makeDefaultFixture()
        fixture.runtime.defaultInputSourceSelection = TestInputSources.us.id

        fixture.runtime.englishInputSourceSelection = TestInputSources.shuangpin.id

        XCTAssertEqual(fixture.runtime.defaultInputSourceSelection, AppRuntime.englishRuleID)
    }

    @MainActor
    func testSwitchingBackToNoSwitchClearsTheStoredDefault() async {
        let fixture = makeDefaultFixture()
        fixture.runtime.defaultInputSourceSelection = AppRuntime.chineseRuleID

        fixture.runtime.defaultInputSourceSelection = AppRuntime.noSwitchInputSourceID

        XCTAssertNil(fixture.defaults.string(forKey: AppRuntime.defaultInputSourceIDKey))
    }
}
