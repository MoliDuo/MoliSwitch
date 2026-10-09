import Foundation
import XCTest
@testable import MoliSwitchCore

final class CommandRuleSetTests: XCTestCase {
    private func rule(_ command: String, _ inputSourceID: String = "role.chinese") -> CommandRule {
        CommandRule(command: command, inputSourceID: inputSourceID, inputSourceName: "中文")
    }

    func testNormalizedCommandDropsDirectoryWhitespaceAndLoginDash() {
        XCTAssertEqual(CommandRuleSet.normalizedCommand("  /opt/homebrew/bin/nvim \n"), "nvim")
        XCTAssertEqual(CommandRuleSet.normalizedCommand("-zsh"), "zsh")
        XCTAssertEqual(CommandRuleSet.normalizedCommand("   "), "")
    }

    func testNormalizingDropsInvalidAndDuplicateRules() {
        let set = CommandRuleSet(normalizing: [
            rule(" claude "),
            rule("Claude", "role.english"),
            rule(""),
            rule("vim", ""),
        ])

        XCTAssertEqual(set.rules, [rule("claude")])
    }

    func testMatchingIgnoresCaseAndUsesTheFirstCandidateWithARule() {
        let set = CommandRuleSet(rules: [rule("claude"), rule("node", "role.english")])

        XCTAssertEqual(set.rule(forCommand: "CLAUDE")?.command, "claude")
        XCTAssertEqual(set.rule(matchingAnyOf: ["codex", "node"])?.command, "node")
        XCTAssertEqual(set.rule(matchingAnyOf: ["claude", "node"])?.command, "claude")
        XCTAssertNil(set.rule(matchingAnyOf: ["zsh"]))
    }

    func testUpsertReplacesTheRuleForTheSameCommand() {
        var set = CommandRuleSet(rules: [rule("vim")])

        set.upsert(rule("/usr/bin/VIM", "role.english"))
        XCTAssertEqual(set.rules.count, 1)
        XCTAssertEqual(set.rules.first?.inputSourceID, "role.english")

        XCTAssertNotNil(set.remove(command: "Vim"))
        XCTAssertNil(set.remove(command: "vim"))
        XCTAssertTrue(set.rules.isEmpty)
    }

    func testCommandRulesRoundTripThroughTheStore() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("MoliSwitchCoreTests-" + UUID().uuidString)
            .appendingPathComponent("command-rules.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = JSONCommandRuleStore(url: url)

        XCTAssertEqual(try store.load(), [])
        try store.save([rule("claude")])
        XCTAssertEqual(try store.load(), [rule("claude")])
    }
}
