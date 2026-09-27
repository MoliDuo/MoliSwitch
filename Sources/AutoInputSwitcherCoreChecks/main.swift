import AutoInputSwitcherCore
import Foundation

@main
struct CoreChecks {
    static func main() throws {
        try testRuleSetReturnsExactBundleRule()
        try testUpsertingRuleReplacesExistingBundleID()
        try testJSONRuleStoreLoadsEmptyRulesWhenFileDoesNotExist()
        try testJSONRuleStorePersistsRules()
        try testSwitchCounterDefaultsToZero()
        try testSwitchCounterPersistsIncrementedCount()
        try testApplicationListFilterMatchesNameAndBundleID()
        try testApplicationListFilterShowsOnlyConfiguredEntries()
        try testApplicationListFilterShowsOnlyUnconfiguredEntries()
        try testNormalisingRuleSetKeepsFirstRuleAndDropsInvalidEntries()
        try testIdentifierValidationRejectsPlaceholderAndBlankValues()
        try testJSONRuleStoreThrowsOnCorruptFileAndKeepsItIntact()
        try testApplicationListFilterRequiresInstalledApplicationsWhenUnconfigured()
        try testFieldRuleMatchesTheSavedField()
        try testAddressBarDetectorRecognisesSafariAndChrome()
        print("Core checks passed")
    }

    private static func testRuleSetReturnsExactBundleRule() throws {
        let terminal = AppRule(
            bundleIdentifier: "com.apple.Terminal",
            applicationName: "Terminal",
            inputSourceID: "com.apple.keylayout.US",
            inputSourceName: "U.S."
        )
        let ruleSet = RuleSet(rules: [terminal])

        try expectEqual(ruleSet.rule(forBundleIdentifier: "com.apple.Terminal"), terminal)
        try expectNil(ruleSet.rule(forBundleIdentifier: "com.apple.finder"))
    }

    private static func testUpsertingRuleReplacesExistingBundleID() throws {
        var ruleSet = RuleSet()
        ruleSet.upsert(
            AppRule(
                bundleIdentifier: "com.tencent.xinWeChat",
                applicationName: "WeChat",
                inputSourceID: "com.apple.keylayout.US",
                inputSourceName: "U.S."
            )
        )
        ruleSet.upsert(
            AppRule(
                bundleIdentifier: "com.tencent.xinWeChat",
                applicationName: "WeChat",
                inputSourceID: "com.apple.inputmethod.SCIM.Shuangpin",
                inputSourceName: "Shuangpin - Simplified"
            )
        )

        try expectEqual(ruleSet.rules.count, 1)
        try expectEqual(ruleSet.rules[0].inputSourceID, "com.apple.inputmethod.SCIM.Shuangpin")
    }

    private static func testJSONRuleStoreLoadsEmptyRulesWhenFileDoesNotExist() throws {
        let store = JSONRuleStore(url: temporaryRulesURL())

        try expectEqual(try store.load(), [])
    }

    private static func testJSONRuleStorePersistsRules() throws {
        let store = JSONRuleStore(url: temporaryRulesURL())
        let rules = [
            AppRule(
                bundleIdentifier: "com.apple.Terminal",
                applicationName: "Terminal",
                inputSourceID: "com.apple.keylayout.US",
                inputSourceName: "U.S."
            ),
            AppRule(
                bundleIdentifier: "com.tencent.xinWeChat",
                applicationName: "WeChat",
                inputSourceID: "com.apple.inputmethod.SCIM.Shuangpin",
                inputSourceName: "Shuangpin - Simplified"
            )
        ]

        try store.save(rules)

        try expectEqual(try store.load(), rules)
    }

