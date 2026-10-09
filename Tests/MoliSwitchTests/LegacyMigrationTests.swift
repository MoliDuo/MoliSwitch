import Foundation
import XCTest
@testable import MoliSwitchApp

@MainActor
final class LegacyMigrationTests: XCTestCase {
    private var root: URL!
    private var legacyDirectory: URL!
    private var directory: URL!
    private var suiteNames: [String] = []

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MoliSwitchMigrationTests-" + UUID().uuidString, isDirectory: true)
        legacyDirectory = root.appendingPathComponent("AutoInputSwitcher", isDirectory: true)
        directory = root.appendingPathComponent("MoliSwitch", isDirectory: true)
        try FileManager.default.createDirectory(at: legacyDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
        for name in suiteNames {
            UserDefaults().removePersistentDomain(forName: name)
        }
    }

    private func makeDefaults() -> UserDefaults {
        let name = "MoliSwitchMigrationTests." + UUID().uuidString
        suiteNames.append(name)
        return UserDefaults(suiteName: name)!
    }

    private func makeMigration(legacyDefaults: UserDefaults, defaults: UserDefaults) -> LegacyMigration {
        LegacyMigration(
            legacyDirectory: legacyDirectory,
            directory: directory,
            legacyDefaults: legacyDefaults,
            defaults: defaults
        )
    }

    private func write(_ text: String, to url: URL) throws {
        try Data(text.utf8).write(to: url)
    }

    private func read(_ url: URL) throws -> String {
        try String(contentsOf: url, encoding: .utf8)
    }

    func testCopiesRuleFilesAndSettings() throws {
        try write("[\"apps\"]", to: legacyDirectory.appendingPathComponent("rules.json"))
        try write("[\"commands\"]", to: legacyDirectory.appendingPathComponent("command-rules.json"))
        let legacyDefaults = makeDefaults()
        legacyDefaults.set(false, forKey: AppRuntime.showMenuBarIconKey)
        legacyDefaults.set(42, forKey: "switchCount")
        legacyDefaults.set(true, forKey: "voiceRestoreEnabled")
        let defaults = makeDefaults()

        makeMigration(legacyDefaults: legacyDefaults, defaults: defaults).migrateIfNeeded()

        XCTAssertEqual(try read(directory.appendingPathComponent("rules.json")), "[\"apps\"]")
        XCTAssertEqual(try read(directory.appendingPathComponent("command-rules.json")), "[\"commands\"]")
        XCTAssertFalse(FileManager.default
            .fileExists(atPath: directory.appendingPathComponent("field-rules.json").path))
        XCTAssertEqual(defaults.object(forKey: AppRuntime.showMenuBarIconKey) as? Bool, false)
        XCTAssertEqual(defaults.integer(forKey: "switchCount"), 42)
        XCTAssertNil(defaults.object(forKey: "voiceRestoreEnabled"))
        // The old files stay where they were.
        XCTAssertTrue(FileManager.default.fileExists(atPath: legacyDirectory.appendingPathComponent("rules.json").path))
    }

    func testWithoutAnOldVersionNothingIsCreated() throws {
        try FileManager.default.removeItem(at: legacyDirectory)
        let defaults = makeDefaults()

        makeMigration(legacyDefaults: makeDefaults(), defaults: defaults).migrateIfNeeded()

        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
        XCTAssertTrue(defaults.bool(forKey: LegacyMigration.completedKey))
    }

    func testExistingFilesAndSettingsAreKept() throws {
        try write("[\"old\"]", to: legacyDirectory.appendingPathComponent("rules.json"))
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try write("[\"new\"]", to: directory.appendingPathComponent("rules.json"))
        let legacyDefaults = makeDefaults()
        legacyDefaults.set("old", forKey: AppRuntime.chineseInputSourceIDKey)
        let defaults = makeDefaults()
        defaults.set("new", forKey: AppRuntime.chineseInputSourceIDKey)

        makeMigration(legacyDefaults: legacyDefaults, defaults: defaults).migrateIfNeeded()

        XCTAssertEqual(try read(directory.appendingPathComponent("rules.json")), "[\"new\"]")
        XCTAssertEqual(defaults.string(forKey: AppRuntime.chineseInputSourceIDKey), "new")
    }

    func testRunsOnlyOnce() throws {
        let legacyDefaults = makeDefaults()
        let defaults = makeDefaults()
        let migration = makeMigration(legacyDefaults: legacyDefaults, defaults: defaults)
        migration.migrateIfNeeded()

        try write("[\"later\"]", to: legacyDirectory.appendingPathComponent("rules.json"))
        legacyDefaults.set(7, forKey: "switchCount")
        migration.migrateIfNeeded()

        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("rules.json").path))
        XCTAssertNil(defaults.object(forKey: "switchCount"))
    }
}
