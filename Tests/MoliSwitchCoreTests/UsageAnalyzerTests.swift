import XCTest
@testable import MoliSwitchCore

final class UsageAnalyzerTests: XCTestCase {
    private let zh = "com.apple.inputmethod.SCIM.Shuangpin"
    private let us = "com.apple.keylayout.US"

    private func current(
        targets: [String: String] = [:],
        fieldRules: [FieldRule] = []
    ) -> UsageAnalyzer.CurrentRules {
        UsageAnalyzer.CurrentRules(
            appTargets: targets,
            fieldRules: fieldRules,
            inputSourceNames: [zh: "简体双拼", us: "美国"]
        )
    }

    private func manual(_ app: String, from: String, to: String, mono: Double, extra: String = "") -> String {
        "{\"e\":\"manualSwitch\",\"app\":\"\(app)\",\"from\":\"\(from)\",\"to\":\"\(to)\",\"mono\":\(mono)\(extra)}"
    }

    private func appFocus(_ app: String) -> String {
        "{\"e\":\"appFocus\",\"app\":\"\(app)\",\"appName\":\"Chat\"}"
    }

    func testSuggestsAppRuleFromRepeatedManualSwitches() {
        var lines = [appFocus("a.chat")]
        for index in 0..<9 {
            lines.append(manual("a.chat", from: us, to: zh, mono: Double(index) * 10_000))
        }

        let result = UsageAnalyzer().suggestions(fromLines: lines, current: current(targets: ["a.chat": us]))

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(
            result.first?.action,
            .setAppRule(bundleIdentifier: "a.chat", applicationName: "Chat", inputSourceID: zh)
        )
    }

    func testNoSuggestionWhenRuleAlreadyMatches() {
        let lines = (0..<9).map { manual("a.chat", from: us, to: zh, mono: Double($0) * 10_000) }

        XCTAssertTrue(UsageAnalyzer().suggestions(fromLines: lines, current: current(targets: ["a.chat": zh])).isEmpty)
    }

    func testNoSuggestionBelowThresholdOrMixedTargets() {
        var few = (0..<7).map { manual("a.chat", from: us, to: zh, mono: Double($0) * 10_000) }
        XCTAssertTrue(UsageAnalyzer().suggestions(fromLines: few, current: current()).isEmpty)

        few = (0..<5).map { manual("a.chat", from: us, to: zh, mono: Double($0) * 10_000) }
            + (0..<5).map { manual("a.chat", from: zh, to: us, mono: Double($0) * 10_000 + 5_000) }
        XCTAssertTrue(UsageAnalyzer().suggestions(fromLines: few, current: current()).isEmpty)
    }

    func testFlickersAndOwnSwitchesAreNotCounted() {
        var lines: [String] = []
        for index in 0..<9 {
            let base = Double(index) * 10_000
            lines.append(manual("a.chat", from: zh, to: us, mono: base))
            lines.append(manual("a.chat", from: us, to: zh, mono: base + 25))
        }
        lines += (0..<9).map { manual("a.chat", from: zh, to: us, mono: 200_000 + Double($0), extra: ",\"ownSwitch\":true") }
        lines += (0..<9).map { manual("a.chat", from: zh, to: us, mono: 300_000 + Double($0), extra: ",\"undoesPrevious\":true") }

        XCTAssertTrue(UsageAnalyzer().suggestions(fromLines: lines, current: current(targets: ["a.chat": zh])).isEmpty)
    }

    private let fieldLine = """
    {"e":"fieldFocus","app":"a.chat","field":{"role":"AXTextField","descriptor":"Terminal input","ancestors":["AXGroup"],"web":true}}
    """

    private func letter(_ app: String, source: String) -> String {
        "{\"e\":\"key\",\"app\":\"\(app)\",\"category\":\"letter\",\"current\":\"\(source)\"}"
    }

    func testSuggestsFieldRuleFromTypingSource() {
        let lines = [appFocus("a.chat"), fieldLine]
            + Array(repeating: letter("a.chat", source: us), count: 95)
            + Array(repeating: letter("a.chat", source: zh), count: 5)

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
        let lines = [fieldLine] + Array(repeating: letter("a.chat", source: us), count: 120)
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
}
