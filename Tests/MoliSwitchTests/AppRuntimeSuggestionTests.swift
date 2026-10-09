import Foundation
import MoliSwitchCore
import XCTest
@testable import MoliSwitchApp

final class AppRuntimeSuggestionTests: XCTestCase {
    private let app = "com.apple.Notes"

    private let us = "com.apple.keylayout.US"
    private let abc = "com.apple.keylayout.ABC"
    private let chinese = "com.apple.inputmethod.SCIM.Shuangpin"

    private func letter(_ app: String, source: String, mono: Double) -> String {
        "{\"app\":\"\(app)\",\"category\":\"letter\",\"current\":\"\(source)\",\"e\":\"key\","
            + "\"key\":\"printable\",\"keyCode\":0,\"mono\":\(mono),\"shifted\":false}"
    }

    /// Visits where the user picks ABC as soon as the application is active.
    private func correctedVisits(_ app: String, name: String, terminal: String? = nil) -> [String] {
        let context = terminal.map { "{\"candidates\":[\"\($0)\"],\"tty\":\"/dev/ttys001\"}" } ?? "null"
        return (0..<9).flatMap { index -> [String] in
            let start = Double(index) * 100_000
            return [
                "{\"app\":\"\(app)\",\"appName\":\"\(name)\",\"e\":\"appFocus\","
                    + "\"mono\":\(start),\"terminal\":\(context)}",
                "{\"app\":\"\(app)\",\"e\":\"manualSwitch\",\"from\":\"\(us)\","
                    + "\"mono\":\(start + 500),\"to\":\"\(abc)\"}",
            ] + (0..<5).map { letter(app, source: abc, mono: start + 1000 + Double($0) * 100) }
        }
    }

    private var lines: [String] {
        correctedVisits(app, name: "Notes")
    }

    /// Shift + / typed in Chinese, deleted, and typed again, in each application.
    private func retypedSlash(in apps: [String]) -> [String] {
        apps.enumerated().flatMap { index, app -> [String] in
            let start = Double(index) * 100_000
            func slash(_ mono: Double) -> String {
                "{\"app\":\"\(app)\",\"category\":\"symbol\",\"current\":\"\(chinese)\",\"e\":\"key\","
                    + "\"key\":\"printable\",\"keyCode\":44,\"mono\":\(mono),\"shift\":\"pass\",\"shifted\":true}"
            }
            return [
                "{\"app\":\"\(app)\",\"appName\":\"Notes\",\"e\":\"appFocus\",\"mono\":\(start),\"terminal\":null}",
                slash(start + 1000),
                "{\"app\":\"\(app)\",\"category\":null,\"current\":\"\(chinese)\",\"e\":\"key\","
                    + "\"key\":\"backspace\",\"keyCode\":51,\"mono\":\(start + 1500),\"shifted\":false}",
                slash(start + 2000),
            ]
        }
    }

    private let lettersOnly: [String: Any] = [
        "shiftEnglishEnabled": true,
        "shiftEnglishKeyCodes": ShiftKey.keyCodes(in: .letter).sorted(),
    ]

    @MainActor
    func testApplyAndUndoCommandRule() async {
        let fixture = makeFixture(suggestionLines: correctedVisits(
            "com.googlecode.iterm2",
            name: "iTerm2",
            terminal: "claude"
        ))
        let runtime = fixture.runtime

        await runtime.refreshSuggestions()
        XCTAssertEqual(runtime.suggestions.map(\.action), [.setCommandRule(command: "claude", inputSourceID: abc)])

        XCTAssertTrue(runtime.applySuggestion(runtime.suggestions[0]))
        XCTAssertEqual(fixture.commandStore.rules.map(\.command), ["claude"])
        XCTAssertEqual(fixture.commandStore.rules.first?.inputSourceID, abc)
        XCTAssertTrue(fixture.store.rules.isEmpty)

        runtime.undoSuggestion(runtime.appliedSuggestions[0])
        XCTAssertTrue(fixture.commandStore.rules.isEmpty)
    }

    @MainActor
    func testUndoRestoresPreviousCommandRule() async {
        let previous = CommandRule(command: "claude", inputSourceID: us, inputSourceName: "U.S.")
        let fixture = makeFixture(
            commandRules: [previous],
            suggestionLines: correctedVisits("com.googlecode.iterm2", name: "iTerm2", terminal: "claude")
        )
        let runtime = fixture.runtime

        await runtime.refreshSuggestions()
        XCTAssertTrue(runtime.applySuggestion(runtime.suggestions[0]))
        XCTAssertEqual(fixture.commandStore.rules.first?.inputSourceID, abc)

        runtime.undoSuggestion(runtime.appliedSuggestions[0])
        XCTAssertEqual(fixture.commandStore.rules, [previous])
    }

