import Foundation
import XCTest

@testable import MoliSwitchCore

final class ShiftAppRuleTests: XCTestCase {
    private func rule(_ name: String, _ bundleIdentifier: String, _ options: ShiftEnglishOptions = .off) -> ShiftAppRule {
        ShiftAppRule(bundleIdentifier: bundleIdentifier, applicationName: name, options: options)
    }

    func testListKeepsOneRulePerApplicationInNameOrder() {
        let list = ShiftAppRuleList(normalizing: [
            rule("Zed", "dev.zed.Zed"),
            rule("notes", "com.apple.Notes"),
            rule("Notes again", "com.apple.Notes", .all),
            rule("Broken", ""),
        ])

        XCTAssertEqual(list.rules.map(\.bundleIdentifier), ["com.apple.Notes", "dev.zed.Zed"])
        XCTAssertEqual(list.rule(for: "com.apple.Notes")?.options, .off)
    }

    func testSetReplacesAndRemoveDeletes() {
        var list = ShiftAppRuleList(rules: [rule("Notes", "com.apple.Notes")])

        list.set(rule("Notes", "com.apple.Notes", .all))
        XCTAssertEqual(list.rules.count, 1)
        XCTAssertEqual(list.rule(for: "com.apple.Notes")?.options, .all)

        XCTAssertNotNil(list.remove(bundleIdentifier: "com.apple.Notes"))
        XCTAssertTrue(list.rules.isEmpty)
        XCTAssertNil(list.remove(bundleIdentifier: "com.apple.Notes"))
    }

    func testRulesSurviveEncodingInAFixedOrder() throws {
        let options = ShiftEnglishOptions(categories: [.symbol, .letter], restoresOnRelease: false)
        let rules = [rule("Notes", "com.apple.Notes", options)]

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(rules)
        XCTAssertTrue(String(decoding: data, as: UTF8.self).contains(#""categories":["letter","symbol"]"#))

        XCTAssertEqual(try JSONDecoder().decode([ShiftAppRule].self, from: data), rules)
    }
}
