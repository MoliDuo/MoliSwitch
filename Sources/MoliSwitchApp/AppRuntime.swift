import AppKit
import Foundation
import MoliSwitchCore

@MainActor
final class AppRuntime: ObservableObject {
    static let showMenuBarIconKey = "showMenuBarIcon"
    static let chineseInputSourceIDKey = "chineseInputSourceID"
    static let englishInputSourceIDKey = "englishInputSourceID"
    static let terminalSwitchingEnabledKey = "terminalSwitchingEnabled"
    static let defaultInputSourceIDKey = "defaultInputSourceID"
    static let addressBarSwitchingEnabledKey = "addressBarSwitchingEnabled"
    static let addressBarInputSourceIDKey = "addressBarInputSourceID"
    static let slashCommandSwitchingEnabledKey = "slashCommandSwitchingEnabled"
    static let slashCommandRestoresOnSpaceKey = "slashCommandRestoresOnSpace"
    /// Not shown in the settings: how long a slash waits after the switch, in
    /// milliseconds, for trying out what an application needs.
    static let slashCommandSwitchDelayKey = "slashCommandSwitchDelayMilliseconds"
    /// Not shown in the settings: whether switching back after Shift or a slash
    /// command presses the system shortcut "Select the previous input source"
    /// instead of selecting the input source directly. On unless set to false.
    static let restoreUsesSystemShortcutKey = "restoreUsesSystemShortcut"
    static let shiftEnglishEnabledKey = "shiftEnglishEnabled"
    static let usageLoggingEnabledKey = "usageLoggingEnabled"
    static let shiftRestoresOnReleaseKey = "shiftRestoresOnRelease"
    /// Read only, to carry the categories chosen before keys were chosen one
    /// by one over into shiftEnglishKeyCodesKey.
    static let shiftEnglishCategoriesKey = "shiftEnglishCategories"
    static let shiftEnglishKeyCodesKey = "shiftEnglishKeyCodes"
    /// Set once the applications where Shift did not switch were carried over
    /// into shift-app-rules.json.
    static let shiftExcludedAppsMigratedKey = "didMigrateShiftExcludedApps"
    /// Settings picker value for "detect the input source automatically".
    static let automaticInputSourceID = ""
    /// Picker value of an application without a rule, which switches to the
    /// default input source.
    static let followDefaultInputSourceID = "default"
    /// Rule values that follow the Chinese or English input source chosen in the
    /// settings instead of naming one input source.
    static let chineseRuleID = "role.chinese"
    static let englishRuleID = "role.english"

    static var noSwitchInputSourceID: String {
        RuleSet.noSwitchInputSourceID
    }

    @Published private(set) var currentApplication: RunningApplicationInfo?
    @Published private(set) var currentInputSource: InputSource?
    @Published private(set) var installedApplications: [InstalledApplication] = []
    @Published private(set) var inputSources: [InputSource] = []
    @Published private(set) var ruleSet = RuleSet()
    @Published private(set) var commandRuleSet = CommandRuleSet()
    @Published private(set) var commandRuleEditingEnabled = true
    @Published private(set) var fieldRuleSet = FieldRuleSet()
    @Published private(set) var fieldRuleEditingEnabled = true
    @Published private(set) var slashCommandApps = SlashCommandAppList()
    @Published private(set) var slashCommandAppEditingEnabled = true
    /// Applications with their own Shift settings.
    @Published private(set) var shiftAppRules = ShiftAppRuleList()
    @Published private(set) var shiftAppRuleEditingEnabled = true
    /// True when key presses cannot be seen although everything asks for it.
    @Published private(set) var keyMonitoringUnavailable = false
    /// Whether MoliSwitch may use Accessibility to see the focused field.
    @Published private(set) var accessibilityTrusted = false
    /// The program most recently seen in the foreground of a terminal tab.
    @Published private(set) var lastTerminalContext: TerminalContext?
    /// True when the user did not allow reading the terminal's active tab.
    @Published private(set) var terminalAccessDenied = false
    @Published private(set) var switchCount = 0
    @Published private(set) var launchAtLoginStatus: LaunchAtLoginStatus = .notRegistered
    /// Whether the system shows the input source next to the caret after a switch.
    @Published private(set) var inputSourceIndicatorEnabled = true
    @Published private(set) var isScanning = false
    @Published private(set) var ruleEditingEnabled = true
    @Published private(set) var iconCacheGeneration = 0

    @Published private(set) var storageStatus: StatusMessage?
    @Published private(set) var scanStatus: StatusMessage?
    @Published private(set) var inputSourceStatus: StatusMessage?
    @Published private(set) var loginStatus: StatusMessage?

    @Published var searchText = ""
    /// The application whose settings show beside the application table.
    @Published var selectedApplicationID: String?
    @Published var applicationListScope: ApplicationListScope = .all
    @Published var showMenuBarIcon: Bool {
        didSet {
            guard showMenuBarIcon != oldValue else { return }
            defaults.set(showMenuBarIcon, forKey: Self.showMenuBarIconKey)
            logUsage("setting", ["name": "showMenuBarIcon", "value": .string("\(showMenuBarIcon)")])
        }
    }

    /// Whether what happens is written to the usage log on this Mac.
    @Published var usageLoggingEnabled: Bool {
        didSet {
            guard usageLoggingEnabled != oldValue else { return }
            defaults.set(usageLoggingEnabled, forKey: Self.usageLoggingEnabledKey)
            if usageLoggingEnabled {
                usageLogger.isEnabled = true
                logUsage("setting", ["name": "usageLoggingEnabled", "value": "true"])
                logSnapshot("loggingEnabled")
            } else {
                fieldTextTask?.cancel()
                logUsage("setting", ["name": "usageLoggingEnabled", "value": "false"])
                usageLogger.flush()
                usageLogger.isEnabled = false
            }
            updateKeyMonitoring()
            refreshFieldObservation()
        }
    }

    /// Whether command rules apply in Terminal and iTerm2.
    @Published var terminalSwitchingEnabled: Bool {
        didSet {
            guard terminalSwitchingEnabled != oldValue else { return }
            defaults.set(terminalSwitchingEnabled, forKey: Self.terminalSwitchingEnabledKey)
            logUsage("setting", ["name": "terminalSwitchingEnabled", "value": .string("\(terminalSwitchingEnabled)")])
            updateTerminalPolling(for: currentApplication)
        }
    }

    /// The chosen Chinese input source, or automaticInputSourceID.
    @Published var chineseInputSourceSelection: String {
        didSet {
            guard chineseInputSourceSelection != oldValue else { return }
            let previous = resolveInputSource(oldValue) { detectedChineseInputSource }
            persistSelection(chineseInputSourceSelection, forKey: Self.chineseInputSourceIDKey)
            logUsage("setting", ["name": "chineseInputSource", "value": .string(chineseInputSourceSelection)])
            adoptRole(Self.chineseRuleID, forRulesUsing: previous)
        }
    }

    /// The chosen English input source, or automaticInputSourceID.
    @Published var englishInputSourceSelection: String {
        didSet {
            guard englishInputSourceSelection != oldValue else { return }
            let previous = resolveInputSource(oldValue) { detectedEnglishInputSource }
            persistSelection(englishInputSourceSelection, forKey: Self.englishInputSourceIDKey)
            logUsage("setting", ["name": "englishInputSource", "value": .string(englishInputSourceSelection)])
            adoptRole(Self.englishRuleID, forRulesUsing: previous)
        }
    }

    /// Whether the address bar of a browser switches to its own input source.
    @Published var addressBarSwitchingEnabled: Bool {
        didSet {
            guard addressBarSwitchingEnabled != oldValue else { return }
            defaults.set(addressBarSwitchingEnabled, forKey: Self.addressBarSwitchingEnabledKey)
            logUsage(
                "setting",
                ["name": "addressBarSwitchingEnabled", "value": .string("\(addressBarSwitchingEnabled)")]
            )
            refreshFieldObservation()
        }
    }

    /// The input source of browser address bars: a role or an input source.
    @Published var addressBarInputSourceSelection: String {
        didSet {
            guard addressBarInputSourceSelection != oldValue else { return }
            defaults.set(addressBarInputSourceSelection, forKey: Self.addressBarInputSourceIDKey)
            logUsage(
                "setting",
                ["name": "addressBarInputSourceSelection", "value": .string("\(addressBarInputSourceSelection)")]
            )
            refreshFieldObservation()
        }
    }

    /// Whether a slash at the start of the input switches to the English input
    /// source in the applications of slashCommandApps.
    @Published var slashCommandSwitchingEnabled: Bool {
        didSet {
            guard slashCommandSwitchingEnabled != oldValue else { return }
            defaults.set(slashCommandSwitchingEnabled, forKey: Self.slashCommandSwitchingEnabledKey)
            logUsage(
                "setting",
                ["name": "slashCommandSwitchingEnabled", "value": .string("\(slashCommandSwitchingEnabled)")]
            )
            updateKeyMonitoring()
            refreshFieldObservation()
        }
    }

    /// Whether a space ends a slash command, like Return does.
    @Published var slashCommandRestoresOnSpace: Bool {
        didSet {
            guard slashCommandRestoresOnSpace != oldValue else { return }
            defaults.set(slashCommandRestoresOnSpace, forKey: Self.slashCommandRestoresOnSpaceKey)
            logUsage(
                "setting",
                ["name": "slashCommandRestoresOnSpace", "value": .string("\(slashCommandRestoresOnSpace)")]
            )
            slashCommandTracker.restoresOnSpace = slashCommandRestoresOnSpace
        }
    }

    /// Whether characters typed with Shift held are typed with the English
    /// input source, as globalShiftOptions or the application's rule says.
    @Published var shiftEnglishEnabled: Bool {
        didSet {
            guard shiftEnglishEnabled != oldValue else { return }
            defaults.set(shiftEnglishEnabled, forKey: Self.shiftEnglishEnabledKey)
            logUsage("setting", ["name": "shiftEnglishEnabled", "value": .string("\(shiftEnglishEnabled)")])
            if !shiftEnglishEnabled {
                shiftTracker.cancel()
            }
            updateKeyMonitoring()
        }
    }

    /// Whether letting go of Shift switches back to the input source used before.
    @Published var shiftRestoresOnRelease: Bool {
        didSet {
            guard shiftRestoresOnRelease != oldValue else { return }
            defaults.set(shiftRestoresOnRelease, forKey: Self.shiftRestoresOnReleaseKey)
            logUsage("setting", ["name": "shiftRestoresOnRelease", "value": .string("\(shiftRestoresOnRelease)")])
        }
    }

    /// The keys that switch to English with Shift held, in applications
    /// without a rule of their own.
    @Published var shiftEnglishKeyCodes: Set<Int> {
        didSet {
            guard shiftEnglishKeyCodes != oldValue else { return }
            defaults.set(shiftEnglishKeyCodes.sorted(), forKey: Self.shiftEnglishKeyCodesKey)
            logUsage(
                "setting",
                ["name": "shiftEnglishKeyCodes", "value": .array(shiftEnglishKeyCodes.sorted().map(JSONValue.int))]
            )
        }
    }

    /// What applications without a rule switch to: noSwitchInputSourceID, a
    /// role, or an input source.
    @Published var defaultInputSourceSelection: String {
        didSet {
            guard defaultInputSourceSelection != oldValue else { return }
            logUsage("setting", ["name": "defaultInputSource", "value": .string(defaultInputSourceSelection)])
            if defaultInputSourceSelection == Self.noSwitchInputSourceID {
                defaults.removeObject(forKey: Self.defaultInputSourceIDKey)
            } else {
                defaults.set(defaultInputSourceSelection, forKey: Self.defaultInputSourceIDKey)
            }
        }
    }

    private let store: any RuleStore
    private let commandStore: any CommandRuleStore
    private let fieldStore: any FieldRuleStore
    private let suggestionLinesProvider: @Sendable () -> [String]
    private let slashCommandAppStore: any SlashCommandAppStore
    private let shiftAppRuleStore: any ShiftAppRuleStore
    /// The applications where Shift did not switch, from before Shift had
    /// settings per application; only read to carry them over.
    private let shiftExcludedAppStore: any SlashCommandAppStore
    private let keyEventMonitor: any KeyEventMonitoring
    private let slashCommandSwitchDelay: Duration
    private let slashCommandRestoreDelay: Duration
    private let shiftRestoreDelay: Duration
    private let focusedFieldProvider: any FocusedFieldProviding
    private let terminalContextProvider: any TerminalContextProviding
    private let terminalPollInterval: TimeInterval
    private let inputSourceManager: any InputSourceManaging
    private let applicationScanner: any ApplicationScanning
    private let loginItemManager: any LoginItemManaging
    private let inputSourceIndicator: any InputSourceIndicatorControlling
    private let switchCounter: SwitchCounter
    private let usageLogger: any UsageLogging
    /// Reads what the system says about input methods for the usage log. Nil
    /// in tests, where there is no real system to read.
    private let inputMethodProbe: InputMethodProbe?
    private let defaults: UserDefaults
    private let ownBundleIdentifier: String?
    let updateController: UpdateController?

    private var scanTask: Task<Void, Never>?
    private var activationObserver: NSObjectProtocol?
    private var hasStarted = false
    private var hasStopped = false

    /// Bookkeeping for the usage log.
    /// The input source this app asked for last, to tell its own switches from
    /// the user's when the system reports a change.
    private var pendingSelfSwitch: (id: String, mono: Double)?
    /// The previous change the user made, to tell a real switch from the
    /// system reporting one toggle twice (there and straight back).
    private var lastManualChange: (from: String?, to: String?, mono: Double)?
    private var fieldTextTask: Task<Void, Never>?
    private var lastLoggedFieldText: (identity: String, text: String)?
    private var lastFieldDetailsKey: String?
    private var lastFocusMono: Double?
    /// The input source the system reported last.
    private var lastObservedSourceID: String?
    /// For the Caps Lock log: when a modifier last changed, when Caps Lock
    /// last changed, and the readbacks still to come after the latest press.
    private var lastModifierMono: Double?
    private var lastCapsMono: Double?
    private var recentCapsMonos: [Double] = []
    private var capsReadbackTasks: [Task<Void, Never>] = []
    /// For the input method probes: a number for each switch and each probed
    /// key, when this app last switched, and the pending probe after a pause.
    private var switchSequence = 0
    private var keySequence = 0
    private var lastOwnSwitchMono: Double?
    private var lastKeyFieldProbeMono: Double = 0
    private var keyPauseProbeTask: Task<Void, Never>?
    private var snapshotTask: Task<Void, Never>?
    private var terminalUnavailableLogged = false

    private var terminalPollTask: Task<Void, Never>?
    private var polledApplication: RunningApplicationInfo?
    /// Key of the rule applied last, so a rule is applied once per context and a
    /// manual switch inside the same program is kept.
    private var appliedRuleKey: String?
    /// The terminal program the rule in effect was chosen for.
    private var terminalContextInEffect: TerminalContext?

