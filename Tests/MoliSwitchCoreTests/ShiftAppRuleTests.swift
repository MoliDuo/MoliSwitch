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
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(text.contains(#""categories":["letter","symbol"]"#))
        XCTAssertTrue(text.contains(#""keyCodes":[0,1,2,3,4,5,6,7,8,9,11,"#))

        XCTAssertEqual(try JSONDecoder().decode([ShiftAppRule].self, from: data), rules)
    }

    func testSingleKeysSurviveEncoding() throws {
        let options = ShiftEnglishOptions(keyCodes: [44, 41], restoresOnRelease: true)
        let data = try JSONEncoder().encode(options)
        XCTAssertEqual(try JSONDecoder().decode(ShiftEnglishOptions.self, from: data), options)
    }

    func testOptionsSavedWithOnlyCategoriesAreRead() throws {
        let data = Data(#"{"categories":["digit"],"restoresOnRelease":false}"#.utf8)
        let options = try JSONDecoder().decode(ShiftEnglishOptions.self, from: data)
        XCTAssertEqual(options, ShiftEnglishOptions(categories: [.digit], restoresOnRelease: false))
        XCTAssertEqual(options.keyCodes, ShiftKey.keyCodes(in: .digit))
    }
}
