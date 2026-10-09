import Foundation
import XCTest
@testable import MoliSwitchCore

final class JSONRuleStoreTests: XCTestCase {
    // MARK: - Helpers

    /// Runs the body inside a throwaway directory so tests never touch the real
    /// user configuration.
    private func withTemporaryDirectory(_ body: (URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "MoliSwitchCoreTests-" + UUID().uuidString,
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

    private func makeStore(in directory: URL) -> JSONRuleStore {
        JSONRuleStore(url: directory.appendingPathComponent("rules.json"))
    }

    private func makeRule(
        bundleIdentifier: String,
        applicationName: String = "Terminal",
        inputSourceID: String = "com.apple.keylayout.US",
        inputSourceName: String = "U.S."
    ) -> AppRule {
        AppRule(
            bundleIdentifier: bundleIdentifier,
            applicationName: applicationName,
            inputSourceID: inputSourceID,
            inputSourceName: inputSourceName
        )
    }

    // MARK: - Loading

    func testLoadReturnsEmptyRulesOnlyWhenTheFileIsMissing() throws {
        try withTemporaryDirectory { directory in
            let store = makeStore(in: directory)

            XCTAssertFalse(store.fileExists)
            XCTAssertEqual(try store.load(), [])
        }
    }

    func testEmptyRulesFileIsDistinguishedFromAMissingFile() throws {
        try withTemporaryDirectory { directory in
            let store = makeStore(in: directory)
            try Data("[]".utf8).write(to: store.url)

            XCTAssertTrue(store.fileExists)
            XCTAssertEqual(try store.load(), [])
        }
    }

    func testLoadThrowsOnCorruptJSONAndLeavesTheFileUntouched() throws {
        try withTemporaryDirectory { directory in
            let store = makeStore(in: directory)
            let original = Data("{ this is not a rule list".utf8)
            try original.write(to: store.url)

            XCTAssertThrowsError(try store.load())

            let onDisk = try Data(contentsOf: store.url)
            XCTAssertEqual(onDisk, original)
        }
    }

    func testLoadThrowsWhenThePathIsNotAReadableFile() throws {
        try withTemporaryDirectory { directory in
            let store = makeStore(in: directory)
            try FileManager.default.createDirectory(
                at: store.url,
                withIntermediateDirectories: false
            )

            XCTAssertThrowsError(try store.load())
        }
    }

    func testLoadThrowsWhenTheFileCannotBeRead() throws {
        try XCTSkipIf(getuid() == 0, "File permissions do not restrict the root user")

        try withTemporaryDirectory { directory in
            let store = makeStore(in: directory)
            try Data("[]".utf8).write(to: store.url)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o000],
                ofItemAtPath: store.url.path
            )
            defer {
                try? FileManager.default.setAttributes(
                    [.posixPermissions: 0o644],
                    ofItemAtPath: store.url.path
                )
            }

            XCTAssertThrowsError(try store.load())
        }
    }

    func testMissingFileDetectionIsLimitedToNoSuchFileErrors() {
        XCTAssertTrue(
            JSONRuleStore.isMissingFileError(
                NSError(domain: NSCocoaErrorDomain, code: NSFileReadNoSuchFileError)
            )
        )
        XCTAssertFalse(
            JSONRuleStore.isMissingFileError(
                NSError(domain: NSCocoaErrorDomain, code: NSFileReadNoPermissionError)
            )
        )
        XCTAssertTrue(
            JSONRuleStore.isMissingFileError(
                NSError(
                    domain: NSCocoaErrorDomain,
                    code: NSFileReadUnknownError,
                    userInfo: [
                        NSUnderlyingErrorKey: NSError(
                            domain: NSCocoaErrorDomain,
                            code: NSFileReadNoSuchFileError
                        ),
                    ]
                )
            )
        )
    }

    // MARK: - Saving

    func testSaveCreatesIntermediateDirectoriesAndRoundTrips() throws {
        try withTemporaryDirectory { directory in
            let store = JSONRuleStore(
                url: directory
                    .appendingPathComponent("nested", isDirectory: true)
                    .appendingPathComponent("rules.json")
            )
            let rules = [
                makeRule(bundleIdentifier: "com.apple.Terminal"),
                makeRule(
                    bundleIdentifier: "com.tencent.xinWeChat",
                    applicationName: "WeChat",
                    inputSourceID: "com.apple.inputmethod.SCIM.Shuangpin",
                    inputSourceName: "Shuangpin - Simplified"
                ),
            ]

            try store.save(rules)

            XCTAssertTrue(store.fileExists)
            XCTAssertEqual(try store.load(), rules)
        }
    }

    func testSavedFileKeepsTheExpectedJSONShape() throws {
        try withTemporaryDirectory { directory in
            let store = makeStore(in: directory)
            try store.save([makeRule(bundleIdentifier: "com.apple.Terminal")])

            let object = try JSONSerialization.jsonObject(
                with: Data(contentsOf: store.url)
            ) as? [[String: Any]]

            XCTAssertEqual(object?.count, 1)
            XCTAssertEqual(object?.first?["bundleIdentifier"] as? String, "com.apple.Terminal")
            XCTAssertEqual(object?.first?["applicationName"] as? String, "Terminal")
            XCTAssertEqual(object?.first?["inputSourceID"] as? String, "com.apple.keylayout.US")
            XCTAssertEqual(object?.first?["inputSourceName"] as? String, "U.S.")
        }
    }

    func testSaveFailureLeavesTheExistingFileUnchanged() throws {
        try XCTSkipIf(getuid() == 0, "File permissions do not restrict the root user")

        try withTemporaryDirectory { directory in
            let store = makeStore(in: directory)
            let original = [makeRule(bundleIdentifier: "com.apple.Terminal")]
            try store.save(original)

            // A read-only directory stops the atomic write from creating its
            // temporary file, so the original rules must survive untouched.
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o500],
                ofItemAtPath: directory.path
            )
            defer {
                try? FileManager.default.setAttributes(
                    [.posixPermissions: 0o755],
                    ofItemAtPath: directory.path
                )
            }

            XCTAssertThrowsError(
                try store.save([makeRule(bundleIdentifier: "com.apple.Safari")])
            )
            XCTAssertEqual(try store.load(), original)
        }
    }

    func testSavingAnEmptyRuleListLeavesAReadableEmptyFile() throws {
        try withTemporaryDirectory { directory in
            let store = makeStore(in: directory)

            try store.save([])
            try store.save([])

            XCTAssertTrue(store.fileExists)
            XCTAssertEqual(try store.load(), [])
        }
    }

    // MARK: - Location

    func testApplicationSupportStorePlacesRulesInApplicationSupport() {
        let store = JSONRuleStore.applicationSupportStore(appName: "MoliSwitchTests")

        XCTAssertEqual(store.url.lastPathComponent, "rules.json")
        XCTAssertEqual(
            store.url.deletingLastPathComponent().lastPathComponent,
            "MoliSwitchTests"
        )
        XCTAssertTrue(store.url.path.contains("Application Support"))
    }
}
