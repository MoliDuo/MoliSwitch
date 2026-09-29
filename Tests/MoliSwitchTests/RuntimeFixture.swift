import Foundation
import XCTest

import MoliSwitchCore

@testable import MoliSwitchApp

enum TestInputSources {
    static let us = InputSource(id: "com.apple.keylayout.US", name: "U.S.")
    static let abc = InputSource(id: "com.apple.keylayout.ABC", name: "ABC")
    static let shuangpin = InputSource(
        id: "com.apple.inputmethod.SCIM.Shuangpin",
        name: "Shuangpin – Simplified"
    )
    static let doubao = InputSource(
        id: "com.bytedance.inputmethod.doubaoime.pinyin",
        name: "豆包输入法"
    )

    static let all = [us, abc]
}

/// Everything a test needs to drive an AppRuntime without touching the real user
/// configuration, input sources or login items.
@MainActor
struct RuntimeFixture {
    let runtime: AppRuntime
    let store: FakeRuleStore
    let commandStore: FakeCommandRuleStore
    let fieldStore: FakeFieldRuleStore
    let slashCommandAppStore: FakeSlashCommandAppStore
    let keys: FakeKeyEventMonitor
    let fields: FakeFocusedFieldProvider
    let terminal: FakeTerminalContextProvider
    let inputSources: FakeInputSourceManager
    let scanner: FakeApplicationScanner
    let loginItems: FakeLoginItemManager
    let defaults: UserDefaults
    let suiteName: String
}

@MainActor
func makeFixture(
    rules: [AppRule] = [],
    commandRules: [CommandRule] = [],
    fieldRules: [FieldRule] = [],
    slashCommandApps: [SlashCommandApp] = [],
    installedApplications: [InstalledApplication] = [],
    sources: [InputSource] = TestInputSources.all,
    current: InputSource? = TestInputSources.us,
    scanDelay: TimeInterval = 0,
    scanRootCount: Int = 1
) -> RuntimeFixture {
    let suiteName = "MoliSwitchTests." + UUID().uuidString
    let defaults = UserDefaults(suiteName: suiteName) ?? .standard
    defaults.removePersistentDomain(forName: suiteName)

    let store = FakeRuleStore(rules: rules)
    let commandStore = FakeCommandRuleStore(rules: commandRules)
    let fieldStore = FakeFieldRuleStore(rules: fieldRules)
    let slashCommandAppStore = FakeSlashCommandAppStore(apps: slashCommandApps)
    let keys = FakeKeyEventMonitor()
    let fields = FakeFocusedFieldProvider()
    let terminal = FakeTerminalContextProvider()
    let inputSources = FakeInputSourceManager(sources: sources, current: current)
    let scanner = FakeApplicationScanner(
        result: ApplicationScanResult(
            applications: installedApplications,
            failedRoots: [],
            rootCount: scanRootCount
        ),
        delay: scanDelay
    )
    let loginItems = FakeLoginItemManager()

    let runtime = AppRuntime(
        store: store,
        commandStore: commandStore,
        fieldStore: fieldStore,
        slashCommandAppStore: slashCommandAppStore,
        keyEventMonitor: keys,
        slashCommandSwitchDelay: .zero,
        slashCommandRestoreDelay: .zero,
        focusedFieldProvider: fields,
        terminalContextProvider: terminal,
        terminalPollInterval: 0.02,
        inputSourceManager: inputSources,
        applicationScanner: scanner,
        loginItemManager: loginItems,
        switchCounter: SwitchCounter(defaults: defaults),
        defaults: defaults,
        updateController: nil,
        ownBundleIdentifier: "com.moli.MoliSwitch"
    )

    // Mimic a cold start, which loads the rules without reporting a status
    // message. The user triggered reload is a separate action and stays out of
    // the fixture so that tests can exercise it explicitly.
    runtime.reloadInputSources()
    runtime.loadRulesAtStartup()

    return RuntimeFixture(
        runtime: runtime,
        store: store,
        commandStore: commandStore,
        fieldStore: fieldStore,
        slashCommandAppStore: slashCommandAppStore,
        keys: keys,
        fields: fields,
        terminal: terminal,
        inputSources: inputSources,
        scanner: scanner,
        loginItems: loginItems,
        defaults: defaults,
        suiteName: suiteName
    )
}

func makeRule(
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

/// An application as the scanner would report it: present on disk.
func makeInstalledApplication(_ name: String, _ bundleIdentifier: String) -> InstalledApplication {
    InstalledApplication(
        name: name,
        bundleIdentifier: bundleIdentifier,
        url: URL(fileURLWithPath: "/Applications/" + name + ".app", isDirectory: true)
    )
}

@MainActor
func waitUntil(
    timeout: TimeInterval = 5,
    _ condition: () -> Bool
) async {
    let deadline = Date().addingTimeInterval(timeout)

    while Date() < deadline {
        if condition() {
            return
        }

        try? await Task.sleep(for: .milliseconds(10))
    }
}

@MainActor
extension RuntimeFixture {
    /// Runs the fixture scanner and waits until the runtime published its result.
    func scan() async {
        runtime.refreshApplications()
        await waitUntil { !runtime.isScanning }
    }
}