    /// The application whose focused field is followed, and that field.
    private var fieldApplication: RunningApplicationInfo?
    private var focusedField: FieldSignature?
    /// What to return to when focus leaves a field that has a rule of its own
    /// and nothing else applies: the input source used before the field, as long
    /// as the one the field switched to is still selected.
    private var fieldRestore: (previousID: String, fieldID: String?)?

    private var slashCommandTracker: SlashCommandTracker

    private var shiftTracker = ShiftEnglishTracker()
    /// Types the key held back for Shift once the English input source is in.
    private var shiftSwitchTask: Task<Void, Never>?
    /// Switches back after Shift was let go; keys wait for it meanwhile.
    private var shiftRestoreTask: Task<Void, Never>?
    private var shiftRestoreHoldsKeys = false

    init(
        store: any RuleStore = JSONRuleStore.applicationSupportStore(),
        commandStore: any CommandRuleStore = JSONCommandRuleStore.applicationSupportStore(),
        fieldStore: any FieldRuleStore = JSONFieldRuleStore.applicationSupportStore(),
        slashCommandAppStore: any SlashCommandAppStore = JSONSlashCommandAppStore.applicationSupportStore(),
        shiftAppRuleStore: any ShiftAppRuleStore = JSONShiftAppRuleStore.applicationSupportStore(),
        shiftExcludedAppStore: any SlashCommandAppStore = JSONSlashCommandAppStore.applicationSupportStore(
            fileName: "shift-excluded-apps.json"
        ),
        keyEventMonitor: any KeyEventMonitoring = SystemKeyEventMonitor(),
        slashCommandSwitchDelay: Duration = .milliseconds(20),
        slashCommandRestoreDelay: Duration = .milliseconds(80),
        shiftRestoreDelay: Duration = .milliseconds(20),
        focusedFieldProvider: any FocusedFieldProviding = SystemFocusedFieldProvider(),
        terminalContextProvider: any TerminalContextProviding = SystemTerminalContextProvider(),
        terminalPollInterval: TimeInterval = 0.5,
        inputSourceManager: any InputSourceManaging = SystemInputSourceManager(),
        applicationScanner: any ApplicationScanning = InstalledApplicationScanner(),
        loginItemManager: any LoginItemManaging = SystemLoginItemManager(),
        inputSourceIndicator: any InputSourceIndicatorControlling = SystemInputSourceIndicator(),
        switchCounter: SwitchCounter = SwitchCounter(),
        usageLogger: any UsageLogging = JSONLUsageLogger(),
        inputMethodProbe: InputMethodProbe? = nil,
        suggestionLines: (@Sendable () -> [String])? = nil,
        defaults: UserDefaults = .standard,
        updateController: UpdateController? = nil,
        ownBundleIdentifier: String? = Bundle.main.bundleIdentifier
    ) {
        self.store = store
        self.commandStore = commandStore
        self.fieldStore = fieldStore
        suggestionLinesProvider = suggestionLines ?? UsageAnalyzer.linesOfUsageLog
        self.slashCommandAppStore = slashCommandAppStore
        self.shiftAppRuleStore = shiftAppRuleStore
        self.shiftExcludedAppStore = shiftExcludedAppStore
        self.keyEventMonitor = keyEventMonitor
        self.slashCommandSwitchDelay = slashCommandSwitchDelay
        self.slashCommandRestoreDelay = slashCommandRestoreDelay
        self.shiftRestoreDelay = shiftRestoreDelay
        self.focusedFieldProvider = focusedFieldProvider
        self.terminalContextProvider = terminalContextProvider
        self.terminalPollInterval = terminalPollInterval
        self.inputSourceManager = inputSourceManager
        self.applicationScanner = applicationScanner
        self.loginItemManager = loginItemManager
        self.inputSourceIndicator = inputSourceIndicator
        self.switchCounter = switchCounter
        self.usageLogger = usageLogger
        self.inputMethodProbe = inputMethodProbe
        self.defaults = defaults
        self.updateController = updateController
        self.ownBundleIdentifier = ownBundleIdentifier
        showMenuBarIcon = defaults.object(forKey: Self.showMenuBarIconKey) as? Bool ?? true
        usageLoggingEnabled = defaults.object(forKey: Self.usageLoggingEnabledKey) as? Bool ?? true
        terminalSwitchingEnabled = defaults.object(forKey: Self.terminalSwitchingEnabledKey) as? Bool ?? true
        chineseInputSourceSelection = defaults.string(forKey: Self.chineseInputSourceIDKey)
            ?? Self.automaticInputSourceID
        englishInputSourceSelection = defaults.string(forKey: Self.englishInputSourceIDKey)
            ?? Self.automaticInputSourceID
        defaultInputSourceSelection = defaults.string(forKey: Self.defaultInputSourceIDKey)
            ?? Self.noSwitchInputSourceID
        addressBarSwitchingEnabled = defaults.object(forKey: Self.addressBarSwitchingEnabledKey) as? Bool ?? true
        addressBarInputSourceSelection = defaults.string(forKey: Self.addressBarInputSourceIDKey)
            ?? Self.englishRuleID
        slashCommandSwitchingEnabled = defaults.object(forKey: Self.slashCommandSwitchingEnabledKey) as? Bool
            ?? true
        let restoresOnSpace = defaults.bool(forKey: Self.slashCommandRestoresOnSpaceKey)
        slashCommandRestoresOnSpace = restoresOnSpace
        slashCommandTracker = SlashCommandTracker(restoresOnSpace: restoresOnSpace)
        shiftEnglishEnabled = defaults.bool(forKey: Self.shiftEnglishEnabledKey)
        shiftRestoresOnRelease = defaults.object(forKey: Self.shiftRestoresOnReleaseKey) as? Bool ?? true
        if let keyCodes = defaults.array(forKey: Self.shiftEnglishKeyCodesKey) as? [Int] {
            shiftEnglishKeyCodes = Set(keyCodes)
        } else {
            let categories = defaults.stringArray(forKey: Self.shiftEnglishCategoriesKey)
                .map { Set($0.compactMap(ShiftKeyCategory.init(rawValue:))) }
                ?? Set(ShiftKeyCategory.allCases)
            shiftEnglishKeyCodes = ShiftEnglishOptions(categories: categories, restoresOnRelease: true).keyCodes
        }
        accessibilityTrusted = focusedFieldProvider.isTrusted
        switchCount = switchCounter.count
        launchAtLoginStatus = loginItemManager.status
        inputSourceIndicatorEnabled = inputSourceIndicator.isEnabled

        usageLogger.isEnabled = usageLoggingEnabled
        // Lines of the system log, such as key decisions, go to the usage log too.
        Diagnostics.sink = { category, level, message in
            usageLogger.log(
                UsageEvent(
                    "diag",
                    [
                        "category": .string(category.rawValue),
                        "level": .string(level.rawValue),
                        "message": .string(message),
                    ]
                )
            )
        }
    }

    // MARK: - Lifecycle

    func start() {
        guard !hasStarted else { return }
        hasStarted = true

        logUsage("appStart", Self.environmentFields())
        loadRulesAtStartup()
        refreshInputSources()
        lastObservedSourceID = currentInputSource?.id
        logSnapshot("appStart")
        startSnapshotHeartbeat()
        inputMethodProbe?.startObservingNotifications()
        startSuggestionRefresh()
        reportLoginStatus()
        startMonitoring()
        updateController?.start()
        refreshApplications()
        updateCurrentApplication(from: NSWorkspace.shared.frontmostApplication)
    }

    func stop() {
        guard !hasStopped else { return }
        hasStopped = true

        logUsage("appStop")
        snapshotTask?.cancel()
        snapshotTask = nil
        suggestionTask?.cancel()
        suggestionTask = nil
        scanTask?.cancel()
        scanTask = nil
        isScanning = false

        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
            self.activationObserver = nil
        }

