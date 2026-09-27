import Foundation
import XCTest

@testable import MoliSwitchCore

final class FieldRuleSetTests: XCTestCase {
    private let searchField = FieldSignature(
        role: "AXTextField",
        subrole: "AXSearchField",
        descriptor: "搜索",
        ancestorRoles: ["AXGroup", "AXSplitGroup", "AXWindow"]
    )

    private func rule(
        _ signature: FieldSignature,
        bundleIdentifier: String = "com.tencent.xinWeChat",
        inputSourceID: String = "role.english"
    ) -> FieldRule {
        FieldRule(
            bundleIdentifier: bundleIdentifier,
            applicationName: "WeChat",
            label: signature.suggestedLabel,
            signature: signature,
            inputSourceID: inputSourceID,
            inputSourceName: "英文"
        )
    }

    func testSignatureTrimsBlankAttributes() {
        let signature = FieldSignature(role: "AXTextArea", subrole: " ", identifier: "", descriptor: " 消息 ")

        XCTAssertNil(signature.subrole)
        XCTAssertNil(signature.identifier)
        XCTAssertEqual(signature.descriptor, "消息")
    }

    func testFieldWithAnIdentifierIsRecognisedWhereverItIs() {
        let saved = FieldSignature(role: "AXTextField", identifier: "search", ancestorRoles: ["AXGroup"])
        let moved = FieldSignature(
            role: "AXTextField",
            identifier: "search",
            descriptor: "Search",
            ancestorRoles: ["AXGroup", "AXGroup"]
        )

        XCTAssertTrue(saved.matches(moved))
        XCTAssertFalse(saved.matches(FieldSignature(role: "AXTextField", identifier: "name")))
        XCTAssertFalse(saved.matches(FieldSignature(role: "AXTextArea", identifier: "search")))
    }

    func testFieldWithoutAnIdentifierNeedsEveryAttributeToAgree() {
        XCTAssertTrue(searchField.matches(searchField))

        var otherPlace = searchField
        otherPlace.ancestorRoles = ["AXGroup", "AXWindow"]
        XCTAssertFalse(searchField.matches(otherPlace))

        var otherName = searchField
        otherName.descriptor = "消息"
        XCTAssertFalse(searchField.matches(otherName))

        var onAWebPage = searchField
        onAWebPage.isInWebArea = true
        XCTAssertFalse(searchField.matches(onAWebPage))
    }

    func testSuggestedLabelPrefersTheFieldsOwnName() {
        XCTAssertEqual(searchField.suggestedLabel, "搜索")
        XCTAssertEqual(FieldSignature(role: "AXTextField", subrole: "AXSearchField").suggestedLabel, "搜索框")
        XCTAssertEqual(FieldSignature(role: "AXTextArea").suggestedLabel, "多行输入框")
        XCTAssertEqual(FieldSignature(role: "AXTextField").suggestedLabel, "输入框")
    }

    func testNormalizingDropsInvalidAndRepeatedRules() {
        let first = rule(searchField)
        var sameID = rule(FieldSignature(role: "AXTextArea"))
        sameID.id = first.id

        let set = FieldRuleSet(normalizing: [
            first,
            sameID,
            rule(searchField, inputSourceID: "role.chinese"),
            rule(searchField, bundleIdentifier: " "),
            rule(FieldSignature(role: "AXTextArea"), inputSourceID: ""),
            rule(FieldSignature(role: "")),
        ])

        XCTAssertEqual(set.rules, [first])
    }

    func testLookupIsPerApplication() {
        let wechat = rule(searchField)
        let set = FieldRuleSet(rules: [wechat])

        XCTAssertEqual(set.rule(forBundleIdentifier: "com.tencent.xinWeChat", matching: searchField), wechat)
        XCTAssertNil(set.rule(forBundleIdentifier: "com.apple.Notes", matching: searchField))
        XCTAssertTrue(set.hasRules(forBundleIdentifier: "com.tencent.xinWeChat"))
        XCTAssertFalse(set.hasRules(forBundleIdentifier: "com.apple.Notes"))
    }

    func testUpsertAndRemoveByID() {
        var set = FieldRuleSet()
        var saved = rule(searchField)
        set.upsert(saved)

        saved.inputSourceID = "role.chinese"
        set.upsert(saved)
        XCTAssertEqual(set.rules.count, 1)
        XCTAssertEqual(set.rule(id: saved.id)?.inputSourceID, "role.chinese")

        XCTAssertNotNil(set.remove(id: saved.id))
        XCTAssertNil(set.remove(id: saved.id))
        XCTAssertTrue(set.rules.isEmpty)
    }

    func testFieldRulesRoundTripThroughTheStore() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("MoliSwitchCoreTests-" + UUID().uuidString)
            .appendingPathComponent("field-rules.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = JSONFieldRuleStore(url: url)
        let saved = rule(searchField)

        XCTAssertEqual(try store.load(), [])
        try store.save([saved])
        XCTAssertEqual(try store.load(), [saved])
    }
}

final class AddressBarDetectorTests: XCTestCase {
    func testSafariAddressBarIsRecognisedByItsIdentifier() {
        let addressBar = FieldSignature(role: "AXTextField", identifier: "WEB_BROWSER_ADDRESS_AND_SEARCH_FIELD")

        XCTAssertTrue(AddressBarDetector.isBrowser(bundleIdentifier: "com.apple.Safari"))
        XCTAssertTrue(AddressBarDetector.isAddressBar(bundleIdentifier: "com.apple.Safari", field: addressBar))
        XCTAssertFalse(
            AddressBarDetector.isAddressBar(
                bundleIdentifier: "com.apple.Safari",
                field: FieldSignature(role: "AXTextField", descriptor: "Search", isInWebArea: true)
            )
        )
    }

    func testChromiumOmniboxIsRecognisedOutsideTheWebPage() {
        let omnibox = FieldSignature(role: "AXTextField", descriptor: "地址和搜索栏")
        var onAWebPage = omnibox
        onAWebPage.isInWebArea = true

        XCTAssertTrue(AddressBarDetector.isAddressBar(bundleIdentifier: "com.google.Chrome", field: omnibox))
        XCTAssertTrue(AddressBarDetector.isAddressBar(bundleIdentifier: "com.microsoft.edgemac", field: omnibox))
        XCTAssertFalse(AddressBarDetector.isAddressBar(bundleIdentifier: "com.google.Chrome", field: onAWebPage))
        XCTAssertFalse(
            AddressBarDetector.isAddressBar(
                bundleIdentifier: "com.google.Chrome",
                field: FieldSignature(role: "AXTextField", descriptor: "查找")
            )
        )
    }

    func testOtherApplicationsHaveNoAddressBar() {
        let omnibox = FieldSignature(role: "AXTextField", descriptor: "Address and search bar")

        XCTAssertFalse(AddressBarDetector.isBrowser(bundleIdentifier: "com.tencent.xinWeChat"))
        XCTAssertFalse(AddressBarDetector.isAddressBar(bundleIdentifier: "com.tencent.xinWeChat", field: omnibox))
    }
}
