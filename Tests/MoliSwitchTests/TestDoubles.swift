import Foundation

import MoliSwitchCore

@testable import MoliSwitchApp

// MARK: - Rule store

/// In-memory rule store with injectable load and save failures.
final class FakeRuleStore: RuleStore, @unchecked Sendable {
    struct Failure: Error, LocalizedError {
        let message: String

        var errorDescription: String? { message }
    }

    let url: URL

    private let lock = NSLock()
    private var storedRules: [AppRule]
    private var loadError: Error?
    private var saveError: Error?
    private var loadCountValue = 0
    private var saveCountValue = 0

    init(
        url: URL = URL(fileURLWithPath: "/tmp/MoliSwitchTests/rules.json"),
        rules: [AppRule] = []
    ) {
        self.url = url
        self.storedRules = rules
    }

    var rules: [AppRule] {
        lock.lock()
        defer { lock.unlock() }
        return storedRules
    }

    var loadCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return loadCountValue
    }

    var saveCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return saveCountValue
    }

    func setRules(_ rules: [AppRule]) {
        lock.lock()
        defer { lock.unlock() }
        storedRules = rules
    }

    func failLoading(with error: Error?) {
        lock.lock()
        defer { lock.unlock() }
        loadError = error
    }

    func failSaving(with error: Error?) {
        lock.lock()
        defer { lock.unlock() }
        saveError = error
    }

    func load() throws -> [AppRule] {
        lock.lock()
        defer { lock.unlock() }

        loadCountValue += 1

        if let loadError {
            throw loadError
        }

        return storedRules
    }

    func save(_ rules: [AppRule]) throws {
        lock.lock()
        defer { lock.unlock() }

        saveCountValue += 1

        if let saveError {
            throw saveError
        }

        storedRules = rules
    }
}

// MARK: - Input sources

@MainActor
final class FakeInputSourceManager: InputSourceManaging {
    var sources: [InputSource]
    var current: InputSource?
    /// Result returned by selectInputSource, so a failing switch can be injected.
    var selectionResult = true

    private(set) var invalidateCacheCount = 0
    private(set) var selectRequestCount = 0
    /// Every input source ID passed to selectInputSource, in order.
    private(set) var selectedIDs: [String] = []
    private(set) var startMonitoringCount = 0
    private(set) var stopMonitoringCount = 0
    private var selectionHandler: (@MainActor () -> Void)?

    init(sources: [InputSource], current: InputSource? = nil) {
        self.sources = sources
        self.current = current
    }

    func availableInputSources() -> [InputSource] {
        sources
    }

    func invalidateCache() {
        invalidateCacheCount += 1
    }

    func currentInputSource() -> InputSource? {
        current
    }

    func selectInputSource(id: String) -> Bool {
        selectRequestCount += 1
        selectedIDs.append(id)

        guard selectionResult else {
            return false
        }

        if let source = sources.first(where: { $0.id == id }) {
            current = source
        }

        return true
    }

    func startMonitoringEnabledSources(_ handler: @escaping @MainActor () -> Void) {
        startMonitoringCount += 1
    }

    func stopMonitoringEnabledSources() {
        stopMonitoringCount += 1
    }

    func startMonitoringSelectedSource(_ handler: @escaping @MainActor () -> Void) {
        selectionHandler = handler
    }

    func stopMonitoringSelectedSource() {
        selectionHandler = nil
    }

    /// Simulates a switch made outside the app, such as a global hot key.
    func simulateSelection(of source: InputSource) {
        current = source
        selectionHandler?()
    }
}

// MARK: - Application scanning

/// Scanner stub. scan() sleeps for the injected delay so overlapping refreshes
/// and cancellation can be driven deterministically from tests.
final class FakeApplicationScanner: ApplicationScanning, @unchecked Sendable {
    private let lock = NSLock()
    private var storedResult: ApplicationScanResult
    private var scanCountValue = 0
    private let delay: TimeInterval

    init(result: ApplicationScanResult = .empty, delay: TimeInterval = 0) {
        self.storedResult = result
        self.delay = delay
    }

