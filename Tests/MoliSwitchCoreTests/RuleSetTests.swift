import XCTest
@testable import MoliSwitchCore

final class RuleSetTests: XCTestCase {
    private func rule(
        bundleIdentifier: String,
        inputSourceID: String = "com.apple.keylayout.US",
        applicationName: String = "Terminal",
        inputSourceName: String = "U.S."
    ) -> AppRule {
        AppRule(
            bundleIdentifier: bundleIdentifier,
            applicationName: applicationName,
            inputSourceID: inputSourceID,
            inputSourceName: inputSourceName
        )
    }

    func testFirstRuleWinsWhenDuplicatesAreNormalized() {
        let first = rule(bundleIdentifier: "com.apple.Terminal", inputSourceName: "第一条")
        let second = rule(bundleIdentifier: "com.apple.Terminal", inputSourceName: "第二条")

        let ruleSet = RuleSet(normalizing: [first, second])

        XCTAssertEqual(ruleSet.rules, [first])
        XCTAssertEqual(ruleSet.rule(forBundleIdentifier: "com.apple.Terminal"), first)
    }

    func testLookupUsesFirstRuleWhenDuplicatesAreNotNormalized() {
        let first = rule(bundleIdentifier: "com.apple.Terminal", inputSourceName: "第一条")
        let second = rule(bundleIdentifier: "com.apple.Terminal", inputSourceName: "第二条")

        let ruleSet = RuleSet(rules: [first, second])

        XCTAssertEqual(ruleSet.rule(forBundleIdentifier: "com.apple.Terminal"), first)
    }

    func testNormalizingDropsRulesWithInvalidIdentifiers() {
        let valid = rule(bundleIdentifier: "com.apple.Terminal")
        let rules = [
            rule(bundleIdentifier: ""),
            rule(bundleIdentifier: "   "),
            rule(bundleIdentifier: "-"),
            rule(bundleIdentifier: "com.apple.Safari", inputSourceID: ""),
            rule(bundleIdentifier: "com.apple.Notes", inputSourceID: "  "),
            valid,
        ]

        XCTAssertEqual(RuleSet(normalizing: rules).rules, [valid])
    }

    func testNormalizingKeepsNoSwitchRules() {
        let noSwitch = rule(bundleIdentifier: "com.apple.Mail", inputSourceID: "-")

        XCTAssertEqual(RuleSet(normalizing: [noSwitch]).rules, [noSwitch])
    }

    func testNormalizingKeepsNonEmptyUnavailableInputSource() {
        let unavailable = rule(
            bundleIdentifier: "com.example.App",
            inputSourceID: "com.example.gone",
            inputSourceName: "已卸载的输入法"
        )

        XCTAssertEqual(RuleSet(normalizing: [unavailable]).rules, [unavailable])
    }

    func testNormalizingPreservesOrderOfFirstAppearances() {
        let a = rule(bundleIdentifier: "com.example.a")
        let b = rule(bundleIdentifier: "com.example.b")
        let duplicateA = rule(bundleIdentifier: "com.example.a", inputSourceName: "重复")
        let c = rule(bundleIdentifier: "com.example.c")

        XCTAssertEqual(RuleSet(normalizing: [a, b, duplicateA, c]).rules, [a, b, c])
    }

    func testIdentifierValidationRejectsPlaceholderAndBlankValues() {
        XCTAssertTrue(RuleSet.isValidIdentifier("com.apple.Terminal"))
        XCTAssertTrue(RuleSet.isValidIdentifier(" com.apple.Terminal "))
        XCTAssertFalse(RuleSet.isValidIdentifier(""))
        XCTAssertFalse(RuleSet.isValidIdentifier("   "))
        XCTAssertFalse(RuleSet.isValidIdentifier("\n"))
        XCTAssertFalse(RuleSet.isValidIdentifier("-"))
    }

    func testNoSwitchSentinelIsDash() {
        XCTAssertEqual(RuleSet.noSwitchInputSourceID, "-")
    }

    func testRuleValidationRequiresBothIdentifiers() {
        XCTAssertTrue(RuleSet.isValid(rule(bundleIdentifier: "com.apple.Terminal")))
        XCTAssertTrue(
            RuleSet.isValid(rule(bundleIdentifier: "com.apple.Terminal", inputSourceID: "-"))
        )
        XCTAssertFalse(
            RuleSet.isValid(rule(bundleIdentifier: "com.apple.Terminal", inputSourceID: " "))
        )
        XCTAssertFalse(RuleSet.isValid(rule(bundleIdentifier: "-")))
    }

    func testUpsertReplacesExistingRuleInPlace() {
        var ruleSet = RuleSet(
            rules: [
                rule(bundleIdentifier: "com.example.a"),
                rule(bundleIdentifier: "com.example.b"),
            ]
        )
        let updated = rule(bundleIdentifier: "com.example.a", inputSourceID: "com.apple.keylayout.ABC")

        ruleSet.upsert(updated)

        XCTAssertEqual(
            ruleSet.rules,
            [updated, rule(bundleIdentifier: "com.example.b")]
        )
    }

    func testUpsertAppendsNewRule() {
        var ruleSet = RuleSet()
        ruleSet.upsert(rule(bundleIdentifier: "com.example.a"))
        ruleSet.upsert(rule(bundleIdentifier: "com.example.b"))

        XCTAssertEqual(ruleSet.rules.map(\.bundleIdentifier), ["com.example.a", "com.example.b"])
    }

    func testRemoveReturnsRemovedRuleAndIgnoresUnknownIdentifiers() {
        var ruleSet = RuleSet(rules: [rule(bundleIdentifier: "com.example.a")])

        let removed = ruleSet.remove(bundleIdentifier: "com.example.a")

        XCTAssertEqual(removed?.bundleIdentifier, "com.example.a")
        XCTAssertTrue(ruleSet.rules.isEmpty)
        XCTAssertNil(ruleSet.remove(bundleIdentifier: "com.example.a"))
    }
}