    @MainActor
    func testApplyAndUndoShiftKeyForOneApplication() async {
        let fixture = makeFixture(defaultsValues: lettersOnly, suggestionLines: retypedSlash(in: [app, app, app, app]))
        let runtime = fixture.runtime

        await runtime.refreshSuggestions()
        XCTAssertEqual(
            runtime.suggestions.map(\.action),
            [.setShiftKey(bundleIdentifier: app, applicationName: "Notes", keyCode: 44, enabled: true)]
        )

        XCTAssertTrue(runtime.applySuggestion(runtime.suggestions[0]))
        let own = runtime.shiftAppRules.rule(for: app)?.options
        XCTAssertEqual(own?.keyCodes, ShiftKey.keyCodes(in: .letter).union([44]))
        XCTAssertEqual(fixture.shiftAppRuleStore.rules.count, 1)
        // Everywhere else is as before.
        XCTAssertEqual(runtime.shiftEnglishKeyCodes, ShiftKey.keyCodes(in: .letter))

        runtime.undoSuggestion(runtime.appliedSuggestions[0])
        XCTAssertTrue(runtime.shiftAppRules.rules.isEmpty)
        XCTAssertTrue(fixture.shiftAppRuleStore.rules.isEmpty)
    }

    @MainActor
    func testApplyAndUndoShiftKeyEverywhere() async {
        let fixture = makeFixture(
            defaultsValues: lettersOnly,
            suggestionLines: retypedSlash(in: ["a.one", "a.two", "a.three", "a.four"])
        )
        let runtime = fixture.runtime

        await runtime.refreshSuggestions()
        XCTAssertEqual(
            runtime.suggestions.map(\.action),
            [.setShiftKey(bundleIdentifier: nil, applicationName: nil, keyCode: 44, enabled: true)]
        )

        XCTAssertTrue(runtime.applySuggestion(runtime.suggestions[0]))
        XCTAssertEqual(runtime.shiftEnglishKeyCodes, ShiftKey.keyCodes(in: .letter).union([44]))
        XCTAssertTrue(runtime.shiftAppRules.rules.isEmpty)

        runtime.undoSuggestion(runtime.appliedSuggestions[0])
        XCTAssertEqual(runtime.shiftEnglishKeyCodes, ShiftKey.keyCodes(in: .letter))
    }

    @MainActor
    func testNoShiftSuggestionWhenShiftIsOff() async {
        var values = lettersOnly
        values["shiftEnglishEnabled"] = false
        let fixture = makeFixture(defaultsValues: values, suggestionLines: retypedSlash(in: [app, app, app, app]))

        await fixture.runtime.refreshSuggestions()
        XCTAssertTrue(fixture.runtime.suggestions.isEmpty)
    }

    @MainActor
    func testApplyAndUndoAppRule() async {
        let fixture = makeFixture(suggestionLines: lines)
        let runtime = fixture.runtime

        await runtime.refreshSuggestions()
        XCTAssertEqual(runtime.suggestions.count, 1)

        let suggestion = runtime.suggestions[0]
        XCTAssertTrue(runtime.applySuggestion(suggestion))
        XCTAssertEqual(fixture.store.rules.first?.bundleIdentifier, app)
        XCTAssertEqual(fixture.store.rules.first?.inputSourceID, TestInputSources.abc.id)
        XCTAssertTrue(runtime.suggestions.isEmpty)
        XCTAssertEqual(runtime.appliedSuggestions.count, 1)

        runtime.undoSuggestion(runtime.appliedSuggestions[0])
        XCTAssertTrue(fixture.store.rules.isEmpty)
        XCTAssertTrue(runtime.appliedSuggestions.isEmpty)
    }

    @MainActor
    func testUndoRestoresPreviousRule() async {
        let previous = makeRule(
            bundleIdentifier: app, applicationName: "Notes",
            inputSourceID: TestInputSources.us.id, inputSourceName: "U.S."
        )
        let fixture = makeFixture(rules: [previous], suggestionLines: lines)
        let runtime = fixture.runtime

        await runtime.refreshSuggestions()
        XCTAssertTrue(runtime.applySuggestion(runtime.suggestions[0]))
        XCTAssertEqual(fixture.store.rules.first?.inputSourceID, TestInputSources.abc.id)

        runtime.undoSuggestion(runtime.appliedSuggestions[0])
        XCTAssertEqual(fixture.store.rules, [previous])
    }

    @MainActor
    func testDismissedSuggestionStaysGone() async {
        let fixture = makeFixture(suggestionLines: lines)
        let runtime = fixture.runtime

        await runtime.refreshSuggestions()
        runtime.dismissSuggestion(runtime.suggestions[0])
        XCTAssertTrue(runtime.suggestions.isEmpty)

        await runtime.refreshSuggestions()
        XCTAssertTrue(runtime.suggestions.isEmpty)
    }
}

final class AppRuntimeCapsLogTests: XCTestCase {
    @MainActor
    func testCapsLockLogsEventReadbacksAndKeyDelay() async throws {
        let fixture = makeFixture(usageLogging: true)
        fixture.runtime.start()
        fixture.keys.changeModifier(keyCode: 57, flags: ["caps"], capsLock: true)

        XCTAssertTrue(fixture.usage.events(named: "modifier").isEmpty)
        XCTAssertEqual(fixture.usage.events(named: "capsLock").count, 1)

        try await Task.sleep(for: .milliseconds(1300))
        XCTAssertEqual(fixture.usage.events(named: "capsReadback").count, 5)
        XCTAssertEqual(fixture.usage.events(named: "capsSettled").count, 1)

        fixture.keys.changeModifier(keyCode: 56, flags: ["shift"])
        XCTAssertEqual(fixture.usage.events(named: "capsLock").count, 1)
        XCTAssertEqual(fixture.usage.events(named: "modifier").count, 1)
        fixture.runtime.stop()
    }
}