    var scanCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return scanCountValue
    }

    func setResult(_ result: ApplicationScanResult) {
        lock.lock()
        defer { lock.unlock() }
        storedResult = result
    }

    func scan() -> ApplicationScanResult {
        lock.lock()
        scanCountValue += 1
        let result = storedResult
        lock.unlock()

        if delay > 0 {
            Thread.sleep(forTimeInterval: delay)
        }

        return result
    }
}

// MARK: - Login items

@MainActor
final class FakeInputSourceIndicator: InputSourceIndicatorControlling {
    var isEnabled = true
    private(set) var changes: [Bool] = []

    func setEnabled(_ enabled: Bool) {
        changes.append(enabled)
        isEnabled = enabled
    }
}

@MainActor
final class FakeLoginItemManager: LoginItemManaging {
    var status: LaunchAtLoginStatus = .notRegistered
    var registerError: Error?
    var unregisterError: Error?

    private(set) var registerCount = 0
    private(set) var unregisterCount = 0
    private(set) var openSystemSettingsCount = 0

    func register() throws {
        registerCount += 1

        if let registerError {
            throw registerError
        }

        status = .enabled
    }

    func unregister() throws {
        unregisterCount += 1

        if let unregisterError {
            throw unregisterError
        }

        status = .notRegistered
    }

    func openSystemSettingsLoginItems() {
        openSystemSettingsCount += 1
    }
}


// MARK: - Command rules

/// In-memory store for command rules.
final class FakeCommandRuleStore: CommandRuleStore, @unchecked Sendable {
    let url = URL(fileURLWithPath: "/tmp/MoliSwitchTests/command-rules.json")

    private let lock = NSLock()
    private var storedRules: [CommandRule]
    private var loadError: Error?

    init(rules: [CommandRule] = []) {
        self.storedRules = rules
    }

    var rules: [CommandRule] {
        lock.lock()
        defer { lock.unlock() }
        return storedRules
    }

    func failLoading(with error: Error?) {
        lock.lock()
        defer { lock.unlock() }
        loadError = error
    }

    func load() throws -> [CommandRule] {
        lock.lock()
        defer { lock.unlock() }
        if let loadError {
            throw loadError
        }
        return storedRules
    }

    func save(_ rules: [CommandRule]) throws {
        lock.lock()
        defer { lock.unlock() }
        storedRules = rules
    }
}

// MARK: - Terminal

/// Reports whatever program the test put in the foreground of the terminal.
@MainActor
final class FakeTerminalContextProvider: TerminalContextProviding {
    var supportedBundleIdentifiers: Set<String> = ["com.apple.Terminal", "com.googlecode.iterm2"]
    var result: TerminalContextResult = .unavailable
    private(set) var queryCount = 0

    func supportsTerminal(bundleIdentifier: String) -> Bool {
        supportedBundleIdentifiers.contains(bundleIdentifier)
    }

    func foregroundContext(bundleIdentifier: String) -> TerminalContextResult {
        queryCount += 1
        return result
    }

    func foregroundContextInBackground(bundleIdentifier: String) async -> TerminalContextResult {
        foregroundContext(bundleIdentifier: bundleIdentifier)
    }

    /// Puts a program in the foreground of a tab.
    func run(_ candidates: [String], tty: String = "/dev/ttys001") {
        result = .found(TerminalContext(tty: tty, candidates: candidates))
    }
}

// MARK: - Focused fields

final class FakeFieldRuleStore: FieldRuleStore, @unchecked Sendable {
    let url = URL(fileURLWithPath: "/tmp/MoliSwitchTests/field-rules.json")

    private let lock = NSLock()
    private var storedRules: [FieldRule]
    private var loadError: Error?

    init(rules: [FieldRule] = []) {
        self.storedRules = rules
    }

    var rules: [FieldRule] {
        lock.lock()
        defer { lock.unlock() }
        return storedRules
    }

    func failLoading(with error: Error?) {
        lock.lock()
        defer { lock.unlock() }
        loadError = error
    }