        inputSourceManager.stopMonitoringEnabledSources()
        stopTerminalPolling()
        stopFollowingFields()
        updateKeyMonitoring()
        inputSourceManager.stopMonitoringSelectedSource()
        updateController?.stop()
        usageLogger.flush()
    }

    // MARK: - Rules

    /// True when the rule file exists but could not be read, so editing is paused
    /// and the original file is left untouched.
    var hasStorageFailure: Bool {
        !ruleEditingEnabled || !commandRuleEditingEnabled || !fieldRuleEditingEnabled
            || !slashCommandAppEditingEnabled || !shiftAppRuleEditingEnabled
    }

    func reloadRulesFromDisk() {
        loadRulesFromDisk(reportingSuccess: true)
    }

    /// Loads the rules the way a cold start does: silently, so the status line
    /// keeps showing the application count instead of a confirmation message.
    func loadRulesAtStartup() {
        loadRulesFromDisk(reportingSuccess: false)
    }

    private func loadRulesFromDisk(reportingSuccess: Bool) {
        defer { updateKeyMonitoring() }

        do {
            let loaded = try store.load()
            ruleSet = RuleSet(normalizing: loaded)
            ruleEditingEnabled = true
            storageStatus = reportingSuccess ? .rulesReloaded : nil
        } catch {
            logUsage("error", ["where": "loadRules", "kind": "app", "error": .string("\(error)")])
            // Keep whatever is already in memory; never write back over a file we
            // could not read.
            ruleEditingEnabled = false
            storageStatus = .rulesReadFailure
            loadCommandRules()
            loadFieldRules()
            loadSlashCommandApps()
            loadShiftAppRules()
            return
        }

        if !loadCommandRules() {
            storageStatus = .commandRulesReadFailure
        }
        if !loadFieldRules() {
            storageStatus = .fieldRulesReadFailure
        }
        if !loadSlashCommandApps() {
            storageStatus = .slashCommandAppsReadFailure
        }
        if !loadShiftAppRules() {
            storageStatus = .shiftAppRulesReadFailure
        }
    }

    @discardableResult
    private func loadCommandRules() -> Bool {
        do {
            commandRuleSet = try CommandRuleSet(normalizing: commandStore.load())
            commandRuleEditingEnabled = true
            return true
        } catch {
            logUsage("error", ["where": "loadRules", "kind": "command", "error": .string("\(error)")])
            commandRuleEditingEnabled = false
            return false
        }
    }

    @discardableResult
    private func loadFieldRules() -> Bool {
        do {
            fieldRuleSet = try FieldRuleSet(normalizing: fieldStore.load())
            fieldRuleEditingEnabled = true
            return true
        } catch {
            logUsage("error", ["where": "loadRules", "kind": "field", "error": .string("\(error)")])
            fieldRuleEditingEnabled = false
            return false
        }
    }

    @discardableResult
    private func loadSlashCommandApps() -> Bool {
        do {
            slashCommandApps = try SlashCommandAppList(normalizing: slashCommandAppStore.load())
            slashCommandAppEditingEnabled = true
            return true
        } catch {
            logUsage("error", ["where": "loadRules", "kind": "slashApps", "error": .string("\(error)")])
            slashCommandAppEditingEnabled = false
            return false
        }
    }

    @discardableResult
    private func loadShiftAppRules() -> Bool {
        do {
            var rules = try ShiftAppRuleList(normalizing: shiftAppRuleStore.load())
            if !defaults.bool(forKey: Self.shiftExcludedAppsMigratedKey),
               let migrated = try migrateShiftExcludedApps(into: rules)
            {
                rules = migrated
                defaults.set(true, forKey: Self.shiftExcludedAppsMigratedKey)
            }
            shiftAppRules = rules
            shiftAppRuleEditingEnabled = true
            return true
        } catch {
            logUsage("error", ["where": "loadRules", "kind": "shift", "error": .string("\(error)")])
            shiftAppRuleEditingEnabled = false
            return false
        }
    }

    /// Turns Shift off in the applications where it did not switch before
    /// Shift had settings per application. The old file stays in place; when
    /// it cannot be read, nil is returned and it is tried again next time.
    private func migrateShiftExcludedApps(into rules: ShiftAppRuleList) throws -> ShiftAppRuleList? {
        guard let excluded = try? shiftExcludedAppStore.load() else { return nil }
        var candidate = rules
        for app in SlashCommandAppList(normalizing: excluded).apps
            where candidate.rule(for: app.bundleIdentifier) == nil
        {
            candidate.set(
                ShiftAppRule(
                    bundleIdentifier: app.bundleIdentifier,
                    applicationName: app.applicationName,
                    options: .off
                )
            )
        }
        if candidate != rules {
            try shiftAppRuleStore.save(candidate.rules)
        }
        return candidate
    }

    func revealRulesFileInFinder() {
        let url: URL = if !ruleEditingEnabled {
            store.url
        } else if !commandRuleEditingEnabled {
            commandStore.url
        } else if !fieldRuleEditingEnabled {
            fieldStore.url
        } else if !slashCommandAppEditingEnabled {
            slashCommandAppStore.url
        } else if !shiftAppRuleEditingEnabled {
            shiftAppRuleStore.url
        } else {
            store.url
        }
        let fileManager = FileManager.default

        if fileManager.fileExists(atPath: url.path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
            return
        }

        let directory = url.deletingLastPathComponent()
        if fileManager.fileExists(atPath: directory.path) {
            NSWorkspace.shared.activateFileViewerSelecting([directory])
        }
    }

    // MARK: - Applications

    var configuredRuleCount: Int {
        ruleSet.rules.count
    }

    /// Installed applications plus applications that only exist as saved rules,
    /// so leftover rules stay visible and can still be edited or deleted.
    var displayApplications: [InstalledApplication] {
        var seenBundleIdentifiers: Set<String> = []
        var result: [InstalledApplication] = []

        for application in installedApplications
            where seenBundleIdentifiers.insert(application.bundleIdentifier).inserted
        {
            result.append(application)
        }

        for rule in ruleSet.rules
            where seenBundleIdentifiers.insert(rule.bundleIdentifier).inserted
        {
            let name = rule.applicationName.trimmingCharacters(in: .whitespacesAndNewlines)
            result.append(
                InstalledApplication(
                    name: name.isEmpty ? rule.bundleIdentifier : name,
                    bundleIdentifier: rule.bundleIdentifier,
                    url: nil
                )
            )
        }

        // Applications chosen from elsewhere for slash commands, Shift or text fields.
        let otherApps = slashCommandApps.apps.map { ($0.bundleIdentifier, $0.applicationName) }
            + shiftAppRules.rules.map { ($0.bundleIdentifier, $0.applicationName) }
            + fieldRuleSet.rules.map { ($0.bundleIdentifier, $0.applicationName) }
        for (bundleIdentifier, name) in otherApps
            where seenBundleIdentifiers.insert(bundleIdentifier).inserted
        {
            result.append(
                InstalledApplication(
                    name: name,
                    bundleIdentifier: bundleIdentifier,
                    url: NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
                )
            )
        }

        return result.sorted { lhs, rhs in
            let comparison = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
            if comparison == .orderedSame {
                return lhs.bundleIdentifier < rhs.bundleIdentifier
            }
            return comparison == .orderedAscending
        }
    }

    /// Applications with anything of their own: a rule, slash commands, Shift
    /// settings or remembered text fields, and the terminals once they have
    /// programs.
    private var configuredBundleIdentifiers: Set<String> {
        var identifiers = Set(ruleSet.rules.map(\.bundleIdentifier))
            .union(slashCommandApps.apps.map(\.bundleIdentifier))
            .union(shiftAppRules.rules.map(\.bundleIdentifier))
            .union(fieldRuleSet.rules.map(\.bundleIdentifier))
        if !commandRuleSet.rules.isEmpty {
            identifiers.formUnion(
                installedApplications.map(\.bundleIdentifier).filter(supportsTerminal(bundleIdentifier:))
            )
        }
        return identifiers
    }

    /// Whether programs running in the application can have rules of their own.
    func supportsTerminal(bundleIdentifier: String) -> Bool {
        terminalContextProvider.supportsTerminal(bundleIdentifier: bundleIdentifier)
    }

    func fieldRules(for bundleIdentifier: String) -> [FieldRule] {
        fieldRuleSet.rules.filter { $0.bundleIdentifier == bundleIdentifier }
    }

    /// What an application has besides its input source, in a few words, or
    /// nil when it has nothing else.
    func extrasSummary(for application: InstalledApplication) -> String? {
        var parts: [String] = []
        if usesSlashCommands(application) {
            parts.append("/ 命令")
        }
        if let options = shiftOptions(for: application) {
            parts.append("⇧ " + (options.switchesNothing ? "关闭" : "自定义"))
        }
        if supportsTerminal(bundleIdentifier: application.bundleIdentifier), !commandRuleSet.rules.isEmpty {
            parts.append("\(commandRuleSet.rules.count) 个终端程序")
        }
        let fieldCount = fieldRules(for: application.bundleIdentifier).count
        if fieldCount > 0 {
            parts.append("\(fieldCount) 个输入框")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    var filteredInstalledApplications: [InstalledApplication] {
        let filter = ApplicationListFilter(
            query: searchText,
            scope: applicationListScope,
            configuredBundleIdentifiers: configuredBundleIdentifiers
        )

        return displayApplications.filter {
            filter.includes(
                ApplicationListEntry(
                    displayName: $0.name,
                    bundleIdentifier: $0.bundleIdentifier,
                    isInstalled: $0.isInstalled
                )
            )
        }
    }

    /// Only one scan may be in flight at a time, and the previous list stays on
    /// screen until a usable result arrives.
    func refreshApplications() {
        guard !isScanning else { return }

        isScanning = true
        let scanner = applicationScanner

        scanTask = Task { [weak self] in
            let result = await Task.detached(priority: .userInitiated) {
                scanner.scan()
            }.value

            guard let self, !Task.isCancelled else { return }
            finishScan(with: result)
        }
    }

    private func finishScan(with result: ApplicationScanResult) {
        scanTask = nil
        isScanning = false

        if result.isTotalFailure || result.isPartialFailure {
            logUsage(
                "error",
                [
                    "where": "scanApplications", "total": .bool(result.isTotalFailure),
                    "failedRoots": .strings(result.failedRoots.map(\.path)),
                ]
            )
        }

        if result.isTotalFailure {
            // Nothing usable came back: keep the list that is already on screen.
            scanStatus = StatusMessage(
                text: "应用扫描失败，已保留原有列表。",
                severity: .error
            )
            return
        }

        if result.isPartialFailure {
            if !result.applications.isEmpty {
                installedApplications = result.applications
                iconCacheGeneration += 1
            }

            scanStatus = StatusMessage(
                text: "部分目录扫描失败：" + result.failedRoots.map(\.path).joined(separator: "、"),
                severity: .warning
            )
            return
        }

        installedApplications = result.applications
        iconCacheGeneration += 1
        scanStatus = nil
    }

    // MARK: - Input sources

    func reloadInputSources() {
        refreshInputSources()
    }

    private func refreshInputSources() {
        inputSourceManager.invalidateCache()
        inputSources = inputSourceManager.availableInputSources()
        currentInputSource = inputSourceManager.currentInputSource()
    }

    /// The picker value for one application. A rule that names the current
    /// Chinese or English input source is shown as that role.
    func selectedInputSourceID(for application: InstalledApplication) -> String {
        guard let id = ruleSet.rule(forBundleIdentifier: application.bundleIdentifier)?.inputSourceID else {
            return Self.followDefaultInputSourceID
        }
        return pickerValue(forRuleInputSourceID: id)
    }

    /// The "默认" picker entry, named after what the default currently does.
    var followDefaultChoiceTitle: String {
        "默认（" + defaultInputSourceDescription + "）"
    }

    private var defaultInputSourceDescription: String {
        inputSourceDescription(for: defaultInputSourceSelection)
    }

    private func inputSourceDescription(for selection: String) -> String {
        if selection == Self.noSwitchInputSourceID {
            return "不切换"
        }
        if let roleName = Self.roleName(forRuleID: selection) {
            return roleName
        }
        return inputSources.first { $0.id == selection }?.name ?? selection
    }

    /// Settings entries for the default input source besides "不切换" and the roles.
    var defaultInputSourceChoices: [InputSourceChoice] {
        inputSourceChoices(selectedID: defaultInputSourceSelection, savedName: nil)
    }

    func selectedInputSourceID(for rule: CommandRule) -> String {
        pickerValue(forRuleInputSourceID: rule.inputSourceID)
    }

    private func pickerValue(forRuleInputSourceID id: String) -> String {
        if id == effectiveChineseInputSource?.id {
            return Self.chineseRuleID
        }
        if id == effectiveEnglishInputSource?.id {
            return Self.englishRuleID
        }
        return id
    }

    /// The "中文" and "英文" picker entries, named after the input sources they
    /// currently stand for.
    var ruleRoleChoices: [InputSourceChoice] {
        [
            InputSourceChoice(
                id: Self.chineseRuleID,
                name: Self.roleTitle("中文", effectiveChineseInputSource)
            ),
            InputSourceChoice(
                id: Self.englishRuleID,
                name: Self.roleTitle("英文", effectiveEnglishInputSource)
            ),
        ]
    }

    private static func roleTitle(_ role: String, _ source: InputSource?) -> String {
        role + "（" + (source?.name ?? "未设置") + "）"
    }

    /// Picker entries besides the roles, including the saved input source when
    /// it is no longer installed, so a rule is never silently rewritten. The
    /// Chinese and English input sources are offered through their roles.
    func inputSourceChoices(for application: InstalledApplication) -> [InputSourceChoice] {
        inputSourceChoices(
            selectedID: selectedInputSourceID(for: application),
            savedName: ruleSet.rule(forBundleIdentifier: application.bundleIdentifier)?.inputSourceName
        )
    }

    func inputSourceChoices(for rule: CommandRule) -> [InputSourceChoice] {
        inputSourceChoices(selectedID: selectedInputSourceID(for: rule), savedName: rule.inputSourceName)
    }

    private func inputSourceChoices(selectedID: String, savedName: String?) -> [InputSourceChoice] {
        let hiddenIDs = Set([effectiveChineseInputSource?.id, effectiveEnglishInputSource?.id].compactMap(\.self))
        var choices = inputSources
            .filter { !hiddenIDs.contains($0.id) || $0.id == selectedID }
            .map { InputSourceChoice(id: $0.id, name: $0.name) }

        if
            selectedID != Self.noSwitchInputSourceID,
            selectedID != Self.followDefaultInputSourceID,
            selectedID != Self.chineseRuleID,
            selectedID != Self.englishRuleID,
            !choices.contains(where: { $0.id == selectedID })
        {
            let savedName = savedName?.trimmingCharacters(in: .whitespacesAndNewlines)
            let displayName = (savedName?.isEmpty == false) ? savedName! : selectedID

            choices.append(
                InputSourceChoice(id: selectedID, name: "不可用：" + displayName)
            )
        }

        return choices
    }

    /// Candidate first, disk second, published state last: a failed save leaves
    /// both the visible state and the file untouched.
    func setInputSourceID(_ inputSourceID: String, for application: InstalledApplication) {
        guard ruleEditingEnabled else {
            storageStatus = .rulesReadFailure
            return
        }

        var candidate = ruleSet

        if inputSourceID == Self.followDefaultInputSourceID {
            candidate.remove(bundleIdentifier: application.bundleIdentifier)
        } else if inputSourceID == Self.noSwitchInputSourceID {
            candidate.upsert(
                AppRule(
                    bundleIdentifier: application.bundleIdentifier,
                    applicationName: application.name,
                    inputSourceID: Self.noSwitchInputSourceID,
                    inputSourceName: "不切换"
                )
            )
        } else if let target = ruleTarget(forPickerValue: inputSourceID) {
            candidate.upsert(
                AppRule(
                    bundleIdentifier: application.bundleIdentifier,
                    applicationName: application.name,
                    inputSourceID: target.id,
                    inputSourceName: target.name
                )
            )
        } else if
            ruleSet.rule(forBundleIdentifier: application.bundleIdentifier)?.inputSourceID
            == inputSourceID
        {
            // Re-selecting the input source that is already saved, but currently
            // unavailable, keeps the existing rule.
            return
        } else {
            inputSourceStatus = StatusMessage(
                text: "所选输入法当前不可用，规则未修改。",
                severity: .warning
            )
            return
        }

        guard candidate != ruleSet else { return }

        commit(candidate)
    }

    private func commit(_ candidate: RuleSet) {
        do {
            try store.save(candidate.rules)
            ruleSet = candidate
            storageStatus = .rulesSaved
            logUsage("ruleEdit", ["kind": "app", "ok": true, "count": .int(candidate.rules.count)])
        } catch {
            logUsage("ruleEdit", ["kind": "app", "ok": false, "error": .string("\(error)")])
            storageStatus = .rulesSaveFailure
        }
    }

    /// The identifier and name a rule saves for a picker value: a role, or an
    /// installed input source.
    private func ruleTarget(forPickerValue value: String) -> (id: String, name: String)? {
        if let roleName = Self.roleName(forRuleID: value) {
            return (value, roleName)
        }
        if let inputSource = inputSources.first(where: { $0.id == value }) {
            return (inputSource.id, inputSource.name)
        }
        return nil
    }

    // MARK: - Suggestions

    private static let dismissedSuggestionsKey = "dismissedSuggestionIDs"
    private static let appliedSuggestionsKey = "appliedSuggestions"

    /// Rule changes the usage log suggests, which are only made when applied.
    @Published private(set) var suggestions: [RuleSuggestion] = []
    @Published private(set) var appliedSuggestions: [AppliedSuggestion] = []
    @Published private(set) var isAnalyzing = false
    @Published private(set) var lastAnalysisDate: Date?

    private var suggestionTask: Task<Void, Never>?

    private var dismissedSuggestionIDs: Set<String> {
        get { Set(defaults.stringArray(forKey: Self.dismissedSuggestionsKey) ?? []) }
        set { defaults.set(newValue.sorted(), forKey: Self.dismissedSuggestionsKey) }
    }

    private func startSuggestionRefresh() {
        appliedSuggestions = defaults.data(forKey: Self.appliedSuggestionsKey)
            .flatMap { try? JSONDecoder().decode([AppliedSuggestion].self, from: $0) } ?? []
        suggestionTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(10))
                guard !Task.isCancelled, let self else { return }
                await refreshSuggestions()
                try? await Task.sleep(for: .seconds(6 * 3600))
            }
        }
    }

    private func suggestionContext() -> UsageAnalyzer.CurrentRules {
        var targets: [String: String] = [:]
        for rule in ruleSet.rules {
            targets[rule.bundleIdentifier] = rule.inputSourceID == Self.noSwitchInputSourceID
                ? rule.inputSourceID
                : targetInputSourceID(forRuleID: rule.inputSourceID) ?? rule.inputSourceID
        }
        let defaultTarget = defaultInputSourceSelection == Self.noSwitchInputSourceID
            ? nil
            : targetInputSourceID(forRuleID: defaultInputSourceSelection)
        var commandTargets: [String: String] = [:]
        for rule in commandRuleSet.rules {
            commandTargets[CommandRuleSet.matchKey(rule.command)] =
                targetInputSourceID(forRuleID: rule.inputSourceID) ?? rule.inputSourceID
        }
        return UsageAnalyzer.CurrentRules(
            appTargets: targets,
            defaultTarget: defaultTarget,
            fieldRules: fieldRuleSet.rules,
            commandTargets: commandTargets,
            commandRulesEnabled: terminalSwitchingEnabled,
            shiftEnabled: shiftEnglishEnabled,
            globalShift: globalShiftOptions,
            shiftAppRules: Dictionary(
                shiftAppRules.rules.map { ($0.bundleIdentifier, $0.options) },
                uniquingKeysWith: { first, _ in first }
            ),
            inputSourceNames: Dictionary(inputSources.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        )
    }

    /// Reads the usage log in the background and updates the suggestions.
    func refreshSuggestions() async {
        guard !isAnalyzing else { return }
        isAnalyzing = true
        let context = suggestionContext()
        let provider = suggestionLinesProvider
        let logger = usageLogger
        let found = await Task.detached(priority: .utility) {
            logger.flush()
            return UsageAnalyzer().suggestions(fromLines: provider(), current: context)
        }.value
        let dismissed = dismissedSuggestionIDs
        suggestions = found.filter { !dismissed.contains($0.id) }
        lastAnalysisDate = Date()
        isAnalyzing = false
        logUsage("suggestions", ["count": .int(suggestions.count), "ids": .strings(suggestions.map(\.id))])
    }

    func requestSuggestionRefresh() {
        Task { await refreshSuggestions() }
    }

    func dismissSuggestion(_ suggestion: RuleSuggestion) {
        dismissedSuggestionIDs.insert(suggestion.id)
        suggestions.removeAll { $0.id == suggestion.id }
    }

    /// Makes the suggested change. Returns false when it could not be saved.
    @discardableResult
    func applySuggestion(_ suggestion: RuleSuggestion) -> Bool {
        let change: AppliedSuggestion.Change
        switch suggestion.action {
        case let .setAppRule(bundleIdentifier, applicationName, inputSourceID):
            guard ruleEditingEnabled,
                  let target = ruleTarget(forPickerValue: roleOrID(inputSourceID))
            else { return false }
            let previous = ruleSet.rule(forBundleIdentifier: bundleIdentifier)
            var candidate = ruleSet
            candidate.upsert(
                AppRule(
                    bundleIdentifier: bundleIdentifier,
                    applicationName: previous?.applicationName ?? applicationName,
                    inputSourceID: target.id,
                    inputSourceName: target.name
                )
            )
            commit(candidate)
            guard ruleSet == candidate else { return false }
            change = .appRule(bundleIdentifier: bundleIdentifier, previous: previous)
        case let .addFieldRule(bundleIdentifier, applicationName, signature, inputSourceID):
            guard fieldRuleEditingEnabled,
                  let target = ruleTarget(forPickerValue: roleOrID(inputSourceID)),
                  fieldRuleSet.rule(forBundleIdentifier: bundleIdentifier, matching: signature) == nil
            else { return false }
            let rule = FieldRule(
                bundleIdentifier: bundleIdentifier,
                applicationName: applicationName,
                label: signature.suggestedLabel,
                signature: signature,
                inputSourceID: target.id,
                inputSourceName: target.name
            )
            var candidate = fieldRuleSet
            candidate.upsert(rule)
            guard commitFieldRules(candidate) else { return false }
            change = .fieldRule(id: rule.id)
        case let .setCommandRule(command, inputSourceID):
            let name = CommandRuleSet.normalizedCommand(command)
            guard commandRuleEditingEnabled, !name.isEmpty,
                  let target = ruleTarget(forPickerValue: roleOrID(inputSourceID))
            else { return false }
            let previous = commandRuleSet.rule(forCommand: name)
            var candidate = commandRuleSet
            candidate.upsert(
                CommandRule(command: previous?.command ?? name, inputSourceID: target.id, inputSourceName: target.name)
            )
            guard commitCommandRules(candidate) else { return false }
            change = .commandRule(command: name, previous: previous)
        case let .setShiftKey(bundleIdentifier, applicationName, keyCode, enabled):
            guard let previous = changeShiftOptions(
                bundleIdentifier: bundleIdentifier,
                applicationName: applicationName,
                {
                    $0.set(keyCode: keyCode, on: enabled)
                }
            ) else { return false }
            change = .shiftOptions(bundleIdentifier: bundleIdentifier, previous: previous)
        case let .setShiftRestore(bundleIdentifier, applicationName, enabled):
            guard let previous = changeShiftOptions(
                bundleIdentifier: bundleIdentifier,
                applicationName: applicationName,
                {
                    $0.restoresOnRelease = enabled
                }
            ) else { return false }
            change = .shiftOptions(bundleIdentifier: bundleIdentifier, previous: previous)
        }

        appliedSuggestions.insert(
            AppliedSuggestion(id: suggestion.id, title: suggestion.title, appliedAt: Date(), change: change),
            at: 0
        )
        appliedSuggestions = Array(appliedSuggestions.prefix(20))
        persistAppliedSuggestions()
        suggestions.removeAll { $0.id == suggestion.id }
        logUsage("ruleEdit", ["kind": "suggestion", "reason": "autoSuggestion", "id": .string(suggestion.id)])
        return true
    }

    /// Puts back what a suggestion replaced.
    func undoSuggestion(_ applied: AppliedSuggestion) {
        switch applied.change {
        case let .appRule(bundleIdentifier, previous):
            guard ruleEditingEnabled else { return }
            var candidate = ruleSet
            if let previous {
                candidate.upsert(previous)
            } else {
                candidate.remove(bundleIdentifier: bundleIdentifier)
            }
            commit(candidate)
        case let .fieldRule(id):
            removeFieldRule(id)
        case let .commandRule(command, previous):
            guard commandRuleEditingEnabled else { return }
            var candidate = commandRuleSet
            if let previous {
                candidate.upsert(previous)
            } else {
                candidate.remove(command: command)
            }
            if candidate != commandRuleSet {
                commitCommandRules(candidate)
            }
        case let .shiftOptions(bundleIdentifier, previous):
            if let bundleIdentifier {
                let name = shiftAppRules.rule(for: bundleIdentifier)?.applicationName ?? bundleIdentifier
                setShiftOptions(previous, bundleIdentifier: bundleIdentifier, applicationName: name)
            } else if let previous {
                shiftEnglishKeyCodes = previous.keyCodes
                shiftRestoresOnRelease = previous.restoresOnRelease
            }
        }
        appliedSuggestions.removeAll { $0.id == applied.id && $0.appliedAt == applied.appliedAt }
        persistAppliedSuggestions()
        logUsage("ruleEdit", ["kind": "suggestionUndo", "id": .string(applied.id)])
        Task { await refreshSuggestions() }
    }

    /// Changes the Shift settings of an application, starting from the ones
    /// it uses now, or without one the settings for everywhere. Returns what
    /// is needed to undo it: the settings before, the application's own or
    /// nil when it had none; or nil, nil when nothing was saved.
    private func changeShiftOptions(
        bundleIdentifier: String?,
        applicationName: String?,
        _ change: (inout ShiftEnglishOptions) -> Void
    ) -> ShiftEnglishOptions?? {
        guard let bundleIdentifier else {
            let previous = globalShiftOptions
            var options = previous
            change(&options)
            shiftEnglishKeyCodes = options.keyCodes
            shiftRestoresOnRelease = options.restoresOnRelease
            return .some(previous)
        }
        let previous = shiftAppRules.rule(for: bundleIdentifier)?.options
        var options = previous ?? globalShiftOptions
        change(&options)
        guard setShiftOptions(
            options,
            bundleIdentifier: bundleIdentifier,
            applicationName: applicationName ?? bundleIdentifier
        ) else {
            return nil
        }
        return .some(previous)
    }

    /// A rule follows the Chinese or English role when the input source is
    /// the one standing for it.
    private func roleOrID(_ inputSourceID: String) -> String {
        if inputSourceID == effectiveChineseInputSource?.id {
            return Self.chineseRuleID
        }
        if inputSourceID == effectiveEnglishInputSource?.id {
            return Self.englishRuleID
        }
        return inputSourceID
    }

    private func persistAppliedSuggestions() {
        if let data = try? JSONEncoder().encode(appliedSuggestions) {
            defaults.set(data, forKey: Self.appliedSuggestionsKey)
        }
    }

    // MARK: - Command rules

    /// Adds a rule for a program in the terminal. Returns false when the name is
    /// empty or the program already has a rule.
    @discardableResult
    func addCommandRule(_ command: String, inputSourceID: String = AppRuntime.chineseRuleID) -> Bool {
        guard commandRuleEditingEnabled else {
            storageStatus = .commandRulesReadFailure
            return false
        }

        let name = CommandRuleSet.normalizedCommand(command)
        guard !name.isEmpty, let target = ruleTarget(forPickerValue: inputSourceID) else {
            return false
        }
        guard commandRuleSet.rule(forCommand: name) == nil else {
            inputSourceStatus = StatusMessage(text: "“" + name + "”已经有规则了。", severity: .warning)
            return false
        }

        var candidate = commandRuleSet
        candidate.upsert(CommandRule(command: name, inputSourceID: target.id, inputSourceName: target.name))
        return commitCommandRules(candidate)
    }

    func setInputSourceID(_ inputSourceID: String, forCommand command: String) {
        guard commandRuleEditingEnabled else {
            storageStatus = .commandRulesReadFailure
            return
        }
        guard
            var rule = commandRuleSet.rule(forCommand: command),
            let target = ruleTarget(forPickerValue: inputSourceID)
        else {
            return
        }

        rule.inputSourceID = target.id
        rule.inputSourceName = target.name
        var candidate = commandRuleSet
        candidate.upsert(rule)
        guard candidate != commandRuleSet else { return }
        commitCommandRules(candidate)
    }

    func removeCommandRule(_ command: String) {
        guard commandRuleEditingEnabled else {
            storageStatus = .commandRulesReadFailure
            return
        }

        var candidate = commandRuleSet
        guard candidate.remove(command: command) != nil else { return }
        commitCommandRules(candidate)
    }

    @discardableResult
    private func commitCommandRules(_ candidate: CommandRuleSet) -> Bool {
        do {
            try commandStore.save(candidate.rules)
            commandRuleSet = candidate
            storageStatus = .rulesSaved
            logUsage("ruleEdit", ["kind": "command", "ok": true, "count": .int(candidate.rules.count)])
            updateTerminalPolling(for: currentApplication)
            return true
        } catch {
            logUsage("ruleEdit", ["kind": "command", "ok": false, "error": .string("\(error)")])
            storageStatus = .rulesSaveFailure
            return false
        }
    }

    // MARK: - Field rules

    /// What "记住当前输入框" in the menu bar would do right now.
    enum FieldCaptureState: Equatable {
        /// Accessibility has not been allowed yet.
        case needsAccessibility
        /// No text field of another application has keyboard focus.
        case noField
        case ready(applicationName: String, inputSourceName: String)
    }

    private struct FieldCapture {
        let application: RunningApplicationInfo
        let field: FieldSignature
        let target: (id: String, name: String)
        let inputSourceName: String
    }

    func fieldCaptureState() -> FieldCaptureState {
        refreshAccessibilityTrust()
        guard accessibilityTrusted else { return .needsAccessibility }
        guard let capture = currentFieldCapture() else { return .noField }
        return .ready(applicationName: capture.application.name, inputSourceName: capture.inputSourceName)
    }

    private func currentFieldCapture() -> FieldCapture? {
        guard
            let application = currentApplication,
            let field = focusedFieldProvider.currentField(),
            let inputSource = inputSourceManager.currentInputSource(),
            let target = ruleTarget(forPickerValue: pickerValue(forRuleInputSourceID: inputSource.id))
        else {
            return nil
        }
        return FieldCapture(application: application, field: field, target: target, inputSourceName: inputSource.name)
    }

    /// Saves the input source selected now for the focused field of the
    /// frontmost application. A field that already has a rule gets the new
    /// input source.
    @discardableResult
    func rememberFocusedField() -> Bool {
        guard fieldRuleEditingEnabled else {
            storageStatus = .fieldRulesReadFailure
            return false
        }
        refreshAccessibilityTrust()
        guard accessibilityTrusted, let capture = currentFieldCapture() else { return false }

        let bundleIdentifier = capture.application.bundleIdentifier
        var rule = fieldRuleSet.rule(forBundleIdentifier: bundleIdentifier, matching: capture.field)
            ?? FieldRule(
                bundleIdentifier: bundleIdentifier,
                applicationName: capture.application.name,
                label: capture.field.suggestedLabel,
                signature: capture.field,
                inputSourceID: capture.target.id,
                inputSourceName: capture.target.name
            )
        rule.applicationName = capture.application.name
        rule.inputSourceID = capture.target.id
        rule.inputSourceName = capture.target.name

        var candidate = fieldRuleSet
        candidate.upsert(rule)
        guard candidate != fieldRuleSet else { return true }
        return commitFieldRules(candidate)
    }

    /// Field rules grouped by application, in the order of the application names.
    var fieldRuleGroups: [(bundleIdentifier: String, applicationName: String, rules: [FieldRule])] {
        var groups: [(bundleIdentifier: String, applicationName: String, rules: [FieldRule])] = []
        for rule in fieldRuleSet.rules {
            if let index = groups.firstIndex(where: { $0.bundleIdentifier == rule.bundleIdentifier }) {
                groups[index].rules.append(rule)
            } else {
                let name = rule.applicationName.trimmingCharacters(in: .whitespacesAndNewlines)
                groups.append((rule.bundleIdentifier, name.isEmpty ? rule.bundleIdentifier : name, [rule]))
            }
        }
        return groups.sorted {
            $0.applicationName.localizedCaseInsensitiveCompare($1.applicationName) == .orderedAscending
        }
    }

    func selectedInputSourceID(for rule: FieldRule) -> String {
        pickerValue(forRuleInputSourceID: rule.inputSourceID)
    }

    func inputSourceChoices(for rule: FieldRule) -> [InputSourceChoice] {
        inputSourceChoices(selectedID: selectedInputSourceID(for: rule), savedName: rule.inputSourceName)
    }

    /// Settings entries for the address bar besides the roles.
    var addressBarInputSourceChoices: [InputSourceChoice] {
        inputSourceChoices(selectedID: addressBarInputSourceSelection, savedName: nil)
    }

    func setInputSourceID(_ inputSourceID: String, forFieldRule id: FieldRule.ID) {
        updateFieldRule(id) { rule in
            guard let target = ruleTarget(forPickerValue: inputSourceID) else { return }
            rule.inputSourceID = target.id
            rule.inputSourceName = target.name
        }
    }

    func renameFieldRule(_ id: FieldRule.ID, to label: String) {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        updateFieldRule(id) { $0.label = trimmed }
    }

    func removeFieldRule(_ id: FieldRule.ID) {
        guard fieldRuleEditingEnabled else {
            storageStatus = .fieldRulesReadFailure
            return
        }

        var candidate = fieldRuleSet
        guard candidate.remove(id: id) != nil else { return }
        commitFieldRules(candidate)
    }

    private func updateFieldRule(_ id: FieldRule.ID, _ change: (inout FieldRule) -> Void) {
        guard fieldRuleEditingEnabled else {
            storageStatus = .fieldRulesReadFailure
            return
        }
        guard var rule = fieldRuleSet.rule(id: id) else { return }

        change(&rule)
        var candidate = fieldRuleSet
        candidate.upsert(rule)
        guard candidate != fieldRuleSet else { return }
        commitFieldRules(candidate)
    }

    @discardableResult
    private func commitFieldRules(_ candidate: FieldRuleSet) -> Bool {
        do {
            try fieldStore.save(candidate.rules)
            fieldRuleSet = candidate
            storageStatus = .rulesSaved
            logUsage("ruleEdit", ["kind": "field", "ok": true, "count": .int(candidate.rules.count)])
            refreshFieldObservation()
            return true
        } catch {
            logUsage("ruleEdit", ["kind": "field", "ok": false, "error": .string("\(error)")])
            storageStatus = .rulesSaveFailure
            return false
        }
    }

    func openAutomationSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Slash commands

    func addSlashCommandApp(_ application: InstalledApplication) {
        guard slashCommandAppEditingEnabled else {
            storageStatus = .slashCommandAppsReadFailure
            return
        }

        var candidate = slashCommandApps
        candidate.insert(
            SlashCommandApp(bundleIdentifier: application.bundleIdentifier, applicationName: application.name)
        )
        guard candidate != slashCommandApps else { return }
        commitSlashCommandApps(candidate)
    }

    func removeSlashCommandApp(bundleIdentifier: String) {
        guard slashCommandAppEditingEnabled else {
            storageStatus = .slashCommandAppsReadFailure
            return
        }

        var candidate = slashCommandApps
        guard candidate.remove(bundleIdentifier: bundleIdentifier) != nil else { return }
        commitSlashCommandApps(candidate)
    }

    private func commitSlashCommandApps(_ candidate: SlashCommandAppList) {
        do {
            try slashCommandAppStore.save(candidate.apps)
            slashCommandApps = candidate
            storageStatus = .rulesSaved
            logUsage("ruleEdit", ["kind": "slashApps", "ok": true, "count": .int(candidate.apps.count)])
            updateKeyMonitoring()
            refreshFieldObservation()
        } catch {
            logUsage("ruleEdit", ["kind": "slashApps", "ok": false, "error": .string("\(error)")])
            storageStatus = .rulesSaveFailure
        }
    }

    func usesSlashCommands(_ application: InstalledApplication) -> Bool {
        slashCommandApps.contains(bundleIdentifier: application.bundleIdentifier)
    }

    func setUsesSlashCommands(_ enabled: Bool, for application: InstalledApplication) {
        if enabled {
            addSlashCommandApp(application)
        } else {
            removeSlashCommandApp(bundleIdentifier: application.bundleIdentifier)
        }
    }

    // MARK: - Shift

    /// What applications without a rule of their own use.
    var globalShiftOptions: ShiftEnglishOptions {
        ShiftEnglishOptions(keyCodes: shiftEnglishKeyCodes, restoresOnRelease: shiftRestoresOnRelease)
    }

    /// The application's own Shift settings, or nil when it uses globalShiftOptions.
    func shiftOptions(for application: InstalledApplication) -> ShiftEnglishOptions? {
        shiftAppRules.rule(for: application.bundleIdentifier)?.options
    }

    /// Gives the application its own Shift settings, or with nil makes it use
    /// globalShiftOptions again.
    func setShiftOptions(_ options: ShiftEnglishOptions?, for application: InstalledApplication) {
        setShiftOptions(options, bundleIdentifier: application.bundleIdentifier, applicationName: application.name)
    }

    /// Returns false when the settings could not be saved.
    @discardableResult
    func setShiftOptions(_ options: ShiftEnglishOptions?, bundleIdentifier: String, applicationName: String) -> Bool {
        guard shiftAppRuleEditingEnabled else {
            storageStatus = .shiftAppRulesReadFailure
            return false
        }

        var candidate = shiftAppRules
        if let options {
            candidate.set(
                ShiftAppRule(bundleIdentifier: bundleIdentifier, applicationName: applicationName, options: options)
            )
        } else {
            candidate.remove(bundleIdentifier: bundleIdentifier)
        }
        guard candidate != shiftAppRules else { return true }

        do {
            try shiftAppRuleStore.save(candidate.rules)
            shiftAppRules = candidate
            storageStatus = .rulesSaved
            logUsage("ruleEdit", ["kind": "shift", "ok": true, "count": .int(candidate.rules.count)])
            return true
        } catch {
            logUsage("ruleEdit", ["kind": "shift", "ok": false, "error": .string("\(error)")])
            storageStatus = .rulesSaveFailure
            return false
        }
    }

    /// What Shift switches in the application, or nil when nothing.
    private func shiftOptions(in app: RunningApplicationInfo) -> ShiftEnglishOptions? {
        guard shiftEnglishEnabled else { return nil }
        let options = shiftAppRules.rule(for: app.bundleIdentifier)?.options ?? globalShiftOptions
        return options.switchesNothing ? nil : options
    }

    /// Whether a slash typed in the application may start a command.
    private func watchesSlashCommands(in app: RunningApplicationInfo) -> Bool {
        slashCommandSwitchingEnabled && slashCommandApps.contains(bundleIdentifier: app.bundleIdentifier)
    }

    /// Key presses are only looked at while slash commands or Shift could use
    /// them, and Accessibility allows it.
    private func updateKeyMonitoring() {
        let wanted = !hasStopped
            && ((slashCommandSwitchingEnabled && !slashCommandApps.apps.isEmpty) || shiftEnglishEnabled
                || usageLoggingEnabled)
            && accessibilityTrusted

        if wanted {
            if !keyEventMonitor.isRunning {
                keyEventMonitor.start { [weak self] event in
                    self?.handleKeyEvent(event) ?? false
                }
            }
        } else if keyEventMonitor.isRunning {
            keyEventMonitor.stop()
            slashCommandTracker.cancelCommand()
            shiftTracker.cancel()
        }

        let unavailable = wanted && !keyEventMonitor.isRunning
        if keyMonitoringUnavailable != unavailable {
            keyMonitoringUnavailable = unavailable
        }
    }

    /// Returns true to hold the key back until the monitor is told to type it.
    func handleKeyEvent(_ event: MonitoredKeyEvent) -> Bool {
        switch event {
        case .shiftReleased:
            let currentID = inputSourceManager.currentInputSource()?.id
            let decision = shiftTracker.shiftReleased(currentID: currentID)
            logUsage(
                "shiftRelease",
                ["current": .optional(currentID), "decision": .string(String(describing: decision))]
            )
            probe("shiftReleaseProbe", ["decision": .string(String(describing: decision))], parts: .all)
            if case let .restore(previousID) = decision {
                restoreAfterShift(previousID)
            }
            return false
        case let .keyDown(key, shifted, category, detail):
            return handleKeyDown(key, shifted: shifted, category: category, detail: detail)
        case let .modifierChanged(keyCode, flags, capsLock):
            handleModifierChanged(keyCode: keyCode, flags: flags, capsLock: capsLock)
            return false
        }
    }

    /// Logs every modifier change, and for Caps Lock reads the input source
    /// back several times, to see whether and when the input method followed.
    private func handleModifierChanged(keyCode: Int, flags: [String], capsLock: Bool) {
        guard usageLogger.isEnabled else { return }
        let mono = UsageEvent.currentMonotonicMilliseconds()
        let isCapsKey = keyCode == 57
        var fields: [String: JSONValue] = [
            "keyCode": .int(keyCode),
            "flags": .strings(flags),
            "capsLock": .bool(capsLock),
            "isCapsKey": .bool(isCapsKey),
            "current": .optional(inputSourceManager.currentInputSource()?.id),
        ]
        if let lastModifierMono {
            fields["sinceModifierMs"] = .double(mono - lastModifierMono)
        }
        lastModifierMono = mono
        guard isCapsKey else {
            logUsage("modifier", fields)
            return
        }

        fields["details"] = .object(inputSourceManager.currentInputSourceDetails().mapValues(JSONValue.string))
        if let lastCapsMono {
            fields["sinceLastCapsMs"] = .double(mono - lastCapsMono)
        }
        if let pendingSelfSwitch {
            fields["sinceOwnSwitchMs"] = .double(mono - pendingSelfSwitch.mono)
        }
        fields["shiftSwitched"] = .bool(shiftTracker.isSwitched)
        fields["pressesIn3s"] = .int(recentCapsMonos.filter { mono - $0 < 3000 }.count + 1)
        lastCapsMono = mono
        recentCapsMonos = (recentCapsMonos + [mono]).suffix(5)
        logUsage("capsLock", fields)
        probe("capsProbe", ["capsAtMono": .double(mono), "afterMs": 0, "capsLock": .bool(capsLock)], parts: .all)
        for delay in [30, 100, 250, 500, 1000] {
            probe(
                "capsProbe",
                ["capsAtMono": .double(mono), "afterMs": .int(delay), "capsLock": .bool(capsLock)],
                parts: delay == 250 || delay == 1000 ? .all : [.windows],
                afterMs: delay
            )
        }
        scheduleCapsReadback(startedAt: mono, capsLock: capsLock)
    }

    /// Reads the input source back after Caps Lock, 30 ms to 1 s later.
    private func scheduleCapsReadback(startedAt mono: Double, capsLock: Bool) {
        capsReadbackTasks.forEach { $0.cancel() }
        let before = inputSourceManager.currentInputSource()?.id
        let delays = [30, 100, 250, 500, 1000]
        capsReadbackTasks = delays.map { delay in
            Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(delay))
                guard !Task.isCancelled, let self else { return }
                let actual = inputSourceManager.currentInputSource()?.id
                logUsage(
                    "capsReadback",
                    [
                        "afterMs": .int(delay), "actual": .optional(actual),
                        "before": .optional(before), "changed": .bool(actual != before),
                        "capsLock": .bool(capsLock), "capsAtMono": .double(mono),
                        "details": .object(inputSourceManager.currentInputSourceDetails().mapValues(JSONValue.string)),
                    ]
                )
                if delay == delays.last {
                    logUsage(
                        "capsSettled",
                        [
                            "before": .optional(before), "after": .optional(actual),
                            "changed": .bool(actual != before), "capsAtMono": .double(mono),
                            "lastChangeSeenBy": .optional(lastObservedSourceID),
                        ]
                    )
                }
            }
        }
    }

    private func handleKeyDown(
        _ key: SlashCommandKey,
        shifted: Bool,
        category: ShiftKeyCategory?,
        detail: KeyDetail?
    ) -> Bool {
        let keyFields = keyLogFields(key, shifted: shifted, category: category, detail: detail)
        noteTypingForFieldText(key)
        // Keys typed while Shift switches back wait for it, so they are typed
        // with the input source used before.
        if shiftRestoreTask != nil {
            shiftRestoreHoldsKeys = true
            logUsage("key", keyFields + ["held": "shiftRestore"])
            return true
        }
        guard let app = currentApplication else {
            logUsage("key", keyFields + ["held": "noApp"])
            return false
        }

        let pressed = ContinuousClock.now
        let currentID = inputSourceManager.currentInputSource()?.id

        var shiftDecision = ShiftEnglishTracker.Decision.pass
        let options = shiftOptions(in: app)
        if shiftTracker.isSwitched || options != nil {
            shiftDecision = shiftTracker.handle(
                category,
                keyCode: detail?.keyCode,
                shifted: shifted,
                currentID: currentID,
                englishID: effectiveEnglishInputSource?.id,
                options: options ?? .off
            )
            if shiftDecision != .pass {
                Diagnostics.record(
                    .shift, .debug,
                    "key \(String(describing: key)) (\(category?.rawValue ?? "-")) in \(app.bundleIdentifier) with \(currentID ?? "nil"): \(String(describing: shiftDecision))"
                )
            }
        }

        // The slash tracker sees every key, so it knows what was typed.
        let holdsForSlash = watchesSlashCommands(in: app)
            && handleSlashCommandKey(key, in: app, currentID: currentID, pressed: pressed)

        logUsage(
            "key",
            keyFields + [
                "current": .optional(currentID),
                "shift": .string(String(describing: shiftDecision)),
                "heldForSlash": .bool(holdsForSlash),
                "slashState": .string(slashCommandTracker.stateDescription),
            ]
        )
        probeKey(key, keyFields: keyFields, currentID: currentID)

        switch shiftDecision {
        case .pass:
            return holdsForSlash
        case let .switchToEnglish(englishID):
            guard selectInputSourceForKeys(englishID, reason: "shift") else {
                shiftTracker.cancel()
                return holdsForSlash
            }
            shiftSwitchTask = releaseHeldKeys(after: effectiveSlashCommandSwitchDelay, pressed: pressed)
            return true
        case let .restore(previousID):
            // Shift was let go without the monitor seeing it.
            shiftRestoreHoldsKeys = true
            restoreAfterShift(previousID)
            return true
        }
    }

    /// Switches back once the key typed with Shift reached the application,
    /// then types the keys pressed meanwhile.
    private func restoreAfterShift(_ previousID: String) {
        let englishID = inputSourceManager.currentInputSource()?.id
        let pendingSwitch = shiftSwitchTask
        let delay = shiftRestoreDelay
        let switchDelay = effectiveSlashCommandSwitchDelay
        shiftRestoreTask = Task { [weak self] in
            await pendingSwitch?.value
            try? await Task.sleep(for: delay, tolerance: .milliseconds(1))
            guard let self else { return }

            let selectedID = inputSourceManager.currentInputSource()?.id
            if selectedID == englishID {
                await restoreInputSource(previousID, reason: "shiftRestore")
            } else {
                Diagnostics.record(.shift, .info, "restore skipped, \(selectedID ?? "nil") was selected meanwhile")
                logUsage(
                    "switchSkipped",
                    ["reason": "shiftRestore", "wanted": .string(previousID), "selected": .optional(selectedID)]
                )
            }

            if shiftRestoreHoldsKeys {
                try? await Task.sleep(for: switchDelay, tolerance: .milliseconds(1))
                logUsage(
                    "heldKeysReleased",
                    [
                        "reason": "shiftRestore",
                        "count": .int(keyEventMonitor.heldKeyCount),
                        "current": .optional(inputSourceManager.currentInputSource()?.id),
                    ]
                )
                keyEventMonitor.releaseHeldKeys()
            }
            shiftRestoreHoldsKeys = false
            shiftRestoreTask = nil
        }
    }

    /// Types the held keys once the application had a moment to leave the
    /// input method, or it would still type the first one with it.
    private func releaseHeldKeys(after delay: Duration, pressed: ContinuousClock.Instant) -> Task<Void, Never> {
        Task { [weak self] in
            // Without a tolerance the timer may fire 10 ms late.
            try? await Task.sleep(for: delay, tolerance: .milliseconds(1))
            if let self {
                logUsage(
                    "heldKeysReleased",
                    [
                        "reason": "switch",
                        "count": .int(keyEventMonitor.heldKeyCount),
                        "current": .optional(inputSourceManager.currentInputSource()?.id),
                    ]
                )
            }
            self?.keyEventMonitor.releaseHeldKeys()
            let elapsed = Diagnostics.milliseconds(since: pressed)
            Diagnostics.record(.slash, .debug, "held keys released \(elapsed) ms after the first was pressed")
        }
    }

    /// Returns true to hold the key back.
    private func handleSlashCommandKey(
        _ key: SlashCommandKey,
        in app: RunningApplicationInfo,
        currentID: String?,
        pressed: ContinuousClock.Instant
    ) -> Bool {
        let decision = slashCommandTracker.handle(
            key,
            currentID: currentID,
            englishID: effectiveEnglishInputSource?.id,
            caretAtStart: {
                guard SlashCommandApp.reportsCaretPosition(bundleIdentifier: app.bundleIdentifier) else { return nil }
                let start = ContinuousClock.now
                let atStart = focusedFieldProvider.isCaretAtStart()
                let elapsed = Diagnostics.milliseconds(since: start)
                Diagnostics.record(
                    .slash, .debug,
                    "caret at start: \(String(describing: atStart)), \(elapsed) ms"
                )
                return atStart
            }
        )
        let state = slashCommandTracker.stateDescription
        Diagnostics.record(
            .slash, .debug,
            "key \(String(describing: key)) in \(app.bundleIdentifier) with \(currentID ?? "nil"): \(String(describing: decision)), now \(state)"
        )

        switch decision {
        case .pass:
            return false
        case let .switchToEnglish(englishID):
            guard selectInputSourceForKeys(englishID, reason: "slash") else {
                slashCommandTracker.cancelCommand()
                return false
            }
            // Otherwise the slash would still be typed as 「、」.
            _ = releaseHeldKeys(after: effectiveSlashCommandSwitchDelay, pressed: pressed)
            return true
        case let .restore(previousID):
            // Return and Escape reach the application first, still typed with
            // the English input source.
            let englishID = currentID
            let delay = slashCommandRestoreDelay
            Task { [weak self] in
                try? await Task.sleep(for: delay)
                guard let self else { return }
                let selectedID = inputSourceManager.currentInputSource()?.id
                guard selectedID == englishID else {
                    Diagnostics.record(
                        .slash, .info,
                        "restore skipped, \(selectedID ?? "nil") was selected meanwhile"
                    )
                    logUsage(
                        "switchSkipped",
                        ["reason": "slashRestore", "wanted": .string(previousID), "selected": .optional(selectedID)]
                    )
                    return
                }
                await restoreInputSource(previousID, reason: "slashRestore")
            }
            return false
        }
    }

    private var effectiveSlashCommandSwitchDelay: Duration {
        guard defaults.object(forKey: Self.slashCommandSwitchDelayKey) != nil else {
            return slashCommandSwitchDelay
        }
        let milliseconds = defaults.integer(forKey: Self.slashCommandSwitchDelayKey)
        return .milliseconds(min(max(milliseconds, 0), 200))
    }

    /// Ends a command when focus moved to another field or application.
    private func endSlashCommandForFocusChange() {
        let wasInCommand = slashCommandTracker.isInCommand
        let decision = slashCommandTracker.focusChanged(currentID: inputSourceManager.currentInputSource()?.id)
        if wasInCommand {
            Diagnostics.record(.slash, .info, "focus changed during a command: \(String(describing: decision))")
        }
        if wasInCommand {
            logUsage("slashEnd", ["why": "focusChanged", "decision": .string(String(describing: decision))])
        }
        if case let .restore(previousID) = decision {
            selectInputSourceForKeys(previousID, reason: "slashRestore")
        }
    }

    @discardableResult
    private func selectInputSourceForKeys(_ id: String, reason: String) -> Bool {
        let selected = selectLogged(id, reason: reason, from: inputSourceManager.currentInputSource()?.id)
        guard selected else { return false }
        switchCounter.recordSwitch()
        switchCount = switchCounter.count
        currentInputSource = inputSources.first { $0.id == id } ?? inputSourceManager.currentInputSource()
        return true
    }

    // MARK: - Chinese and English input sources

    var effectiveChineseInputSource: InputSource? {
        resolveInputSource(chineseInputSourceSelection) { detectedChineseInputSource }
    }

    /// An input method that is not a keyboard layout, for example Shuangpin. Apple's own Chinese input methods come
    /// first so that the result does not depend on how third-party input
    /// methods such as 微信键盘 or 搜狗 happen to be named.
    var detectedChineseInputSource: InputSource? {
        let candidates = inputSources.filter { !Self.isKeyboardLayout($0.id) }
        return candidates.first(where: { Self.isAppleChineseInputMethod($0.id) }) ?? candidates.first
    }

    private static let appleChineseInputMethodPrefixes = [
        "com.apple.inputmethod.SCIM",
        "com.apple.inputmethod.TCIM",
        "com.apple.inputmethod.TYIM",
    ]

    private static func isAppleChineseInputMethod(_ id: String) -> Bool {
        appleChineseInputMethodPrefixes.contains { id.hasPrefix($0) }
    }

    var effectiveEnglishInputSource: InputSource? {
        resolveInputSource(englishInputSourceSelection) { detectedEnglishInputSource }
    }

    /// The first keyboard layout, for example U.S. or ABC.
    var detectedEnglishInputSource: InputSource? {
        inputSources.first { Self.isKeyboardLayout($0.id) }
    }

    var chineseInputSourceChoices: [InputSourceChoice] {
        settingChoices(for: chineseInputSourceSelection)
    }

    var englishInputSourceChoices: [InputSourceChoice] {
        settingChoices(for: englishInputSourceSelection)
    }

    private static func isKeyboardLayout(_ id: String) -> Bool {
        id.contains(".keylayout.")
    }

    private static func roleName(forRuleID id: String) -> String? {
        switch id {
        case chineseRuleID: return "中文"
        case englishRuleID: return "英文"
        default: return nil
        }
    }

    /// The input source a rule switches to: the role's input source for a role,
    /// otherwise the saved identifier itself.
    private func targetInputSourceID(forRuleID id: String) -> String? {
        switch id {
        case Self.chineseRuleID: return effectiveChineseInputSource?.id
        case Self.englishRuleID: return effectiveEnglishInputSource?.id
        default: return id
        }
    }

    private func resolveInputSource(_ selection: String, detected: () -> InputSource?) -> InputSource? {
        if selection == Self.automaticInputSourceID {
            return detected()
        }
        return inputSources.first { $0.id == selection }
    }

    private func persistSelection(_ selection: String, forKey key: String) {
        if selection == Self.automaticInputSourceID {
            defaults.removeObject(forKey: key)
        } else {
            defaults.set(selection, forKey: key)
        }
    }

    /// Rules that name the input source a role used to stand for were shown as
    /// that role, so they keep following it after the role changes.
    private func adoptRole(_ roleID: String, forRulesUsing previous: InputSource?) {
        guard
            let previous,
            let roleName = Self.roleName(forRuleID: roleID)
        else {
            return
        }

        if defaultInputSourceSelection == previous.id {
            defaultInputSourceSelection = roleID
        }
        if addressBarInputSourceSelection == previous.id {
            addressBarInputSourceSelection = roleID
        }

        if fieldRuleEditingEnabled {
            var fieldCandidate = fieldRuleSet
            for rule in fieldRuleSet.rules where rule.inputSourceID == previous.id {
                var updated = rule
                updated.inputSourceID = roleID
                updated.inputSourceName = roleName
                fieldCandidate.upsert(updated)
            }
            if fieldCandidate != fieldRuleSet {
                commitFieldRules(fieldCandidate)
            }
        }

        guard ruleEditingEnabled else { return }
        var candidate = ruleSet
        for rule in ruleSet.rules where rule.inputSourceID == previous.id {
            var updated = rule
            updated.inputSourceID = roleID
            updated.inputSourceName = roleName
            candidate.upsert(updated)
        }

        if candidate != ruleSet {
            commit(candidate)
        }

        guard commandRuleEditingEnabled else { return }
        var commandCandidate = commandRuleSet
        for rule in commandRuleSet.rules where rule.inputSourceID == previous.id {
            var updated = rule
            updated.inputSourceID = roleID
            updated.inputSourceName = roleName
            commandCandidate.upsert(updated)
        }
        if commandCandidate != commandRuleSet {
            commitCommandRules(commandCandidate)
        }
    }

    // MARK: - Launch at login

    var isLaunchAtLoginEnabled: Bool {
        launchAtLoginStatus.isEnabled
    }

    /// Turns the system's input source bubble next to the caret on or off.
    func setInputSourceIndicatorEnabled(_ enabled: Bool) {
        inputSourceIndicator.setEnabled(enabled)
        refreshInputSourceIndicator()
    }

    /// Reads the setting again, since it can be changed outside MoliSwitch.
    func refreshInputSourceIndicator() {
        let enabled = inputSourceIndicator.isEnabled
        if inputSourceIndicatorEnabled != enabled {
            inputSourceIndicatorEnabled = enabled
        }
    }

    func setLaunchAtLoginEnabled(_ enabled: Bool) {
        do {
            if enabled {
                if loginItemManager.status == .requiresApproval {
                    // Never register again while the system is waiting for the
                    // user to allow the login item.
                    loginStatus = StatusMessage(
                        text: "“登录时打开”正在等待系统批准，请在“系统设置 › 通用 › 登录项”中允许。",
                        severity: .warning
                    )
                    refreshLaunchAtLoginStatus()
                } else if loginItemManager.status != .enabled {
                    try loginItemManager.register()
                    reportLoginStatus()
                }
            } else {
                if loginItemManager.status.isRegistered {
                    try loginItemManager.unregister()
                }
                reportLoginStatus()
            }
        } catch {
            refreshLaunchAtLoginStatus()
            loginStatus = StatusMessage(
                text: "“登录时打开”设置失败：" + error.localizedDescription,
                severity: .error
            )
        }
    }

    func refreshLaunchAtLoginStatus() {
        launchAtLoginStatus = loginItemManager.status
    }

    func openLoginItemsSystemSettings() {
        loginItemManager.openSystemSettingsLoginItems()
    }

    private func reportLoginStatus() {
        refreshLaunchAtLoginStatus()

        switch launchAtLoginStatus {
        case .enabled:
            loginStatus = StatusMessage(text: "已开启登录时打开")
        case .notRegistered, .notFound:
            // A fresh install that was never registered reports notFound.
            loginStatus = StatusMessage(text: "已关闭登录时打开")
        case .requiresApproval:
            loginStatus = StatusMessage(
                text: "“登录时打开”正在等待系统批准，请在“系统设置 › 通用 › 登录项”中允许。",
                severity: .warning
            )
        }
    }

    // MARK: - Updates

    var canCheckForUpdates: Bool {
        updateController?.canCheckForUpdates ?? false
    }

    func checkForUpdates() {
        updateController?.checkForUpdates()
    }

    // MARK: - Status line

    /// The most severe outstanding status. Unrelated activity can only ever clear
    /// its own entry, so an error is never hidden by a later informational message.
    var primaryStatus: StatusMessage? {
        let candidates = [storageStatus, scanStatus, inputSourceStatus, loginStatus]
            .compactMap(\.self)

        var best: StatusMessage?
        for candidate in candidates {
            if let current = best {
                if candidate.severity > current.severity {
                    best = candidate
                }
            } else {
                best = candidate
            }
        }

        return best
    }

    var statusText: String {
        primaryStatus?.text ?? "显示 " + String(filteredInstalledApplications.count) + " 个应用"
    }

    // MARK: - Foreground application monitoring

    private func startMonitoring() {
        guard activationObserver == nil else { return }

        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard
                let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                as? NSRunningApplication
            else {
                return
            }

            let activatedProcessIdentifier = app.processIdentifier
            let runtime = self

            Task { @MainActor in
                // Re-check just before acting: the foreground application may have
                // changed again while this event was queued.
                guard
                    let runtime,
                    let frontmost = NSWorkspace.shared.frontmostApplication,
                    frontmost.processIdentifier == activatedProcessIdentifier
                else {
                    return
                }

                runtime.updateCurrentApplication(from: frontmost)
            }
        }

        inputSourceManager.startMonitoringEnabledSources { [weak self] in
            self?.refreshInputSources()
        }

        inputSourceManager.startMonitoringSelectedSource { [weak self] in
            self?.handleSelectedInputSourceChanged()
        }
    }

    private func updateCurrentApplication(from app: NSRunningApplication?) {
        guard
            let app,
            let bundleIdentifier = app.bundleIdentifier,
            bundleIdentifier != ownBundleIdentifier
        else {
            currentApplication = nil
            currentInputSource = inputSourceManager.currentInputSource()
            lastFocusMono = UsageEvent.currentMonotonicMilliseconds()
            logUsage(
                "appFocus",
                [
                    "ownApp": .bool(app?.bundleIdentifier != nil && app?.bundleIdentifier == ownBundleIdentifier),
                    "frontmost": .optional(app?.bundleIdentifier),
                    "frontmostName": .optional(app?.localizedName),
                    "current": .optional(currentInputSource?.id),
                ]
            )
            updateTerminalPolling(for: nil)
            stopFollowingFields()
            return
        }

        let applicationInfo = RunningApplicationInfo(
            bundleIdentifier: bundleIdentifier,
            name: app.localizedName ?? bundleIdentifier
        )
        currentApplication = applicationInfo
        applyRuleIfNeeded(for: applicationInfo)
    }

    /// Applies the rule for an application that just became active, and starts
    /// following the program in its active tab when it is a terminal, or the
    /// focused field when a field of the application has a rule.
    func applyRuleIfNeeded(for app: RunningApplicationInfo) {
        if currentApplication != app {
            currentApplication = app
        }

        var context: TerminalContext?
        if case let .found(found)? = terminalContext(for: app) {
            context = found
        }
        terminalContextInEffect = context
        fieldRestore = nil
        endSlashCommandForFocusChange()
        // The rule of the application decides now.
        shiftTracker.cancel()
        followFields(of: app)

        let rule = activeRule(for: app)
        lastFocusMono = UsageEvent.currentMonotonicMilliseconds()
        logUsage(
            "appFocus",
            [
                "appName": .string(app.name),
                "current": .optional(inputSourceManager.currentInputSource()?.id),
                "ruleKind": .optional(rule.map { Self.ruleKind(of: $0.key) }),
                "ruleKey": .optional(rule?.key),
                "ruleTarget": .optional(rule?.inputSourceID),
                "terminal": Self.jsonValue(of: terminalContextInEffect),
            ]
        )
        logSnapshot("appFocus")
        apply(rule)
        updateTerminalPolling(for: app)
    }

    /// The rule in effect: the command rule for the program in the active
    /// terminal tab, otherwise the rule of the focused field, otherwise the rule
    /// of the application, otherwise the default input source.
    private struct ActiveRule {
        /// Identifies the context the rule was chosen for.
        let key: String
        let inputSourceID: String
        let inputSourceName: String
        /// True for the rule of a single field, including the address bar.
        var isFieldRule = false
    }

    private func activeRule(for app: RunningApplicationInfo) -> ActiveRule? {
        let context = terminalContextInEffect
        let tab = context.map { "@" + $0.tty } ?? ""

        if let context, let rule = commandRuleSet.rule(matchingAnyOf: context.candidates) {
            return ActiveRule(
                key: "command:" + rule.id + tab + "=" + rule.inputSourceID,
                inputSourceID: rule.inputSourceID,
                inputSourceName: rule.inputSourceName
            )
        }

        if let rule = activeFieldRule(for: app) {
            return rule
        }

        if let rule = ruleSet.rule(forBundleIdentifier: app.bundleIdentifier) {
            guard rule.inputSourceID != Self.noSwitchInputSourceID else { return nil }
            return ActiveRule(
                key: "app:" + app.bundleIdentifier + tab + "=" + rule.inputSourceID,
                inputSourceID: rule.inputSourceID,
                inputSourceName: rule.inputSourceName
            )
        }

        let defaultID = defaultInputSourceSelection
        guard defaultID != Self.noSwitchInputSourceID else { return nil }
        return ActiveRule(
            key: "default:" + app.bundleIdentifier + tab + "=" + defaultID,
            inputSourceID: defaultID,
            inputSourceName: defaultInputSourceDescription
        )
    }

    /// Makes a rule the one in effect and switches to its input source. Leaving a
    /// field whose rule switched the input source, for a place without any rule,
    /// returns to the input source used before the field.
    private func apply(_ rule: ActiveRule?) {
        let previousKey = appliedRuleKey
        appliedRuleKey = rule?.key

        if let rule, rule.isFieldRule {
            if fieldRestore == nil, let currentID = inputSourceManager.currentInputSource()?.id {
                fieldRestore = (currentID, nil)
            }
            switchInputSource(to: rule)
            fieldRestore?.fieldID = targetInputSourceID(forRuleID: rule.inputSourceID)
            return
        }

        let restore = fieldRestore
        fieldRestore = nil

        if
            rule == nil,
            previousKey != nil,
            let restore,
            restore.previousID != restore.fieldID,
            inputSourceManager.currentInputSource()?.id == restore.fieldID
        {
            let name = inputSources.first { $0.id == restore.previousID }?.name ?? restore.previousID
            switchInputSource(
                to: ActiveRule(key: "restore", inputSourceID: restore.previousID, inputSourceName: name)
            )
            return
        }

        switchInputSource(to: rule)
    }

    /// Applies the rule for the current context when it differs from the one in
    /// effect, which keeps a manual switch inside the same context.
    private func reapplyIfContextChanged(for app: RunningApplicationInfo) {
        let rule = activeRule(for: app)
        guard rule?.key != appliedRuleKey else { return }

        apply(rule)
    }

    private func switchInputSource(to rule: ActiveRule?) {
        guard let rule else {
            logUsage("switchSkipped", ["reason": "noRule"])
            currentInputSource = inputSourceManager.currentInputSource()
            inputSourceStatus = nil
            return
        }

        guard let targetID = targetInputSourceID(forRuleID: rule.inputSourceID) else {
            logUsage(
                "switchSkipped",
                [
                    "reason": "targetMissing", "ruleKind": .string(Self.ruleKind(of: rule.key)),
                    "ruleKey": .string(rule.key), "wanted": .string(rule.inputSourceID),
                ]
            )
            inputSourceStatus = StatusMessage(
                text: "还没有找到" + rule.inputSourceName + "输入法，请在设置里选择。",
                severity: .warning
            )
            currentInputSource = inputSourceManager.currentInputSource()
            return
        }

        let currentID = inputSourceManager.currentInputSource()?.id
        if currentID != targetID {
            // The count only tracks input sources that were actually switched.
            if selectLogged(targetID, reason: Self.ruleKind(of: rule.key), rule: rule, from: currentID) {
                switchCounter.recordSwitch()
                switchCount = switchCounter.count
                inputSourceStatus = nil
            } else {
                inputSourceStatus = StatusMessage(
                    text: "输入法切换失败：" + rule.inputSourceName + " 当前不可用。",
                    severity: .warning
                )
            }
        } else {
            logUsage(
                "switchSkipped",
                [
                    "reason": "alreadyThere", "ruleKind": .string(Self.ruleKind(of: rule.key)),
                    "ruleKey": .string(rule.key), "current": .string(targetID),
                ]
            )
            inputSourceStatus = nil
        }

        currentInputSource = inputSourceManager.currentInputSource()
    }

    // MARK: - Focused fields

    /// Focus is only followed where a field rule or a slash command could apply,
    /// so other applications are never touched through Accessibility.
    private func followsFields(_ app: RunningApplicationInfo) -> Bool {
        accessibilityTrusted
            && (fieldRuleSet.hasRules(forBundleIdentifier: app.bundleIdentifier)
                || (addressBarSwitchingEnabled && AddressBarDetector.isBrowser(bundleIdentifier: app.bundleIdentifier))
                || watchesSlashCommands(in: app)
                || usageLoggingEnabled)
    }

    private func followFields(of app: RunningApplicationInfo) {
        refreshAccessibilityTrust()

        guard followsFields(app) else {
            stopFollowingFields()
            return
        }

        fieldApplication = app
        focusedFieldProvider.startObserving(bundleIdentifier: app.bundleIdentifier) { [weak self] field in
            self?.handleFocusedFieldChanged(field)
        }
        focusedField = focusedFieldProvider.currentField()
        let details = focusedFieldProvider.currentFieldDetails(includeValue: false)
        lastFieldDetailsKey = String(describing: details.sorted { $0.key < $1.key })
        logUsage(
            "fieldFocus",
            ["field": Self.jsonValue(of: focusedField), "detail": .object(details), "initial": true]
        )
    }

    private func stopFollowingFields() {
        guard fieldApplication != nil else { return }
        focusedFieldProvider.stopObserving()
        fieldApplication = nil
        focusedField = nil
    }

    private func handleFocusedFieldChanged(_ field: FieldSignature?) {
        guard let app = fieldApplication, app == currentApplication else { return }
        let details = focusedFieldProvider.currentFieldDetails(includeValue: false)
        let detailsKey = String(describing: details.sorted { $0.key < $1.key })
        let changed = field != focusedField
        guard changed || detailsKey != lastFieldDetailsKey else { return }
        lastFieldDetailsKey = detailsKey
        focusedField = field
        logUsage("fieldFocus", ["field": Self.jsonValue(of: field), "detail": .object(details)])
        guard changed else { return }
        endSlashCommandForFocusChange()
        reapplyIfContextChanged(for: app)
    }

    /// Starts or stops following fields after the rules or settings changed, and
    /// applies what changed for the current field.
    private func refreshFieldObservation() {
        guard let app = currentApplication else { return }

        if followsFields(app) {
            if fieldApplication != app {
                followFields(of: app)
            }
        } else {
            stopFollowingFields()
        }
        reapplyIfContextChanged(for: app)
    }

    private func activeFieldRule(for app: RunningApplicationInfo) -> ActiveRule? {
        guard fieldApplication == app, let field = focusedField else { return nil }

        if let rule = fieldRuleSet.rule(forBundleIdentifier: app.bundleIdentifier, matching: field) {
            return ActiveRule(
                key: "field:" + rule.id.uuidString + "=" + rule.inputSourceID,
                inputSourceID: rule.inputSourceID,
                inputSourceName: rule.inputSourceName,
                isFieldRule: true
            )
        }

        if addressBarSwitchingEnabled, AddressBarDetector.isAddressBar(
            bundleIdentifier: app.bundleIdentifier,
            field: field
        ) {
            let id = addressBarInputSourceSelection
            return ActiveRule(
                key: "addressbar:" + app.bundleIdentifier + "=" + id,
                inputSourceID: id,
                inputSourceName: inputSourceDescription(for: id),
                isFieldRule: true
            )
        }

        return nil
    }

    func refreshAccessibilityTrust() {
        let trusted = focusedFieldProvider.isTrusted
        if accessibilityTrusted != trusted {
            accessibilityTrusted = trusted
            logUsage("accessibility", ["trusted": .bool(trusted)])
            updateKeyMonitoring()
        } else if keyMonitoringUnavailable {
            updateKeyMonitoring()
        }
    }

    func requestAccessibilityTrust() {
        focusedFieldProvider.requestTrust()
        refreshAccessibilityTrust()
    }

    func openAccessibilitySystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Programs in the terminal

    /// Terminal tabs are only inspected while a command rule could apply, so the
    /// Automation permission is not requested from people who never use them.
    private func followsTerminal(_ app: RunningApplicationInfo) -> Bool {
        terminalSwitchingEnabled
            && !commandRuleSet.rules.isEmpty
            && terminalContextProvider.supportsTerminal(bundleIdentifier: app.bundleIdentifier)
    }

    private func terminalContext(for app: RunningApplicationInfo) -> TerminalContextResult? {
        guard followsTerminal(app) else { return nil }
        return noteTerminalContext(terminalContextProvider.foregroundContext(bundleIdentifier: app.bundleIdentifier))
    }

    private func noteTerminalContext(_ result: TerminalContextResult) -> TerminalContextResult {
        switch result {
        case let .found(context):
            terminalUnavailableLogged = false
            if terminalAccessDenied {
                terminalAccessDenied = false
            }
            if lastTerminalContext != context {
                lastTerminalContext = context
                logUsage("terminal", ["result": "found", "context": Self.jsonValue(of: context)])
            }
        case .denied:
            if !terminalAccessDenied {
                terminalAccessDenied = true
                logUsage("terminal", ["result": "denied"])
            }
        case .unavailable:
            if !terminalUnavailableLogged {
                terminalUnavailableLogged = true
                logUsage("terminal", ["result": "unavailable"])
            }
        }
        return result
    }

    private func updateTerminalPolling(for app: RunningApplicationInfo?) {
        guard let app, followsTerminal(app) else {
            stopTerminalPolling()
            return
        }

        polledApplication = app
        guard terminalPollTask == nil else { return }

        let interval = terminalPollInterval
        terminalPollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval))
                guard !Task.isCancelled, let self else { return }
                await pollTerminal()
            }
        }
    }

    private func stopTerminalPolling() {
        terminalPollTask?.cancel()
        terminalPollTask = nil
        polledApplication = nil
    }

    /// Switches when the program in the active tab, or the tab itself, changed.
    private func pollTerminal() async {
        guard let app = polledApplication, followsTerminal(app) else {
            stopTerminalPolling()
            return
        }

        let asked = await terminalContextProvider.foregroundContextInBackground(bundleIdentifier: app.bundleIdentifier)
        // Another application may have become active in the meantime.
        guard !Task.isCancelled, polledApplication == app, followsTerminal(app) else { return }
        let result = noteTerminalContext(asked)

        switch result {
        case let .found(found):
            terminalContextInEffect = found
        case .denied:
            terminalContextInEffect = nil
        case .unavailable:
            // Keep the current rule instead of falling back for a moment.
            return
        }

        reapplyIfContextChanged(for: app)
    }

    // MARK: - Selected input source

    private func handleSelectedInputSourceChanged() {
        let previousID = lastObservedSourceID
        let now = inputSourceManager.currentInputSource()
        currentInputSource = now
        lastObservedSourceID = now?.id
        guard usageLogger.isEnabled else { return }

        // The system also reports the switches this app asked for.
        let mono = UsageEvent.currentMonotonicMilliseconds()
        let ownSwitch = pendingSelfSwitch.map { $0.id == now?.id && mono - $0.mono < 1000 } ?? false
        var fields: [String: JSONValue] = [
            "from": .optional(previousID),
            "to": .optional(now?.id),
            "toName": .optional(now?.name),
            "ownSwitch": .bool(ownSwitch),
            "details": .object(inputSourceManager.currentInputSourceDetails().mapValues(JSONValue.string)),
        ]
        if let pendingSelfSwitch {
            fields["sinceOwnSwitchMs"] = .double(mono - pendingSelfSwitch.mono)
            fields["ownSwitchTarget"] = .string(pendingSelfSwitch.id)
        }
        if let lastCapsMono {
            fields["sinceCapsMs"] = .double(mono - lastCapsMono)
        }
        if let lastModifierMono {
            fields["sinceModifierMs"] = .double(mono - lastModifierMono)
        }
        logUsage("systemInputSourceChanged", fields)
        probe(
            "sourceChangeProbe",
            ["from": .optional(previousID), "to": .optional(now?.id), "ownSwitch": .bool(ownSwitch)],
            parts: .all
        )

        guard !ownSwitch, previousID != now?.id else { return }
        var manual = fields
        manual["details"] = nil
        manual["ownSwitchTarget"] = nil
        if let lastFocusMono {
            manual["sinceFocusMs"] = .double(mono - lastFocusMono)
        }
        manual["appliedRuleKey"] = .optional(appliedRuleKey)
        if let last = lastManualChange, mono - last.mono < 150 {
            manual["sincePreviousManualMs"] = .double(mono - last.mono)
            manual["undoesPrevious"] = .bool(last.from == now?.id && last.to == previousID)
        }
        lastManualChange = (previousID, now?.id, mono)
        logUsage("manualSwitch", manual)
        logSnapshot("manualSwitch")
    }

    // MARK: - Usage log

    /// Shows the newest day's file in Finder.
    func revealUsageLogFolder() {
        usageLogger.flush()
        let directory = JSONLUsageLogger.defaultDirectory()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting(
            [(usageLogger as? JSONLUsageLogger)?.logFiles().last ?? directory]
        )
    }

    func clearUsageLog() {
        (usageLogger as? JSONLUsageLogger)?.clear()
    }

    /// Writes one event. Cheap when the log is off, and never touches the disk
    /// on the calling thread, so it is safe on the key path.
    private func logUsage(_ name: String, _ fields: [String: JSONValue] = [:]) {
        guard usageLogger.isEnabled else { return }
        var fields = fields
        if fields["app"] == nil {
            fields["app"] = .optional(currentApplication?.bundleIdentifier)
        }
        usageLogger.log(UsageEvent(name, fields))
    }

    /// Everything that decides what happens next, so a log shows the state at
    /// that moment and not only the decisions.
    private func logSnapshot(_ reason: String) {
        guard usageLogger.isEnabled else { return }
        probe("snapshotProbe", ["reason": .string(reason)], parts: .all)

        let current = inputSourceManager.currentInputSource()
        let options = globalShiftOptions
        logUsage(
            "snapshot",
            [
                "reason": .string(reason),
                "appName": .optional(currentApplication?.name),
                "current": .optional(current?.id),
                "currentName": .optional(current?.name),
                "details": .object(inputSourceManager.currentInputSourceDetails().mapValues(JSONValue.string)),
                "enabledSources": .strings(inputSources.map(\.id)),
                "chinese": .optional(effectiveChineseInputSource?.id),
                "english": .optional(effectiveEnglishInputSource?.id),
                "status": .optional(inputSourceStatus?.text),
                "appliedRuleKey": .optional(appliedRuleKey),
                "focusedField": Self.jsonValue(of: focusedField),
                "fieldRestore": .optional(fieldRestore.map { ($0.previousID) + ">" + ($0.fieldID ?? "?") }),
                "terminal": Self.jsonValue(of: terminalContextInEffect),
                "terminalAccessDenied": .bool(terminalAccessDenied),
                "slashState": .string(slashCommandTracker.stateDescription),
                "shiftSwitched": .bool(shiftTracker.isSwitched),
                "accessibility": .bool(accessibilityTrusted),
                "capsLockOn": .bool(CGEventSource.flagsState(.combinedSessionState).contains(.maskAlphaShift)),
                "recentCapsAgoMs": .array(recentCapsMonos
                    .map { .double(UsageEvent.currentMonotonicMilliseconds() - $0) }),
                "keyMonitorRunning": .bool(keyEventMonitor.isRunning),
                "keyMonitoringUnavailable": .bool(keyMonitoringUnavailable),
                "caretIndicator": .bool(inputSourceIndicatorEnabled),
                "switchCount": .int(switchCount),
                "settings": .object([
                    "shiftEnabled": .bool(shiftEnglishEnabled),
                    "shiftCategories": .strings(options.categories.map(\.rawValue).sorted()),
                    "shiftKeyCodes": .array(options.keyCodes.sorted().map(JSONValue.int)),
                    "shiftRestores": .bool(options.restoresOnRelease),
                    "slashEnabled": .bool(slashCommandSwitchingEnabled),
                    "slashRestoresOnSpace": .bool(slashCommandRestoresOnSpace),
                    "slashDelayMs": .double(Self.milliseconds(of: effectiveSlashCommandSwitchDelay)),
                    "terminalEnabled": .bool(terminalSwitchingEnabled),
                    "terminalPollSeconds": .double(terminalPollInterval),
                    "addressBarEnabled": .bool(addressBarSwitchingEnabled),
                    "addressBarTarget": .string(addressBarInputSourceSelection),
                    "defaultTarget": .string(defaultInputSourceSelection),
                    "appRules": .int(ruleSet.rules.count),
                    "commandRules": .int(commandRuleSet.rules.count),
                    "fieldRules": .int(fieldRuleSet.rules.count),
                    "slashApps": .int(slashCommandApps.apps.count),
                    "shiftAppRules": .int(shiftAppRules.rules.count),
                ]),
            ]
        )
    }

    private func startSnapshotHeartbeat() {
        snapshotTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                guard !Task.isCancelled, let self else { return }
                logSnapshot("heartbeat")
            }
        }
    }

    /// Selects an input source and records what came of it: how long it took,
    /// why it failed, and what the system says shortly after.
    private func selectLogged(_ id: String, reason: String, rule: ActiveRule? = nil, from: String?) -> Bool {
        switchSequence += 1
        probe(
            "switchProbe",
            ["seq": .int(switchSequence), "phase": "before", "reason": .string(reason), "to": .string(id)],
            parts: .all
        )
        let start = ContinuousClock.now
        pendingSelfSwitch = (id, UsageEvent.currentMonotonicMilliseconds())
        let selected = inputSourceManager.selectInputSource(id: id)
        let elapsed = Diagnostics.milliseconds(since: start)
        Diagnostics.record(.slash, .info, "select \(id): \(selected ? "ok" : "failed"), \(elapsed) ms")

        var fields: [String: JSONValue] = [
            "reason": .string(reason),
            "from": .optional(from),
            "to": .string(id),
            "ok": .bool(selected),
            "ms": .double(Double(elapsed) ?? 0),
        ]
        if let rule {
            fields["ruleKind"] = .string(Self.ruleKind(of: rule.key))
            fields["ruleKey"] = .string(rule.key)
        }
        if !selected {
            pendingSelfSwitch = nil
            fields["failure"] = .optional(inputSourceManager.lastSelectionFailure)
        }
        logUsage("switch", fields)

        if selected {
            scheduleSwitchVerification(target: id, reason: reason)
        } else {
            logSnapshot("switchFailed")
        }
        return selected
    }

    /// Reads the input source back after a switch: a different answer means
    /// the system or the input method changed it again.
    private func scheduleSwitchVerification(target: String, reason: String) {
        guard usageLogger.isEnabled else { return }
        lastOwnSwitchMono = UsageEvent.currentMonotonicMilliseconds()
        for delay in [0, 30, 80, 150, 300, 1000] {
            probe(
                "switchProbe",
                [
                    "seq": .int(switchSequence),
                    "phase": "after",
                    "afterMs": .int(delay),
                    "reason": .string(reason),
                    "target": .string(target),
                ],
                parts: delay == 150 || delay == 1000 ? .all : [.windows],
                afterMs: delay
            )
        }
        for delay in [50, 300] {
            Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(delay))
                guard let self else { return }
                let actual = inputSourceManager.currentInputSource()?.id
                logUsage(
                    "switchVerify",
                    [
                        "target": .string(target), "actual": .optional(actual),
                        "match": .bool(actual == target), "afterMs": .int(delay),
                    ]
                )
            }
        }
    }

    // MARK: - Switching back

    private var restoreUsesSystemShortcut: Bool {
        defaults.object(forKey: Self.restoreUsesSystemShortcutKey) as? Bool ?? true
    }

    /// Switches back to the input source used before Shift or a slash command
    /// switched to English.
    ///
    /// Selected directly from here, an input method such as Shuangpin is
    /// sometimes current for the system while the frontmost application keeps
    /// typing letters, until Caps Lock is pressed twice. Caps Lock switches
    /// inside the application, so the same is done here with the system
    /// shortcut for the previous input source, when that is the one wanted.
    /// Selecting directly stays as the fallback.
    private func restoreInputSource(_ id: String, reason: String) async {
        let from = inputSourceManager.currentInputSource()?.id
        let basis = shortcutRestoreBasis(target: id, from: from)
        guard
            restoreUsesSystemShortcut,
            keyEventMonitor.supportsInputSourceShortcut,
            from != id,
            let basis
        else {
            selectInputSourceForKeys(id, reason: reason)
            return
        }

        switchSequence += 1
        let sequence = switchSequence
        probe(
            "switchProbe",
            [
                "seq": .int(sequence),
                "phase": "before",
                "reason": .string(reason),
                "to": .string(id),
                "method": "shortcut",
            ],
            parts: .all
        )
        let start = ContinuousClock.now
        pendingSelfSwitch = (id, UsageEvent.currentMonotonicMilliseconds())
        guard let shortcut = keyEventMonitor.postSelectPreviousInputSourceShortcut() else {
            pendingSelfSwitch = nil
            logUsage(
                "switchShortcutUnavailable",
                ["reason": .string(reason), "to": .string(id), "from": .optional(from)]
            )
            selectInputSourceForKeys(id, reason: reason)
            return
        }

        // The keys held meanwhile are typed after the shortcut in any case,
        // as they are posted after it; this wait is for the log and the fallback.
        var current = from
        let deadline = start + .milliseconds(200)
        var polls = 0
        while ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(3), tolerance: .milliseconds(1))
            polls += 1
            current = inputSourceManager.currentInputSource()?.id
            if current != from {
                break
            }
        }
        let elapsed = Self.milliseconds(of: ContinuousClock.now - start)
        var fields: [String: JSONValue] = [
            "reason": .string(reason), "from": .optional(from), "to": .string(id), "ok": .bool(current == id),
            "ms": .double(elapsed), "method": "shortcut", "shortcut": .string(shortcut), "basis": .string(basis),
            "polls": .int(polls), "seq": .int(sequence),
        ]
        guard current == id else {
            fields["actual"] = .optional(current)
            logUsage("switchShortcutMissed", fields)
            logSnapshot("switchShortcutMissed")
            selectInputSourceForKeys(id, reason: reason + "Fallback")
            return
        }
        logUsage("switch", fields)
        switchCounter.recordSwitch()
        switchCount = switchCounter.count
        currentInputSource = inputSources.first { $0.id == id } ?? inputSourceManager.currentInputSource()
        scheduleSwitchVerification(target: id, reason: reason)
    }

    /// Why the previous input source is the one wanted, or nil when it may not be.
    private func shortcutRestoreBasis(target: String, from: String?) -> String? {
        let ids = inputSources.map(\.id)
        if ids.count == 2, ids.contains(target), let from, ids.contains(from) {
            return "twoSources"
        }
        let domain = "com.apple.HIToolbox" as CFString
        CFPreferencesAppSynchronize(domain)
        guard
            let history = CFPreferencesCopyAppValue("AppleInputSourceHistory" as CFString, domain) as? [[String: Any]],
            history.count >= 2
        else {
            return nil
        }
        func id(_ entry: [String: Any]) -> String? {
            entry["Input Mode"] as? String ?? entry["Bundle ID"] as? String
        }
        return id(history[1]) == target ? "history" : nil
    }

    // MARK: - Input method probes

    private func probe(
        _ name: String,
        _ fields: [String: JSONValue],
        parts: InputMethodProbe.Parts,
        afterMs: Int = 0
    ) {
        guard usageLogger.isEnabled, let inputMethodProbe else { return }
        inputMethodProbe.record(
            name,
            fields + ["app": .optional(currentApplication?.bundleIdentifier)],
            parts: parts,
            afterMs: afterMs,
            mayLogText: mayLogTypedText()
        )
    }

    /// While an input method is current, and for three seconds after this app
    /// switched, what follows each key: the windows on screen 60 ms later
    /// (candidate windows among them), and the text around the caret during
    /// typing, at most twice a second, and once typing pauses.
    private func probeKey(_ key: SlashCommandKey, keyFields: [String: JSONValue], currentID: String?) {
        guard usageLogger.isEnabled, inputMethodProbe != nil else { return }
        let mono = UsageEvent.currentMonotonicMilliseconds()
        let afterOwnSwitch = lastOwnSwitchMono.map { mono - $0 < 3000 } ?? false
        let inInputMethod = currentID.map { !Self.isKeyboardLayout($0) } ?? false
        guard afterOwnSwitch || inInputMethod else { return }

        keySequence += 1
        var fields = keyFields
        fields["keySeq"] = .int(keySequence)
        fields["current"] = .optional(currentID)
        fields["afterOwnSwitch"] = .bool(afterOwnSwitch)
        if let lastOwnSwitchMono {
            fields["sinceOwnSwitchMs"] = .double(mono - lastOwnSwitchMono)
        }
        probe("keyProbe", fields + ["afterMs": 60], parts: afterOwnSwitch ? .all : [.windows], afterMs: 60)
        if mono - lastKeyFieldProbeMono > 500 {
            lastKeyFieldProbeMono = mono
            probe("keyProbe", fields + ["afterMs": 150], parts: [.windows, .field], afterMs: 150)
        }
        keyPauseProbeTask?.cancel()
        keyPauseProbeTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled, let self else { return }
            probe("keyPauseProbe", fields, parts: [.windows, .field, .processes])
        }
    }

    /// command, field, addressbar, app, default or restore.
    private static func ruleKind(of key: String) -> String {
        key.split(separator: ":", maxSplits: 1).first.map(String.init) ?? key
    }

    private static func milliseconds(of duration: Duration) -> Double {
        let parts = duration.components
        return Double(parts.seconds) * 1000 + Double(parts.attoseconds) / 1e15
    }

    /// Apps whose keys and text are never written to the log, because what is
    /// typed there is secret.
    private static let unloggedTextApps = ["bitwarden", "1password", "keychainaccess", "LocalAuthentication"]

    /// Whether what is typed in the current field may be written to the log:
    /// not in password fields, with secure input on, or in password managers.
    private func mayLogTypedText(secureInput: Bool = false) -> Bool {
        if secureInput || focusedField?.subrole == "AXSecureTextField" {
            return false
        }
        let id = currentApplication?.bundleIdentifier.lowercased() ?? ""
        return !Self.unloggedTextApps.contains { id.contains($0.lowercased()) }
    }

    private func keyLogFields(
        _ key: SlashCommandKey,
        shifted: Bool,
        category: ShiftKeyCategory?,
        detail: KeyDetail?
    ) -> [String: JSONValue] {
        var fields: [String: JSONValue] = [
            "key": .string(String(describing: key)),
            "shifted": .bool(shifted),
            "category": .optional(category?.rawValue),
        ]
        if let lastCapsMono {
            let since = UsageEvent.currentMonotonicMilliseconds() - lastCapsMono
            if since < 2000 {
                fields["sinceCapsMs"] = .double(since)
            }
        }
        if let detail {
            fields["keyCode"] = .int(detail.keyCode)
            fields["mods"] = .strings(detail.modifiers)
            if mayLogTypedText(secureInput: detail.isSecureInput) {
                fields["chars"] = .string(detail.characters)
            } else {
                fields["redacted"] = true
            }
        }
        return fields
    }

    // MARK: - Text of the focused field

    /// Writes what is in the focused field after typing stops, and when Return
    /// is pressed, before the application sends it. This is what the input
    /// method finally typed, which the keys alone do not tell for Chinese.
    private func noteTypingForFieldText(_ key: SlashCommandKey) {
        guard usageLoggingEnabled else { return }
        fieldTextTask?.cancel()
        if key == .returnKey {
            logFieldText(reason: "return")
        }
        fieldTextTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            self?.logFieldText(reason: "idle")
        }
    }

    private func logFieldText(reason: String) {
        guard usageLoggingEnabled, let app = currentApplication, mayLogTypedText() else { return }
        var details = focusedFieldProvider.currentFieldDetails(includeValue: true)
        guard details["secure"] != true, case let .string(text)? = details["value"] else { return }
        let identity = "\(app.bundleIdentifier)|\(details["identifier"] ?? .null)|\(details["windowTitle"] ?? .null)"
        guard (identity, text) != lastLoggedFieldText ?? ("", "") else { return }
        lastLoggedFieldText = (identity, text)
        details["reason"] = .string(reason)
        logUsage("fieldText", details)
    }

    private static func jsonValue(of field: FieldSignature?) -> JSONValue {
        guard let field else { return .null }
        return .object([
            "role": .string(field.role),
            "subrole": .optional(field.subrole),
            "identifier": .optional(field.identifier),
            "descriptor": .optional(field.descriptor),
            "ancestors": .strings(field.ancestorRoles),
            "web": .bool(field.isInWebArea),
        ])
    }

    private static func jsonValue(of context: TerminalContext?) -> JSONValue {
        guard let context else { return .null }
        var object: [String: JSONValue] = ["tty": .string(context.tty), "candidates": .strings(context.candidates)]
        if let title = context.remoteTitle {
            object["title"] = .string(title)
        }
        return .object(object)
    }

    private static func environmentFields() -> [String: JSONValue] {
        let info = Bundle.main.infoDictionary
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var model = [CChar](repeating: 0, count: max(size, 1))
        sysctlbyname("hw.model", &model, &size, nil, 0)
        return [
            "version": .optional(info?["CFBundleShortVersionString"] as? String),
            "build": .optional(info?["CFBundleVersion"] as? String),
            "macOS": .string(ProcessInfo.processInfo.operatingSystemVersionString),
            "hardware": .string(String(cString: model)),
            "locale": .string(Locale.current.identifier),
            "languages": .strings(Locale.preferredLanguages),
            "timeZone": .string(TimeZone.current.identifier),
        ]
    }

    /// Picker entries for a settings choice, keeping a saved choice that is no
    /// longer installed visible.
    private func settingChoices(for selection: String) -> [InputSourceChoice] {
        var choices = inputSources.map { InputSourceChoice(id: $0.id, name: $0.name) }
        if
            selection != Self.automaticInputSourceID,
            !choices.contains(where: { $0.id == selection })
        {
            choices.append(InputSourceChoice(id: selection, name: "不可用：" + selection))
        }
        return choices
    }
}

private func + (lhs: [String: JSONValue], rhs: [String: JSONValue]) -> [String: JSONValue] {
    lhs.merging(rhs) { _, new in new }
}
