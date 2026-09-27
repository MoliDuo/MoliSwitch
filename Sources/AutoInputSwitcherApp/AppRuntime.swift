import AppKit
import AutoInputSwitcherCore
import Foundation

@MainActor
final class AppRuntime: ObservableObject {
    static let showMenuBarIconKey = "showMenuBarIcon"
    static let chineseInputSourceIDKey = "chineseInputSourceID"
    static let englishInputSourceIDKey = "englishInputSourceID"
    static let terminalSwitchingEnabledKey = "terminalSwitchingEnabled"
    static let defaultInputSourceIDKey = "defaultInputSourceID"
    static let addressBarSwitchingEnabledKey = "addressBarSwitchingEnabled"
    static let addressBarInputSourceIDKey = "addressBarInputSourceID"
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
    /// Whether AutoInputSwitcher may use Accessibility to see the focused field.
    @Published private(set) var accessibilityTrusted = false
    /// The program most recently seen in the foreground of a terminal tab.
    @Published private(set) var lastTerminalContext: TerminalContext?
    /// True when the user did not allow reading the terminal's active tab.
    @Published private(set) var terminalAccessDenied = false
    @Published private(set) var switchCount = 0
    @Published private(set) var launchAtLoginStatus: LaunchAtLoginStatus = .notRegistered
    @Published private(set) var isScanning = false
    @Published private(set) var ruleEditingEnabled = true
    @Published private(set) var iconCacheGeneration = 0

    @Published private(set) var storageStatus: StatusMessage?
    @Published private(set) var scanStatus: StatusMessage?
    @Published private(set) var inputSourceStatus: StatusMessage?
    @Published private(set) var loginStatus: StatusMessage?

