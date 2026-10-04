import Foundation
import XCTest

import MoliSwitchCore

@testable import MoliSwitchApp

final class AppRuntimeSuggestionTests: XCTestCase {
    private let app = "com.apple.Notes"

    private var lines: [String] {
        ["{\"e\":\"appFocus\",\"app\":\"\(app)\",\"appName\":\"Notes\"}"]
            + (0..<9).map {
                "{\"e\":\"manualSwitch\",\"app\":\"\(app)\",\"from\":\"com.apple.keylayout.US\",\"to\":\"com.apple.keylayout.ABC\",\"mono\":\($0 * 10000)}"
            }
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
