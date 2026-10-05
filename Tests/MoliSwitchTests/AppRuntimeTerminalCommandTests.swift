import Foundation
import XCTest

import MoliSwitchCore

@testable import MoliSwitchApp

final class AppRuntimeTerminalCommandTests: XCTestCase {
    private let terminalApp = RunningApplicationInfo(bundleIdentifier: "com.apple.Terminal", name: "Terminal")

    /// Terminal uses English, claude uses Chinese and vim uses English.
    @MainActor
    private func makeTerminalFixture(current: InputSource = TestInputSources.us) -> RuntimeFixture {
        makeFixture(
            rules: [
                makeRule(
                    bundleIdentifier: "com.apple.Terminal",
                    inputSourceID: AppRuntime.englishRuleID,
                    inputSourceName: "英文"
                ),
            ],
            commandRules: [
                CommandRule(command: "claude", inputSourceID: AppRuntime.chineseRuleID, inputSourceName: "中文"),
                CommandRule(command: "vim", inputSourceID: AppRuntime.englishRuleID, inputSourceName: "英文"),
            ],
            sources: [TestInputSources.us, TestInputSources.shuangpin, TestInputSources.doubao],
            current: current
        )
    }

    @MainActor
    private func waitForPolls(_ fixture: RuntimeFixture, count: Int = 3) async {
        let target = fixture.terminal.queryCount + count
        await waitUntil { fixture.terminal.queryCount >= target }
    }

    @MainActor
    func testProgramInTheTerminalSwitchesAndFallsBackToTheAppRule() async {
        let fixture = makeTerminalFixture()
        defer { fixture.runtime.stop() }
        fixture.terminal.run(["zsh"])

        fixture.runtime.applyRuleIfNeeded(for: terminalApp)
        XCTAssertEqual(fixture.inputSources.current, TestInputSources.us)

        fixture.terminal.run(["claude", "2.1.3"])
        await waitUntil { fixture.inputSources.current == TestInputSources.shuangpin }
        XCTAssertEqual(fixture.inputSources.current, TestInputSources.shuangpin)
        XCTAssertEqual(fixture.runtime.lastTerminalContext?.displayName, "claude")

        fixture.terminal.run(["zsh"])
        await waitUntil { fixture.inputSources.current == TestInputSources.us }
        XCTAssertEqual(fixture.inputSources.current, TestInputSources.us)
    }

    /// Over ssh the program named in the title comes first, and ssh's own
    /// rule is used when the title names none.
    @MainActor
    func testProgramOverSSHIsFoundByTheTitle() async {
        let fixture = makeTerminalFixture()
        defer { fixture.runtime.stop() }
        fixture.terminal.result = .found(
            TerminalContext(tty: "/dev/ttys001", candidates: ["claude", "ssh"], remoteTitle: "✳ Claude Code")
        )

        fixture.runtime.applyRuleIfNeeded(for: terminalApp)
        XCTAssertEqual(fixture.inputSources.current, TestInputSources.shuangpin)
        XCTAssertEqual(fixture.runtime.lastTerminalContext?.displayName, "claude（ssh）")

        fixture.terminal.result = .found(
            TerminalContext(tty: "/dev/ttys001", candidates: ["ssh"], remoteTitle: "me@host: ~")
        )
        await waitUntil { fixture.inputSources.current == TestInputSources.us }
        XCTAssertEqual(fixture.inputSources.current, TestInputSources.us)
    }

    @MainActor
    func testActivatingTheTerminalUsesTheProgramInTheActiveTab() async {
        let fixture = makeTerminalFixture()
        defer { fixture.runtime.stop() }
        fixture.terminal.run(["claude"])

        fixture.runtime.applyRuleIfNeeded(for: terminalApp)
        XCTAssertEqual(fixture.inputSources.current, TestInputSources.shuangpin)
    }

    @MainActor
    func testManualSwitchInsideTheSameProgramIsKept() async {
        let fixture = makeTerminalFixture()
        defer { fixture.runtime.stop() }
        fixture.terminal.run(["claude"])
        fixture.runtime.applyRuleIfNeeded(for: terminalApp)
        XCTAssertEqual(fixture.inputSources.current, TestInputSources.shuangpin)

        // Caps Lock back to English while claude keeps running.
        fixture.inputSources.current = TestInputSources.us
        await waitForPolls(fixture)
        XCTAssertEqual(fixture.inputSources.current, TestInputSources.us)
    }

