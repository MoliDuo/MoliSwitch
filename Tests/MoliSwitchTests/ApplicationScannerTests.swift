import Foundation
import XCTest
@testable import MoliSwitchApp

final class ApplicationScannerTests: XCTestCase {
    // MARK: - Helpers

    private func withTemporaryDirectory(_ body: (URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "MoliSwitchScannerTests-" + UUID().uuidString,
                isDirectory: true
            )

        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: directory.path
            )
            try? FileManager.default.removeItem(at: directory)
        }

        try body(directory)
    }

    private func makeApplicationBundle(
        in root: URL,
        name: String,
        bundleIdentifier: String,
        extraInfo: [String: Any] = [:]
    ) throws {
        let contents = root
            .appendingPathComponent(name + ".app", isDirectory: true)
            .appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(
            at: contents,
            withIntermediateDirectories: true
        )

        let plist: [String: Any] = [
            "CFBundleIdentifier": bundleIdentifier,
            "CFBundleName": name,
            "CFBundleDisplayName": name,
            "CFBundlePackageType": "APPL",
            "CFBundleExecutable": name,
        ].merging(extraInfo) { _, extra in extra }
        let data = try PropertyListSerialization.data(
            fromPropertyList: plist,
            format: .xml,
            options: 0
        )
        try data.write(to: contents.appendingPathComponent("Info.plist"))
    }

    // MARK: - Search roots

    func testDefaultSearchRootsAreInPriorityOrder() {
        let roots = InstalledApplicationScanner().searchRoots().map(\.path)

        XCTAssertEqual(roots.count, 4)
        XCTAssertTrue(roots[0].hasSuffix("/Applications"))
        XCTAssertEqual(roots[1], "/Applications")
        XCTAssertEqual(roots[2], "/System/Applications")
        XCTAssertEqual(roots[3], "/System/Library/CoreServices")
    }

    func testExplicitRootsAreUsedAsGiven() {
        let roots = [URL(fileURLWithPath: "/tmp/one"), URL(fileURLWithPath: "/tmp/two")]

        XCTAssertEqual(InstalledApplicationScanner(roots: roots).searchRoots(), roots)
    }

    // MARK: - Scanning

    func testScanReadsApplicationsFromEveryRoot() throws {
        try withTemporaryDirectory { directory in
            let first = directory.appendingPathComponent("first", isDirectory: true)
            let second = directory.appendingPathComponent("second", isDirectory: true)
            try FileManager.default.createDirectory(at: first, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: second, withIntermediateDirectories: true)
            try makeApplicationBundle(
                in: first,
                name: "Terminal",
                bundleIdentifier: "com.apple.Terminal"
            )
            try makeApplicationBundle(
                in: second,
                name: "Safari",
                bundleIdentifier: "com.apple.Safari"
            )

            let result = InstalledApplicationScanner(roots: [first, second]).scan()

            XCTAssertEqual(
                result.applications.map(\.bundleIdentifier),
                ["com.apple.Safari", "com.apple.Terminal"]
            )
            XCTAssertTrue(result.failedRoots.isEmpty)
            XCTAssertEqual(result.rootCount, 2)
            XCTAssertFalse(result.isPartialFailure)
            XCTAssertFalse(result.isTotalFailure)
        }
    }

    func testDuplicateBundleIdentifiersKeepTheHigherPriorityRoot() throws {
        try withTemporaryDirectory { directory in
            let preferred = directory.appendingPathComponent("preferred", isDirectory: true)
            let fallback = directory.appendingPathComponent("fallback", isDirectory: true)
            try FileManager.default.createDirectory(
                at: preferred,
                withIntermediateDirectories: true
            )
            try FileManager.default.createDirectory(
                at: fallback,
                withIntermediateDirectories: true
            )
            try makeApplicationBundle(
                in: preferred,
                name: "Example",
                bundleIdentifier: "com.example.app"
            )
            try makeApplicationBundle(
                in: fallback,
                name: "Example",
                bundleIdentifier: "com.example.app"
            )

            let result = InstalledApplicationScanner(roots: [preferred, fallback]).scan()

            XCTAssertEqual(result.applications.count, 1)
            XCTAssertEqual(
                result.applications.first?.url?.standardizedFileURL.path,
                preferred.appendingPathComponent("Example.app").standardizedFileURL.path
            )
        }
    }

    func testMissingRootIsReportedAsAPartialFailure() throws {
        try withTemporaryDirectory { directory in
            let existing = directory.appendingPathComponent("existing", isDirectory: true)
            try FileManager.default.createDirectory(at: existing, withIntermediateDirectories: true)
            try makeApplicationBundle(
                in: existing,
                name: "Terminal",
                bundleIdentifier: "com.apple.Terminal"
            )
            let missing = directory.appendingPathComponent("missing", isDirectory: true)

            let result = InstalledApplicationScanner(roots: [existing, missing]).scan()

            XCTAssertEqual(result.applications.count, 1)
            XCTAssertEqual(result.failedRoots.map(\.path), [missing.path])
            XCTAssertTrue(result.isPartialFailure)
            XCTAssertFalse(result.isTotalFailure)
        }
    }

    func testEveryRootFailingIsATotalFailure() throws {
        try withTemporaryDirectory { directory in
            let first = directory.appendingPathComponent("one", isDirectory: true)
            let second = directory.appendingPathComponent("two", isDirectory: true)

            let result = InstalledApplicationScanner(roots: [first, second]).scan()

            XCTAssertTrue(result.applications.isEmpty)
            XCTAssertEqual(result.failedRoots.count, 2)
            XCTAssertTrue(result.isTotalFailure)
            XCTAssertFalse(result.isPartialFailure)
        }
    }

    func testUnreadableRootIsReportedInsteadOfSilentlyReturningNothing() throws {
        try XCTSkipIf(getuid() == 0, "File permissions do not restrict the root user")

        try withTemporaryDirectory { directory in
            let locked = directory.appendingPathComponent("locked", isDirectory: true)
            let readable = directory.appendingPathComponent("readable", isDirectory: true)
            try FileManager.default.createDirectory(at: locked, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(
                at: readable,
                withIntermediateDirectories: true
            )
            try makeApplicationBundle(
                in: readable,
                name: "Terminal",
                bundleIdentifier: "com.apple.Terminal"
            )
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o000],
                ofItemAtPath: locked.path
            )
            defer {
                try? FileManager.default.setAttributes(
                    [.posixPermissions: 0o755],
                    ofItemAtPath: locked.path
                )
            }

            let result = InstalledApplicationScanner(roots: [locked, readable]).scan()

            XCTAssertEqual(result.failedRoots.map(\.path), [locked.path])
            XCTAssertEqual(result.applications.map(\.bundleIdentifier), ["com.apple.Terminal"])
            XCTAssertTrue(result.isPartialFailure)
        }
    }

    func testBundlesWithoutAnIdentifierAreIgnored() throws {
        try withTemporaryDirectory { directory in
            let root = directory.appendingPathComponent("root", isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            try makeApplicationBundle(
                in: root,
                name: "Identifierless",
                bundleIdentifier: ""
            )
            try makeApplicationBundle(
                in: root,
                name: "Terminal",
                bundleIdentifier: "com.apple.Terminal"
            )

            let result = InstalledApplicationScanner(roots: [root]).scan()

            XCTAssertEqual(result.applications.map(\.bundleIdentifier), ["com.apple.Terminal"])
        }
    }

    // MARK: - Result classification

    func testBackgroundHelpersAreSkipped() throws {
        try withTemporaryDirectory { root in
            try makeApplicationBundle(in: root, name: "Editor", bundleIdentifier: "com.example.editor")
            try makeApplicationBundle(
                in: root,
                name: "Snipper",
                bundleIdentifier: "com.example.snipper",
                extraInfo: ["LSUIElement": true, "CFBundleIconName": "AppIcon"]
            )
            try makeApplicationBundle(
                in: root,
                name: "Forwarder",
                bundleIdentifier: "com.example.forwarder",
                extraInfo: ["LSBackgroundOnly": true, "CFBundleIconFile": "AppIcon"]
            )
            try makeApplicationBundle(
                in: root,
                name: "Agent",
                bundleIdentifier: "com.example.agent",
                extraInfo: ["LSUIElement": "1"]
            )

            let result = InstalledApplicationScanner(roots: [root]).scan()

            XCTAssertEqual(result.applications.map(\.bundleIdentifier), ["com.example.editor", "com.example.snipper"])
        }
    }

    func testInvisibleDisplayNameFallsBackToTheBundleName() throws {
        try withTemporaryDirectory { root in
            try makeApplicationBundle(
                in: root,
                name: "MediaHelper",
                bundleIdentifier: "com.example.media",
                extraInfo: ["CFBundleDisplayName": "\u{200E}"]
            )

            let result = InstalledApplicationScanner(roots: [root]).scan()

            XCTAssertEqual(result.applications.map(\.name), ["MediaHelper"])
        }
    }

    func testResultClassification() {
        let root = URL(fileURLWithPath: "/Applications", isDirectory: true)

        XCTAssertEqual(ApplicationScanResult.empty, ApplicationScanResult(
            applications: [],
            failedRoots: [],
            rootCount: 0
        ))

        let healthy = ApplicationScanResult(applications: [], failedRoots: [], rootCount: 3)
        XCTAssertFalse(healthy.isPartialFailure)
        XCTAssertFalse(healthy.isTotalFailure)

        let partial = ApplicationScanResult(
            applications: [],
            failedRoots: [root],
            rootCount: 3
        )
        XCTAssertTrue(partial.isPartialFailure)
        XCTAssertFalse(partial.isTotalFailure)

        let total = ApplicationScanResult(
            applications: [],
            failedRoots: [root, root],
            rootCount: 2
        )
        XCTAssertTrue(total.isTotalFailure)
        XCTAssertFalse(total.isPartialFailure)

        // A scan with no roots at all is not a failure.
        XCTAssertFalse(ApplicationScanResult.empty.isTotalFailure)
    }
}
