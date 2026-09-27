import Foundation
import MoliSwitchCore

/// Carries rules and settings over from AutoInputSwitcher, the app's previous
/// name, which used another bundle identifier and data directory.
@MainActor
struct LegacyMigration {
    static let legacyBundleIdentifier = "com.local.AutoInputSwitcher"
    static let completedKey = "didMigrateFromAutoInputSwitcher"
    static let ruleFileNames = ["rules.json", "command-rules.json", "field-rules.json"]
    static let defaultsKeys = [
        AppRuntime.showMenuBarIconKey,
        AppRuntime.chineseInputSourceIDKey,
        AppRuntime.englishInputSourceIDKey,
        AppRuntime.terminalSwitchingEnabledKey,
        AppRuntime.defaultInputSourceIDKey,
        AppRuntime.addressBarSwitchingEnabledKey,
        AppRuntime.addressBarInputSourceIDKey,
        "switchCount",
    ]

    let legacyDirectory: URL
    let directory: URL
    let legacyDefaults: UserDefaults?
    let defaults: UserDefaults

    static func forCurrentUser(defaults: UserDefaults = .standard) -> LegacyMigration {
        LegacyMigration(
            legacyDirectory: JSONRuleStore.applicationSupportDirectory(appName: "AutoInputSwitcher"),
            directory: JSONRuleStore.applicationSupportDirectory(),
            legacyDefaults: UserDefaults(suiteName: legacyBundleIdentifier),
            defaults: defaults
        )
    }

    /// Copies the files and settings that MoliSwitch does not have yet, once.
    /// The old ones stay in place. Has to run before defaults are registered,
    /// since a registered default hides that the setting was never saved.
    func migrateIfNeeded() {
        guard !defaults.bool(forKey: Self.completedKey) else {
            return
        }

        // A copy that failed is tried again on the next launch.
        if copyRuleFiles() {
            copySettings()
            defaults.set(true, forKey: Self.completedKey)
        }
    }

    private func copyRuleFiles() -> Bool {
        let fileManager = FileManager.default
        var succeeded = true

        for name in Self.ruleFileNames {
            let source = legacyDirectory.appendingPathComponent(name)
            let destination = directory.appendingPathComponent(name)
            guard
                fileManager.fileExists(atPath: source.path),
                !fileManager.fileExists(atPath: destination.path)
            else {
                continue
            }

            do {
                try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
                try fileManager.copyItem(at: source, to: destination)
            } catch {
                succeeded = false
            }
        }

        return succeeded
    }

    private func copySettings() {
        guard let legacyDefaults else {
            return
        }

        for key in Self.defaultsKeys where defaults.object(forKey: key) == nil {
            if let value = legacyDefaults.object(forKey: key) {
                defaults.set(value, forKey: key)
            }
        }
    }
}
