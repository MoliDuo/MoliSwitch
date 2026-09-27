import XCTest

@testable import MoliSwitchCore

final class ApplicationListFilterTests: XCTestCase {
    private let terminal = ApplicationListEntry(
        displayName: "Terminal",
        bundleIdentifier: "com.apple.Terminal"
    )
    private let weChat = ApplicationListEntry(
        displayName: "WeChat",
        bundleIdentifier: "com.tencent.xinWeChat"
    )
    private let leftoverRule = ApplicationListEntry(
        displayName: "Ghost",
        bundleIdentifier: "com.example.ghost",
        isInstalled: false
    )

    func testEntriesDefaultToInstalled() {
        XCTAssertTrue(terminal.isInstalled)
        XCTAssertFalse(leftoverRule.isInstalled)
    }

    func testDefaultFilterIncludesEverything() {
        let filter = ApplicationListFilter()

        XCTAssertTrue(filter.includes(terminal))
        XCTAssertTrue(filter.includes(weChat))
        XCTAssertTrue(filter.includes(leftoverRule))
    }

    func testQueryMatchesNameAndBundleIdentifierIgnoringCase() {
        let byName = ApplicationListFilter(query: "term")
        let byBundleIdentifier = ApplicationListFilter(query: "TENCENT")

        XCTAssertTrue(byName.includes(terminal))
        XCTAssertFalse(byName.includes(weChat))
        XCTAssertFalse(byBundleIdentifier.includes(terminal))
        XCTAssertTrue(byBundleIdentifier.includes(weChat))
    }

    func testQueryIsTrimmedBeforeMatching() {
        let filter = ApplicationListFilter(query: "   term   ")

        XCTAssertTrue(filter.includes(terminal))
    }

    func testConfiguredScopeKeepsRulesForApplicationsThatAreGone() {
        let filter = ApplicationListFilter(
            scope: .configured,
            configuredBundleIdentifiers: ["com.example.ghost"]
        )

        // A leftover rule stays visible even though the application is missing,
        // otherwise it could never be removed from the interface.
        XCTAssertTrue(filter.includes(leftoverRule))
        XCTAssertFalse(filter.includes(terminal))
        XCTAssertFalse(filter.includes(weChat))
    }

    func testUnconfiguredScopeRequiresInstalledAndUnconfiguredApplications() {
        let filter = ApplicationListFilter(
            scope: .unconfigured,
            configuredBundleIdentifiers: ["com.tencent.xinWeChat"]
        )

        XCTAssertTrue(filter.includes(terminal))
        XCTAssertFalse(filter.includes(weChat))
        XCTAssertFalse(filter.includes(leftoverRule))
    }

    func testScopeAndQueryApplyTogether() {
        let configured = ApplicationListFilter(
            query: "ghost",
            scope: .configured,
            configuredBundleIdentifiers: ["com.example.ghost"]
        )
        let configuredWithOtherQuery = ApplicationListFilter(
            query: "terminal",
            scope: .configured,
            configuredBundleIdentifiers: ["com.example.ghost"]
        )

        XCTAssertTrue(configured.includes(leftoverRule))
        XCTAssertFalse(configuredWithOtherQuery.includes(leftoverRule))
    }
}