    @MainActor
    func testAnotherTabReappliesTheRule() async {
        let fixture = makeTerminalFixture()
        defer { fixture.runtime.stop() }
        fixture.terminal.run(["claude"], tty: "/dev/ttys001")
        fixture.runtime.applyRuleIfNeeded(for: terminalApp)
        fixture.inputSources.current = TestInputSources.us

        fixture.terminal.run(["claude"], tty: "/dev/ttys002")
        await waitUntil { fixture.inputSources.current == TestInputSources.shuangpin }
        XCTAssertEqual(fixture.inputSources.current, TestInputSources.shuangpin)
    }

    @MainActor
    func testUnavailableContextKeepsTheCurrentRule() async {
        let fixture = makeTerminalFixture()
        defer { fixture.runtime.stop() }
        fixture.terminal.run(["claude"])
        fixture.runtime.applyRuleIfNeeded(for: terminalApp)

        fixture.terminal.result = .unavailable
        await waitForPolls(fixture)
        XCTAssertEqual(fixture.inputSources.current, TestInputSources.shuangpin)
    }

    @MainActor
    func testDeniedAccessFallsBackToTheAppRule() async {
        let fixture = makeTerminalFixture()
        defer { fixture.runtime.stop() }
        fixture.terminal.result = .denied

        fixture.runtime.applyRuleIfNeeded(for: terminalApp)
        XCTAssertEqual(fixture.inputSources.current, TestInputSources.us)
        XCTAssertTrue(fixture.runtime.terminalAccessDenied)
    }

    @MainActor
    func testDisabledSwitchingIgnoresTheTerminal() async {
        let fixture = makeTerminalFixture()
        defer { fixture.runtime.stop() }
        fixture.runtime.terminalSwitchingEnabled = false
        fixture.terminal.run(["claude"])

        fixture.runtime.applyRuleIfNeeded(for: terminalApp)
        await waitForPolls(fixture, count: 0)
        try? await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(fixture.inputSources.current, TestInputSources.us)
        XCTAssertEqual(fixture.terminal.queryCount, 0)
    }

    @MainActor
    func testTerminalIsNotReadWithoutCommandRules() async {
        let fixture = makeFixture(
            sources: [TestInputSources.us, TestInputSources.shuangpin],
            current: TestInputSources.us
        )
        defer { fixture.runtime.stop() }
        fixture.terminal.run(["claude"])

        fixture.runtime.applyRuleIfNeeded(for: terminalApp)
        try? await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(fixture.terminal.queryCount, 0)
    }

    @MainActor
    func testOtherApplicationsAreNotRead() async {
        let fixture = makeTerminalFixture()
        defer { fixture.runtime.stop() }
        fixture.terminal.run(["claude"])

        fixture.runtime.applyRuleIfNeeded(
            for: RunningApplicationInfo(bundleIdentifier: "com.apple.Safari", name: "Safari")
        )
        try? await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(fixture.terminal.queryCount, 0)
    }

    @MainActor
    func testAddingEditingAndRemovingCommandRules() async {
        let fixture = makeFixture(sources: [TestInputSources.us, TestInputSources.shuangpin])

        XCTAssertTrue(fixture.runtime.addCommandRule("  /usr/local/bin/codex "))
        XCTAssertEqual(fixture.commandStore.rules.map(\.command), ["codex"])
        XCTAssertEqual(fixture.commandStore.rules.first?.inputSourceID, AppRuntime.chineseRuleID)
        XCTAssertFalse(fixture.runtime.addCommandRule("Codex"))
        XCTAssertFalse(fixture.runtime.addCommandRule("   "))

        fixture.runtime.setInputSourceID(AppRuntime.englishRuleID, forCommand: "codex")
        XCTAssertEqual(fixture.commandStore.rules.first?.inputSourceID, AppRuntime.englishRuleID)
        XCTAssertEqual(fixture.runtime.selectedInputSourceID(for: fixture.runtime.commandRuleSet.rules[0]), AppRuntime.englishRuleID)

        fixture.runtime.removeCommandRule("CODEX")
        XCTAssertEqual(fixture.commandStore.rules, [])
    }

    @MainActor
    func testUnreadableCommandRulesPauseEditing() async {
        let fixture = makeFixture()
        fixture.commandStore.failLoading(with: FakeRuleStore.Failure(message: "broken"))

        fixture.runtime.reloadRulesFromDisk()
        XCTAssertFalse(fixture.runtime.commandRuleEditingEnabled)
        XCTAssertTrue(fixture.runtime.hasStorageFailure)
        XCTAssertEqual(fixture.runtime.storageStatus, .commandRulesReadFailure)
        XCTAssertFalse(fixture.runtime.addCommandRule("claude"))
    }
}