    private static func temporaryRulesURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("rules.json")
    }

    private static func testSwitchCounterDefaultsToZero() throws {
        let defaults = temporaryDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let counter = SwitchCounter(defaults: defaults)

        try expectEqual(counter.count, 0)
    }

    private static func testSwitchCounterPersistsIncrementedCount() throws {
        let defaults = temporaryDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let counter = SwitchCounter(defaults: defaults)

        counter.recordSwitch()
        counter.recordSwitch()

        let reloaded = SwitchCounter(defaults: defaults)
        try expectEqual(reloaded.count, 2)
    }

    private static let suiteName = "AutoInputSwitcherCoreChecks.\(UUID().uuidString)"

    private static func temporaryDefaults() -> UserDefaults {
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            fatalError("Unable to create temporary UserDefaults suite")
        }
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private static func testApplicationListFilterMatchesNameAndBundleID() throws {
        let terminal = ApplicationListEntry(
            displayName: "Terminal",
            bundleIdentifier: "com.apple.Terminal"
        )
        let weChat = ApplicationListEntry(
            displayName: "WeChat",
            bundleIdentifier: "com.tencent.xinWeChat"
        )

        let nameFilter = ApplicationListFilter(query: "term")
        let bundleFilter = ApplicationListFilter(query: "tencent")

        try expectEqual(nameFilter.includes(terminal), true)
        try expectEqual(nameFilter.includes(weChat), false)
        try expectEqual(bundleFilter.includes(terminal), false)
        try expectEqual(bundleFilter.includes(weChat), true)
    }

    private static func testApplicationListFilterShowsOnlyConfiguredEntries() throws {
        let terminal = ApplicationListEntry(
            displayName: "Terminal",
            bundleIdentifier: "com.apple.Terminal"
        )
        let weChat = ApplicationListEntry(
            displayName: "WeChat",
            bundleIdentifier: "com.tencent.xinWeChat"
        )
        let filter = ApplicationListFilter(
            scope: .configured,
            configuredBundleIdentifiers: ["com.tencent.xinWeChat"]
        )

        try expectEqual(filter.includes(terminal), false)
        try expectEqual(filter.includes(weChat), true)
    }

    private static func testApplicationListFilterShowsOnlyUnconfiguredEntries() throws {
        let terminal = ApplicationListEntry(
            displayName: "Terminal",
            bundleIdentifier: "com.apple.Terminal"
        )
        let weChat = ApplicationListEntry(
            displayName: "WeChat",
            bundleIdentifier: "com.tencent.xinWeChat"
        )
        let filter = ApplicationListFilter(
            scope: .unconfigured,
            configuredBundleIdentifiers: ["com.tencent.xinWeChat"]
        )

        try expectEqual(filter.includes(terminal), true)
        try expectEqual(filter.includes(weChat), false)
    }

    private static func testNormalisingRuleSetKeepsFirstRuleAndDropsInvalidEntries() throws {
        let first = AppRule(
            bundleIdentifier: "com.apple.Terminal",
            applicationName: "Terminal",
            inputSourceID: "com.apple.keylayout.US",
            inputSourceName: "U.S."
        )
        let duplicate = AppRule(
            bundleIdentifier: "com.apple.Terminal",
            applicationName: "Terminal",
            inputSourceID: "com.apple.keylayout.ABC",
            inputSourceName: "ABC"
        )
        let blankIdentifier = AppRule(
            bundleIdentifier: "   ",
            applicationName: "Blank",
            inputSourceID: "com.apple.keylayout.US",
            inputSourceName: "U.S."
        )
        let noSwitch = AppRule(
            bundleIdentifier: "com.apple.Safari",
            applicationName: "Safari",
            inputSourceID: "-",
            inputSourceName: "不切换"
        )

        let ruleSet = RuleSet(normalizing: [first, duplicate, blankIdentifier, noSwitch])

        try expectEqual(ruleSet.rules, [first, noSwitch])
        try expectEqual(ruleSet.rule(forBundleIdentifier: "com.apple.Terminal"), first)
    }

    private static func testIdentifierValidationRejectsPlaceholderAndBlankValues() throws {
        try expectEqual(RuleSet.isValidIdentifier("com.apple.Terminal"), true)
        try expectEqual(RuleSet.isValidIdentifier("  com.apple.Terminal  "), true)
        try expectEqual(RuleSet.isValidIdentifier(""), false)
        try expectEqual(RuleSet.isValidIdentifier("   "), false)
        try expectEqual(RuleSet.isValidIdentifier("-"), false)
        try expectEqual(RuleSet.noSwitchInputSourceID, "-")
    }

    private static func testJSONRuleStoreThrowsOnCorruptFileAndKeepsItIntact() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let url = directory.appendingPathComponent("rules.json")
        let store = JSONRuleStore(url: url)
        let corrupt = Data("{ this is not a rule list".utf8)
        try corrupt.write(to: url)

        do {
            _ = try store.load()
            throw CheckFailure("Expected the corrupt rule file to fail loading")
        } catch is DecodingError {
            // Expected: malformed JSON is reported instead of being read as an
            // empty rule set.
        }

        try expectEqual(try Data(contentsOf: url), corrupt)
        try expectEqual(store.fileExists, true)
        try expectEqual(
            try JSONRuleStore(url: directory.appendingPathComponent("missing.json")).load(),
            []
        )
    }

    private static func testApplicationListFilterRequiresInstalledApplicationsWhenUnconfigured() throws {
        let installed = ApplicationListEntry(
            displayName: "Terminal",
            bundleIdentifier: "com.apple.Terminal"
        )
        let leftover = ApplicationListEntry(
            displayName: "Ghost",
            bundleIdentifier: "com.example.ghost",
            isInstalled: false
        )

        let unconfigured = ApplicationListFilter(scope: .unconfigured)
        try expectEqual(unconfigured.includes(installed), true)
        try expectEqual(unconfigured.includes(leftover), false)

        let configured = ApplicationListFilter(
            scope: .configured,
            configuredBundleIdentifiers: ["com.example.ghost"]
        )
        try expectEqual(configured.includes(leftover), true)
        try expectEqual(configured.includes(installed), false)
    }

    private static func testFieldRuleMatchesTheSavedField() throws {
        let searchField = FieldSignature(
            role: "AXTextField",
            subrole: "AXSearchField",
            descriptor: "搜索",
            ancestorRoles: ["AXGroup", "AXWindow"]
        )
        let rule = FieldRule(
            bundleIdentifier: "com.tencent.xinWeChat",
            applicationName: "WeChat",
            label: searchField.suggestedLabel,
            signature: searchField,
            inputSourceID: "role.english",
            inputSourceName: "英文"
        )
        let ruleSet = FieldRuleSet(normalizing: [rule, rule])
        var chatField = searchField
        chatField.descriptor = "消息"

        try expectEqual(ruleSet.rules.count, 1)
        try expectEqual(ruleSet.rule(forBundleIdentifier: "com.tencent.xinWeChat", matching: searchField), rule)
        try expectNil(ruleSet.rule(forBundleIdentifier: "com.tencent.xinWeChat", matching: chatField))
        try expectNil(ruleSet.rule(forBundleIdentifier: "com.apple.Notes", matching: searchField))
    }

    private static func testAddressBarDetectorRecognisesSafariAndChrome() throws {
        let safari = FieldSignature(role: "AXTextField", identifier: "WEB_BROWSER_ADDRESS_AND_SEARCH_FIELD")
        let omnibox = FieldSignature(role: "AXTextField", descriptor: "Address and search bar")
        let pageSearch = FieldSignature(role: "AXTextField", descriptor: "Address and search bar", isInWebArea: true)

        try expectEqual(AddressBarDetector.isAddressBar(bundleIdentifier: "com.apple.Safari", field: safari), true)
        try expectEqual(AddressBarDetector.isAddressBar(bundleIdentifier: "com.google.Chrome", field: omnibox), true)
        try expectEqual(AddressBarDetector.isAddressBar(bundleIdentifier: "com.google.Chrome", field: pageSearch), false)
        try expectEqual(AddressBarDetector.isAddressBar(bundleIdentifier: "com.apple.Notes", field: safari), false)
    }

    private static func expectEqual<T: Equatable>(_ actual: T, _ expected: T) throws {
        if actual != expected {
            throw CheckFailure("Expected \(expected), got \(actual)")
        }
    }

    private static func expectNil<T>(_ actual: T?) throws {
        if let actual {
            throw CheckFailure("Expected nil, got \(actual)")
        }
    }
}

struct CheckFailure: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}
