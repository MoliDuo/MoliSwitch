import XCTest
@testable import MoliSwitchCore

final class UsageAnalyzerTests: XCTestCase {
    private let zh = "com.apple.inputmethod.SCIM.Shuangpin"
    private let us = "com.apple.keylayout.US"

    private func current(
        targets: [String: String] = [:],
        fieldRules: [FieldRule] = [],
        commandTargets: [String: String] = [:],
        shiftEnabled: Bool = true,
        globalShift: ShiftEnglishOptions = .all,
        shiftAppRules: [String: ShiftEnglishOptions] = [:]
    ) -> UsageAnalyzer.CurrentRules {
        UsageAnalyzer.CurrentRules(
            appTargets: targets,
            fieldRules: fieldRules,
            commandTargets: commandTargets,
            shiftEnabled: shiftEnabled,
            globalShift: globalShift,
            shiftAppRules: shiftAppRules,
            inputSourceNames: [zh: "简体双拼", us: "美国"]
        )
    }

    // MARK: - Log lines

    private func manual(_ app: String, from: String, to: String, mono: Double, extra: String = "") -> String {
        "{\"e\":\"manualSwitch\",\"app\":\"\(app)\",\"from\":\"\(from)\",\"to\":\"\(to)\",\"mono\":\(mono)\(extra)}"
    }