    @Published var searchText = ""
    @Published var applicationListScope: ApplicationListScope = .all
    @Published var showMenuBarIcon: Bool {
        didSet {
            guard showMenuBarIcon != oldValue else { return }
            defaults.set(showMenuBarIcon, forKey: Self.showMenuBarIconKey)
        }
    }
    /// Whether command rules apply in Terminal and iTerm2.
    @Published var terminalSwitchingEnabled: Bool {
        didSet {
            guard terminalSwitchingEnabled != oldValue else { return }
            defaults.set(terminalSwitchingEnabled, forKey: Self.terminalSwitchingEnabledKey)
            updateTerminalPolling(for: currentApplication)
        }
    }
    /// The chosen Chinese input source, or automaticInputSourceID.
    @Published var chineseInputSourceSelection: String {
        didSet {
            guard chineseInputSourceSelection != oldValue else { return }
            let previous = resolveInputSource(oldValue) { detectedChineseInputSource }
            persistSelection(chineseInputSourceSelection, forKey: Self.chineseInputSourceIDKey)
            adoptRole(Self.chineseRuleID, forRulesUsing: previous)
        }
    }
    /// The chosen English input source, or automaticInputSourceID.
    @Published var englishInputSourceSelection: String {
        didSet {
            guard englishInputSourceSelection != oldValue else { return }
            let previous = resolveInputSource(oldValue) { detectedEnglishInputSource }
            persistSelection(englishInputSourceSelection, forKey: Self.englishInputSourceIDKey)
            adoptRole(Self.englishRuleID, forRulesUsing: previous)
        }
    }
    /// Whether the address bar of a browser switches to its own input source.
    @Published var addressBarSwitchingEnabled: Bool {
        didSet {
            guard addressBarSwitchingEnabled != oldValue else { return }
            defaults.set(addressBarSwitchingEnabled, forKey: Self.addressBarSwitchingEnabledKey)
            refreshFieldObservation()
        }
    }
    /// The input source of browser address bars: a role or an input source.
    @Published var addressBarInputSourceSelection: String {
        didSet {
            guard addressBarInputSourceSelection != oldValue else { return }
            defaults.set(addressBarInputSourceSelection, forKey: Self.addressBarInputSourceIDKey)
            refreshFieldObservation()
        }
    }
    /// What applications without a rule switch to: noSwitchInputSourceID, a
    /// role, or an input source.
    @Published var defaultInputSourceSelection: String {
        didSet {
            guard defaultInputSourceSelection != oldValue else { return }
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
    private let focusedFieldProvider: any FocusedFieldProviding
    private let terminalContextProvider: any TerminalContextProviding
    private let terminalPollInterval: TimeInterval
    private let inputSourceManager: any InputSourceManaging
    private let applicationScanner: any ApplicationScanning
    private let loginItemManager: any LoginItemManaging
    private let switchCounter: SwitchCounter
    private let defaults: UserDefaults
    private let ownBundleIdentifier: String?
    let updateController: UpdateController?

    private var scanTask: Task<Void, Never>?
    private var activationObserver: NSObjectProtocol?
    private var hasStarted = false
    private var hasStopped = false

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

    init(
        store: any RuleStore = JSONRuleStore.applicationSupportStore(),
        commandStore: any CommandRuleStore = JSONCommandRuleStore.applicationSupportStore(),
        fieldStore: any FieldRuleStore = JSONFieldRuleStore.applicationSupportStore(),
        focusedFieldProvider: any FocusedFieldProviding = SystemFocusedFieldProvider(),
        terminalContextProvider: any TerminalContextProviding = SystemTerminalContextProvider(),
        terminalPollInterval: TimeInterval = 0.5,
        inputSourceManager: any InputSourceManaging = SystemInputSourceManager(),
        applicationScanner: any ApplicationScanning = InstalledApplicationScanner(),
        loginItemManager: any LoginItemManaging = SystemLoginItemManager(),
        switchCounter: SwitchCounter = SwitchCounter(),
        defaults: UserDefaults = .standard,
        updateController: UpdateController? = nil,
        ownBundleIdentifier: String? = Bundle.main.bundleIdentifier
    ) {
        self.store = store
        self.commandStore = commandStore
        self.fieldStore = fieldStore
        self.focusedFieldProvider = focusedFieldProvider
        self.terminalContextProvider = terminalContextProvider
        self.terminalPollInterval = terminalPollInterval
        self.inputSourceManager = inputSourceManager
        self.applicationScanner = applicationScanner
        self.loginItemManager = loginItemManager
        self.switchCounter = switchCounter
        self.defaults = defaults
        self.updateController = updateController
        self.ownBundleIdentifier = ownBundleIdentifier
        self.showMenuBarIcon = defaults.object(forKey: Self.showMenuBarIconKey) as? Bool ?? true
        self.terminalSwitchingEnabled = defaults.object(forKey: Self.terminalSwitchingEnabledKey) as? Bool ?? true
        self.chineseInputSourceSelection = defaults.string(forKey: Self.chineseInputSourceIDKey)
            ?? Self.automaticInputSourceID
        self.englishInputSourceSelection = defaults.string(forKey: Self.englishInputSourceIDKey)
            ?? Self.automaticInputSourceID
        self.defaultInputSourceSelection = defaults.string(forKey: Self.defaultInputSourceIDKey)
            ?? Self.noSwitchInputSourceID
        self.addressBarSwitchingEnabled = defaults.object(forKey: Self.addressBarSwitchingEnabledKey) as? Bool ?? true
        self.addressBarInputSourceSelection = defaults.string(forKey: Self.addressBarInputSourceIDKey)
            ?? Self.englishRuleID
        self.accessibilityTrusted = focusedFieldProvider.isTrusted
        self.switchCount = switchCounter.count
        self.launchAtLoginStatus = loginItemManager.status
    }

    // MARK: - Lifecycle

    func start() {
        guard !hasStarted else { return }
        hasStarted = true

        loadRulesAtStartup()
        refreshInputSources()
        reportLoginStatus()
        startMonitoring()
        updateController?.start()
        refreshApplications()
        updateCurrentApplication(from: NSWorkspace.shared.frontmostApplication)
    }

    func stop() {
        guard !hasStopped else { return }
        hasStopped = true

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
        inputSourceManager.stopMonitoringSelectedSource()
        updateController?.stop()
    }

    // MARK: - Rules

    /// True when the rule file exists but could not be read, so editing is paused
    /// and the original file is left untouched.
    var hasStorageFailure: Bool {
        !ruleEditingEnabled || !commandRuleEditingEnabled || !fieldRuleEditingEnabled
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
        do {
            let loaded = try store.load()
            ruleSet = RuleSet(normalizing: loaded)
            ruleEditingEnabled = true
            storageStatus = reportingSuccess ? .rulesReloaded : nil
        } catch {
            // Keep whatever is already in memory; never write back over a file we
            // could not read.
            ruleEditingEnabled = false
            storageStatus = .rulesReadFailure
            loadCommandRules()
            loadFieldRules()
            return
        }

        if !loadCommandRules() {
            storageStatus = .commandRulesReadFailure
        }
        if !loadFieldRules() {
            storageStatus = .fieldRulesReadFailure
        }
    }

    @discardableResult
    private func loadCommandRules() -> Bool {
        do {
            commandRuleSet = CommandRuleSet(normalizing: try commandStore.load())
            commandRuleEditingEnabled = true
            return true
        } catch {
            commandRuleEditingEnabled = false
            return false
        }
    }

    @discardableResult
    private func loadFieldRules() -> Bool {
        do {
            fieldRuleSet = FieldRuleSet(normalizing: try fieldStore.load())
            fieldRuleEditingEnabled = true
            return true
        } catch {
            fieldRuleEditingEnabled = false
            return false
        }
    }

    func revealRulesFileInFinder() {
        let url: URL
        if !ruleEditingEnabled {
            url = store.url
        } else if !commandRuleEditingEnabled {
            url = commandStore.url
        } else if !fieldRuleEditingEnabled {
            url = fieldStore.url
        } else {
            url = store.url
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
        where seenBundleIdentifiers.insert(application.bundleIdentifier).inserted {
            result.append(application)
        }

        for rule in ruleSet.rules
        where seenBundleIdentifiers.insert(rule.bundleIdentifier).inserted {
            let name = rule.applicationName.trimmingCharacters(in: .whitespacesAndNewlines)
            result.append(
                InstalledApplication(
                    name: name.isEmpty ? rule.bundleIdentifier : name,
                    bundleIdentifier: rule.bundleIdentifier,
                    url: nil
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

    var filteredInstalledApplications: [InstalledApplication] {
        let filter = ApplicationListFilter(
            query: searchText,
            scope: applicationListScope,
            configuredBundleIdentifiers: Set(ruleSet.rules.map(\.bundleIdentifier))
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
            self.finishScan(with: result)
        }
    }

    private func finishScan(with result: ApplicationScanResult) {
        scanTask = nil
        isScanning = false

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
        let hiddenIDs = Set([effectiveChineseInputSource?.id, effectiveEnglishInputSource?.id].compactMap { $0 })
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
        } catch {
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
            updateTerminalPolling(for: currentApplication)
            return true
        } catch {
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
            refreshFieldObservation()
            return true
        } catch {
            storageStatus = .rulesSaveFailure
            return false
        }
    }

    func openAutomationSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
            NSWorkspace.shared.open(url)
        }
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

    func setLaunchAtLoginEnabled(_ enabled: Bool) {
        do {
            if enabled {
                if loginItemManager.status == .requiresApproval {
                    // Never register again while the system is waiting for the
                    // user to allow the login item.
                    loginStatus = StatusMessage(
                        text: "开机自启正在等待系统批准，请在“系统设置 › 通用 › 登录项”中允许。",
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
                text: "开机自启设置失败：" + error.localizedDescription,
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
            loginStatus = StatusMessage(text: "已开启开机自启")
        case .notRegistered:
            loginStatus = StatusMessage(text: "已关闭开机自启")
        case .requiresApproval:
            loginStatus = StatusMessage(
                text: "开机自启正在等待系统批准，请在“系统设置 › 通用 › 登录项”中允许。",
                severity: .warning
            )
        case .notFound:
            loginStatus = StatusMessage(
                text: "系统未找到登录项注册信息，请尝试重新开启开机自启。",
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
            .compactMap { $0 }

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
        if case .found(let found)? = terminalContext(for: app) {
            context = found
        }
        terminalContextInEffect = context
        fieldRestore = nil
        followFields(of: app)

        apply(activeRule(for: app))
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
            currentInputSource = inputSourceManager.currentInputSource()
            inputSourceStatus = nil
            return
        }

        guard let targetID = targetInputSourceID(forRuleID: rule.inputSourceID) else {
            inputSourceStatus = StatusMessage(
                text: "还没有找到" + rule.inputSourceName + "输入法，请在设置里选择。",
                severity: .warning
            )
            currentInputSource = inputSourceManager.currentInputSource()
            return
        }

        if inputSourceManager.currentInputSource()?.id != targetID {
            // The count only tracks input sources that were actually switched.
            if inputSourceManager.selectInputSource(id: targetID) {
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
            inputSourceStatus = nil
        }

        currentInputSource = inputSourceManager.currentInputSource()
    }

    // MARK: - Focused fields

    /// Focus is only followed where a field rule could apply, so applications
    /// without one are never touched through Accessibility.
    private func followsFields(_ app: RunningApplicationInfo) -> Bool {
        accessibilityTrusted
            && (fieldRuleSet.hasRules(forBundleIdentifier: app.bundleIdentifier)
                || (addressBarSwitchingEnabled && AddressBarDetector.isBrowser(bundleIdentifier: app.bundleIdentifier)))
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
    }

    private func stopFollowingFields() {
        guard fieldApplication != nil else { return }
        focusedFieldProvider.stopObserving()
        fieldApplication = nil
        focusedField = nil
    }

    private func handleFocusedFieldChanged(_ field: FieldSignature?) {
        guard let app = fieldApplication, app == currentApplication, field != focusedField else { return }
        focusedField = field
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

        if addressBarSwitchingEnabled, AddressBarDetector.isAddressBar(bundleIdentifier: app.bundleIdentifier, field: field) {
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

        let result = terminalContextProvider.foregroundContext(bundleIdentifier: app.bundleIdentifier)
        switch result {
        case .found(let context):
            if terminalAccessDenied { terminalAccessDenied = false }
            if lastTerminalContext != context { lastTerminalContext = context }
        case .denied:
            if !terminalAccessDenied { terminalAccessDenied = true }
        case .unavailable:
            break
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
                self.pollTerminal()
            }
        }
    }

    private func stopTerminalPolling() {
        terminalPollTask?.cancel()
        terminalPollTask = nil
        polledApplication = nil
    }

    /// Switches when the program in the active tab, or the tab itself, changed.
    private func pollTerminal() {
        guard let app = polledApplication, let result = terminalContext(for: app) else {
            stopTerminalPolling()
            return
        }

        switch result {
        case .found(let found):
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
        currentInputSource = inputSourceManager.currentInputSource()
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