    func load() throws -> [FieldRule] {
        lock.lock()
        defer { lock.unlock() }
        if let loadError {
            throw loadError
        }
        return storedRules
    }

    func save(_ rules: [FieldRule]) throws {
        lock.lock()
        defer { lock.unlock() }
        storedRules = rules
    }
}

/// Reports whatever field the test put the cursor in.
@MainActor
final class FakeFocusedFieldProvider: FocusedFieldProviding {
    var isTrusted = true
    private(set) var requestTrustCount = 0
    private(set) var observedBundleIdentifier: String?
    /// What isCaretAtStart reports.
    var caretAtStart: Bool?
    private var field: FieldSignature?
    private var handler: (@MainActor (FieldSignature?) -> Void)?

    func requestTrust() {
        requestTrustCount += 1
    }

    func startObserving(bundleIdentifier: String, handler: @escaping @MainActor (FieldSignature?) -> Void) {
        observedBundleIdentifier = bundleIdentifier
        self.handler = handler
    }

    func stopObserving() {
        observedBundleIdentifier = nil
        handler = nil
    }

    func currentField() -> FieldSignature? {
        field
    }

    func isCaretAtStart() -> Bool? {
        caretAtStart
    }

    /// Moves keyboard focus, as a click into another field would.
    func focus(_ field: FieldSignature?) {
        self.field = field
        handler?(field)
    }
}

// MARK: - Slash commands

final class FakeSlashCommandAppStore: SlashCommandAppStore, @unchecked Sendable {
    let url: URL

    private let lock = NSLock()
    private var storedApps: [SlashCommandApp]
    private var loadError: Error?

    init(apps: [SlashCommandApp] = [], fileName: String = "slash-command-apps.json") {
        self.storedApps = apps
        self.url = URL(fileURLWithPath: "/tmp/MoliSwitchTests/" + fileName)
    }

    var apps: [SlashCommandApp] {
        lock.lock()
        defer { lock.unlock() }
        return storedApps
    }

    func failLoading(with error: Error?) {
        lock.lock()
        defer { lock.unlock() }
        loadError = error
    }

    func load() throws -> [SlashCommandApp] {
        lock.lock()
        defer { lock.unlock() }
        if let loadError {
            throw loadError
        }
        return storedApps
    }

    func save(_ apps: [SlashCommandApp]) throws {
        lock.lock()
        defer { lock.unlock() }
        storedApps = apps
    }
}

/// Lets a test press keys. Keys the runtime holds back count as typed once
/// they are released.
@MainActor
final class FakeKeyEventMonitor: KeyEventMonitoring {
    /// Whether start succeeds, as it does once Accessibility is allowed.
    var canStart = true
    private(set) var startCount = 0
    private(set) var releaseCount = 0
    /// Keys held back and not released yet.
    private(set) var heldKeys: [SlashCommandKey] = []
    /// Keys that reached the application, in order.
    private(set) var typedKeys: [SlashCommandKey] = []
    private var handler: (@MainActor (MonitoredKeyEvent) -> Bool)?

    var isRunning: Bool {
        handler != nil
    }

    @discardableResult
    func start(_ handler: @escaping @MainActor (MonitoredKeyEvent) -> Bool) -> Bool {
        startCount += 1
        guard canStart else { return false }
        self.handler = handler
        return true
    }

    func stop() {
        releaseHeldKeys()
        handler = nil
    }

    func releaseHeldKeys() {
        releaseCount += 1
        typedKeys += heldKeys
        heldKeys = []
    }

    /// Presses a key the way SystemKeyEventMonitor sees it.
    func press(_ key: SlashCommandKey, shifted: Bool = false) {
        let hold = handler?(.keyDown(key, shifted: shifted)) ?? false
        if hold || !heldKeys.isEmpty {
            heldKeys.append(key)
        } else {
            typedKeys.append(key)
        }
    }

    func press(_ keys: [SlashCommandKey]) {
        for key in keys {
            press(key)
        }
    }

    /// Lets go of both Shift keys.
    func releaseShift() {
        _ = handler?(.shiftReleased)
    }
}