    private func appFocus(_ app: String, mono: Double, terminal: [String]? = nil, tty: String = "/dev/ttys001") -> String {
        let context = terminal.map { names in
            "{\"candidates\":[\(names.map { "\"\($0)\"" }.joined(separator: ","))],\"tty\":\"\(tty)\"}"
        } ?? "null"
        return "{\"app\":\"\(app)\",\"appName\":\"Chat\",\"e\":\"appFocus\",\"mono\":\(mono),\"terminal\":\(context)}"
    }

    private func terminal(_ app: String, _ names: [String], mono: Double, tty: String = "/dev/ttys001") -> String {
        let candidates = names.map { "\"\($0)\"" }.joined(separator: ",")
        return "{\"app\":\"\(app)\",\"context\":{\"candidates\":[\(candidates)],\"tty\":\"\(tty)\"},\"e\":\"terminal\",\"mono\":\(mono),\"result\":\"found\"}"
    }

    private func letter(_ app: String, source: String, mono: Double = 0) -> String {
        "{\"app\":\"\(app)\",\"category\":\"letter\",\"chars\":\"a\",\"current\":\"\(source)\",\"e\":\"key\",\"key\":\"printable\",\"keyCode\":0,\"mono\":\(mono),\"shift\":\"pass\",\"shifted\":false}"
    }

    private func letters(_ app: String, source: String, count: Int, from mono: Double) -> [String] {
        (0..<count).map { letter(app, source: source, mono: mono + Double($0) * 100) }
    }

    private func shifted(
        _ app: String,
        keyCode: Int,
        source: String,
        switched: Bool = false,
        category: String = "symbol",
        mono: Double
    ) -> String {
        let decision = switched ? "switchToEnglish(englishID: \\\"\(us)\\\")" : "pass"
        return "{\"app\":\"\(app)\",\"category\":\"\(category)\",\"chars\":\"x\",\"current\":\"\(source)\",\"e\":\"key\",\"key\":\"printable\",\"keyCode\":\(keyCode),\"mono\":\(mono),\"shift\":\"\(decision)\",\"shifted\":true}"
    }

    private func backspace(_ app: String, source: String, mono: Double) -> String {
        "{\"app\":\"\(app)\",\"category\":null,\"current\":\"\(source)\",\"e\":\"key\",\"key\":\"backspace\",\"keyCode\":51,\"mono\":\(mono),\"shift\":\"pass\",\"shifted\":false}"
    }

    private func restore(_ app: String, mono: Double) -> String {
        "{\"app\":\"\(app)\",\"e\":\"switch\",\"from\":\"\(us)\",\"mono\":\(mono),\"ok\":true,\"reason\":\"shiftRestore\",\"to\":\"\(zh)\"}"
    }

    /// A visit to the application: active, optionally switched at once, then typing.
    private func visit(
        _ app: String,
        at mono: Double,
        switchTo: String? = nil,
        from: String? = nil,
        typing source: String,
        letters count: Int = 10
    ) -> [String] {
        var lines = [appFocus(app, mono: mono)]
        if let switchTo {
            lines.append(manual(app, from: from ?? (switchTo == zh ? us : zh), to: switchTo, mono: mono + 500))
        }
        return lines + letters(app, source: source, count: count, from: mono + 1_000)
    }

    // MARK: - Applications

    func testSuggestsAppRuleWhenMostVisitsAreCorrected() {
        var lines: [String] = []
        for index in 0..<10 {
            lines += visit("a.chat", at: Double(index) * 100_000, switchTo: zh, typing: zh)
        }
        lines += visit("a.chat", at: 2_000_000, typing: us)

        let result = UsageAnalyzer().suggestions(fromLines: lines, current: current(targets: ["a.chat": us]))

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(
            result.first?.action,
            .setAppRule(bundleIdentifier: "a.chat", applicationName: "Chat", inputSourceID: zh)
        )
        XCTAssertEqual(result.first?.kind, .application)
        XCTAssertTrue(result.first?.evidence.contains("91%") == true, result.first?.evidence ?? "")
    }

    /// Visits where the rule was right count too: a few corrections among
    /// many visits that needed none are not a reason to change it.
    func testFewCorrectionsAmongManyVisitsSuggestNothing() {
        var lines: [String] = []
        for index in 0..<400 {
            let switches = index % 10 == 0
            lines += visit("a.chat", at: Double(index) * 100_000, switchTo: switches ? zh : nil, typing: switches ? zh : us)
        }

        XCTAssertTrue(UsageAnalyzer().suggestions(fromLines: lines, current: current(targets: ["a.chat": us])).isEmpty)
    }

    func testSwitchingWhileTypingIsNotACorrection() {
        var lines: [String] = []
        for index in 0..<20 {
            let start = Double(index) * 100_000
            lines.append(appFocus("a.chat", mono: start))
            lines += letters("a.chat", source: us, count: 5, from: start + 100)
            lines.append(manual("a.chat", from: us, to: zh, mono: start + 2_000))
            lines += letters("a.chat", source: zh, count: 5, from: start + 3_000)
        }

        XCTAssertTrue(UsageAnalyzer().suggestions(fromLines: lines, current: current(targets: ["a.chat": us])).isEmpty)
    }

    func testVisitsWithoutTypingAreNotCounted() {
        var lines: [String] = []
        for index in 0..<10 {
            lines += visit("a.chat", at: Double(index) * 100_000, switchTo: zh, typing: zh, letters: 1)
        }

        XCTAssertTrue(UsageAnalyzer().suggestions(fromLines: lines, current: current(targets: ["a.chat": us])).isEmpty)
    }

    func testNoSuggestionWhenRuleAlreadyMatches() {
        var lines: [String] = []
        for index in 0..<10 {
            lines += visit("a.chat", at: Double(index) * 100_000, switchTo: zh, typing: zh)
        }

        XCTAssertTrue(UsageAnalyzer().suggestions(fromLines: lines, current: current(targets: ["a.chat": zh])).isEmpty)
    }

    func testSwitchesUndoneAtOnceAndOwnSwitchesAreNotCorrections() {
        var lines: [String] = []
        for index in 0..<10 {
            let start = Double(index) * 100_000
            lines.append(appFocus("a.chat", mono: start))
            lines.append(manual("a.chat", from: us, to: zh, mono: start + 500))
            lines.append(manual("a.chat", from: zh, to: us, mono: start + 525))
            lines.append(manual("a.chat", from: us, to: zh, mono: start + 600, extra: ",\"ownSwitch\":true"))
            lines.append(manual("a.chat", from: us, to: zh, mono: start + 700, extra: ",\"sinceOwnSwitchMs\":50"))
            lines += letters("a.chat", source: us, count: 10, from: start + 1_000)
        }

        XCTAssertTrue(UsageAnalyzer().suggestions(fromLines: lines, current: current(targets: ["a.chat": us])).isEmpty)
    }

    func testSwitchingBackToTheFirstInputSourceIsNoCorrection() {
        var lines: [String] = []
        for index in 0..<10 {
            let start = Double(index) * 100_000
            lines.append(appFocus("a.chat", mono: start))
            lines.append(manual("a.chat", from: us, to: zh, mono: start + 500))
            lines.append(manual("a.chat", from: zh, to: us, mono: start + 2_000))
            lines += letters("a.chat", source: us, count: 10, from: start + 3_000)
        }

        XCTAssertTrue(UsageAnalyzer().suggestions(fromLines: lines, current: current(targets: ["a.chat": us])).isEmpty)
    }

    // MARK: - Terminal programs

    func testTerminalProgramsAreJudgedOneByOne() {
        let term = "a.term"
        var lines: [String] = []
        for index in 0..<10 {
            let start = Double(index) * 100_000
            // The shell needs no change; claude is corrected to English each time.
            lines.append(appFocus(term, mono: start, terminal: ["zsh"]))
            lines += letters(term, source: zh, count: 10, from: start + 100)
            lines.append(terminal(term, ["claude", "node"], mono: start + 10_000))
            lines.append(manual(term, from: zh, to: us, mono: start + 10_500))
            lines += letters(term, source: us, count: 10, from: start + 11_000)
        }

        let result = UsageAnalyzer().suggestions(fromLines: lines, current: current(targets: [term: zh]))

        XCTAssertEqual(result.map(\.action), [.setCommandRule(command: "claude", inputSourceID: us)])
        XCTAssertEqual(result.first?.kind, .command)
        XCTAssertEqual(result.first?.id, "command:claude=\(us)")

        // Once claude has its rule, nothing more.
        XCTAssertTrue(
            UsageAnalyzer().suggestions(fromLines: lines, current: current(targets: [term: zh], commandTargets: ["claude": us]))
                .isEmpty
        )
    }

    /// A program found after the terminal became active is the same visit,
    /// whether the user switched before or after it was found.
    func testProgramFoundAfterActivationKeepsTheVisit() {
        let term = "a.term"
        for switchFirst in [true, false] {
            var lines: [String] = []
            for index in 0..<10 {
                let start = Double(index) * 100_000
                let found = terminal(term, ["vim"], mono: start + 400)
                let switched = manual(term, from: zh, to: us, mono: start + 300)
                lines.append(appFocus(term, mono: start))
                lines += switchFirst ? [switched, found] : [found, switched]
                lines += letters(term, source: us, count: 10, from: start + 1_000)
            }

            XCTAssertEqual(
                UsageAnalyzer().suggestions(fromLines: lines, current: current(targets: [term: zh])).map(\.action),
                [.setCommandRule(command: "vim", inputSourceID: us)],
                "switch first: \(switchFirst)"
            )
        }
    }

    // MARK: - Fields

    private let fieldLine = """
    {"e":"fieldFocus","app":"a.chat","field":{"role":"AXTextField","descriptor":"Terminal input","ancestors":["AXGroup"],"web":true}}
    """

    func testSuggestsFieldRuleFromTypingSource() {
        let lines = [appFocus("a.chat", mono: 0), fieldLine]
            + letters("a.chat", source: us, count: 95, from: 100)
            + letters("a.chat", source: zh, count: 5, from: 20_000)

        let result = UsageAnalyzer().suggestions(fromLines: lines, current: current(targets: ["a.chat": zh]))

        XCTAssertEqual(result.count, 1)
        guard case .addFieldRule(let bundle, _, let signature, let source)? = result.first?.action else {
            return XCTFail("expected a field rule")
        }
        XCTAssertEqual(bundle, "a.chat")
        XCTAssertEqual(signature.descriptor, "Terminal input")
        XCTAssertEqual(source, us)
    }

    func testFieldSuggestionSkippedWhenFieldRuleExistsOrTooFewKeys() {
        let lines = [fieldLine] + letters("a.chat", source: us, count: 120, from: 0)
        let signature = FieldSignature(
            role: "AXTextField", descriptor: "Terminal input", ancestorRoles: ["AXGroup"], isInWebArea: true
        )
        let rule = FieldRule(
            bundleIdentifier: "a.chat", applicationName: "Chat", label: "x",
            signature: signature, inputSourceID: us, inputSourceName: "美国"
        )

        XCTAssertTrue(
            UsageAnalyzer().suggestions(fromLines: lines, current: current(targets: ["a.chat": zh], fieldRules: [rule])).isEmpty
        )
        XCTAssertTrue(
            UsageAnalyzer().suggestions(fromLines: Array(lines.prefix(50)), current: current(targets: ["a.chat": zh])).isEmpty
        )
    }

    // MARK: - Shift

    /// Shift + / typed in Chinese, deleted, and typed again.
    private func retyped(_ app: String, keyCode: Int = 44, at mono: Double) -> [String] {
        [
            shifted(app, keyCode: keyCode, source: zh, mono: mono),
            backspace(app, source: zh, mono: mono + 500),
            shifted(app, keyCode: keyCode, source: zh, mono: mono + 2_000),
        ]
    }

    func testSuggestsSwitchingAKeyRetypedInEnglish() {
        let options = ShiftEnglishOptions(categories: [.letter], restoresOnRelease: true)
        var lines = [appFocus("a.chat", mono: 0)]
        for index in 0..<4 {
            lines += retyped("a.chat", at: Double(index) * 100_000 + 1_000)
        }
        for index in 0..<6 {
            lines.append(shifted("a.chat", keyCode: 44, source: zh, mono: 1_000_000 + Double(index) * 10_000))
        }
        // Another key, typed in Chinese and kept.
        for index in 0..<20 {
            lines.append(shifted("a.chat", keyCode: 41, source: zh, mono: 2_000_000 + Double(index) * 10_000))
        }

        let result = UsageAnalyzer().suggestions(fromLines: lines, current: current(globalShift: options))

        XCTAssertEqual(
            result.map(\.action),
            [.setShiftKey(bundleIdentifier: "a.chat", applicationName: "Chat", keyCode: 44, enabled: true)]
        )
        XCTAssertEqual(result.first?.id, "shiftKey:a.chat:44=on")
        XCTAssertEqual(result.first?.kind, .shift)

        // Not when the key already switches, or Shift is off.
        var withKey = options
        withKey.set(keyCode: 44, on: true)
        XCTAssertTrue(UsageAnalyzer().suggestions(fromLines: lines, current: current(globalShift: withKey)).isEmpty)
        XCTAssertTrue(
            UsageAnalyzer().suggestions(fromLines: lines, current: current(shiftEnabled: false, globalShift: options)).isEmpty
        )
    }

    func testRetypesSpreadOverApplicationsChangeTheGlobalSetting() {
        let options = ShiftEnglishOptions(categories: [.letter], restoresOnRelease: true)
        var lines: [String] = []
        for (index, app) in ["a.one", "a.two", "a.three", "a.one"].enumerated() {
            lines.append(appFocus(app, mono: Double(index) * 100_000))
            lines += retyped(app, at: Double(index) * 100_000 + 1_000)
        }

        let result = UsageAnalyzer().suggestions(fromLines: lines, current: current(globalShift: options))

        XCTAssertEqual(
            result.map(\.action),
            [.setShiftKey(bundleIdentifier: nil, applicationName: nil, keyCode: 44, enabled: true)]
        )
    }

    func testRareRetypesSuggestNothing() {
        let options = ShiftEnglishOptions(categories: [.letter], restoresOnRelease: true)
        var lines = [appFocus("a.chat", mono: 0)]
        for index in 0..<3 {
            lines += retyped("a.chat", at: Double(index) * 100_000 + 1_000)
        }
        for index in 0..<30 {
            lines.append(shifted("a.chat", keyCode: 44, source: zh, mono: 1_000_000 + Double(index) * 10_000))
        }

        XCTAssertTrue(UsageAnalyzer().suggestions(fromLines: lines, current: current(globalShift: options)).isEmpty)
    }

    func testDeletingLaterOrAfterOtherKeysIsNoRetype() {
        let options = ShiftEnglishOptions(categories: [.letter], restoresOnRelease: true)
        var lines = [appFocus("a.chat", mono: 0)]
        for index in 0..<5 {
            let start = Double(index) * 100_000
            lines.append(shifted("a.chat", keyCode: 44, source: zh, mono: start))
            lines.append(letter("a.chat", source: zh, mono: start + 100))
            lines.append(backspace("a.chat", source: zh, mono: start + 200))
            lines.append(shifted("a.chat", keyCode: 44, source: zh, mono: start + 300))
        }

        XCTAssertTrue(UsageAnalyzer().suggestions(fromLines: lines, current: current(globalShift: options)).isEmpty)
    }

    func testSuggestsNotSwitchingAKeyDeletedAtOnce() {
        var lines = [appFocus("a.chat", mono: 0)]
        for index in 0..<10 {
            let start = Double(index) * 100_000
            lines.append(shifted("a.chat", keyCode: 41, source: zh, switched: true, mono: start))
            if index < 4 {
                lines.append(backspace("a.chat", source: us, mono: start + 400))
            } else {
                lines.append(letter("a.chat", source: zh, mono: start + 400))
            }
        }

        let result = UsageAnalyzer().suggestions(fromLines: lines, current: current())

        XCTAssertEqual(
            result.map(\.action),
            [.setShiftKey(bundleIdentifier: "a.chat", applicationName: "Chat", keyCode: 41, enabled: false)]
        )

        // Not when the application's own settings already leave it alone.
        var own = ShiftEnglishOptions.all
        own.set(keyCode: 41, on: false)
        XCTAssertTrue(UsageAnalyzer().suggestions(fromLines: lines, current: current(shiftAppRules: ["a.chat": own])).isEmpty)
    }

    func testSuggestsStayingInEnglishAfterShift() {
        var lines = [appFocus("a.chat", mono: 0)]
        for index in 0..<8 {
            let start = Double(index) * 100_000
            lines.append(restore("a.chat", mono: start))
            if index < 6 {
                lines.append(manual("a.chat", from: zh, to: us, mono: start + 800))
            }
        }

        let result = UsageAnalyzer().suggestions(fromLines: lines, current: current())

        XCTAssertEqual(
            result.map(\.action),
            [.setShiftRestore(bundleIdentifier: "a.chat", applicationName: "Chat", enabled: false)]
        )
        XCTAssertEqual(result.first?.id, "shiftRestore:a.chat=off")
    }

    func testSwitchingBackLaterOrAfterTypingDoesNotUndoTheRestore() {
        var lines = [appFocus("a.chat", mono: 0)]
        for index in 0..<8 {
            let start = Double(index) * 100_000
            lines.append(restore("a.chat", mono: start))
            if index % 2 == 0 {
                lines.append(manual("a.chat", from: zh, to: us, mono: start + 5_000))
            } else {
                lines.append(letter("a.chat", source: zh, mono: start + 100))
                lines.append(manual("a.chat", from: zh, to: us, mono: start + 800))
            }
        }

        XCTAssertTrue(UsageAnalyzer().suggestions(fromLines: lines, current: current()).isEmpty)
    }
}
