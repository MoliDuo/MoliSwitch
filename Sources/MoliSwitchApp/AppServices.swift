import MoliSwitchCore
import Foundation

/// Keyboard input sources. Main-actor isolated because the underlying Carbon
/// APIs are only safe to call from the main thread.
@MainActor
protocol InputSourceManaging: AnyObject {
    func availableInputSources() -> [InputSource]
    func invalidateCache()
    func currentInputSource() -> InputSource?
    /// What the system says about the current input source, for the usage log:
    /// its type, input mode, whether it types ASCII and its languages.
    func currentInputSourceDetails() -> [String: String]
    func selectInputSource(id: String) -> Bool
    /// Why the last selectInputSource(id:) failed, when it did.
    var lastSelectionFailure: String? { get }
    func startMonitoringEnabledSources(_ handler: @escaping @MainActor () -> Void)
    func stopMonitoringEnabledSources()
    /// Called whenever the selected input source changes, whoever changed it.
    func startMonitoringSelectedSource(_ handler: @escaping @MainActor () -> Void)
    func stopMonitoringSelectedSource()
}

extension InputSourceManaging {
    func currentInputSourceDetails() -> [String: String] { [:] }
    var lastSelectionFailure: String? { nil }
}

/// The system bubble that shows the input source next to the caret after it
/// changes. It is a setting for every application, not only MoliSwitch.
@MainActor
protocol InputSourceIndicatorControlling: AnyObject {
    var isEnabled: Bool { get }
    func setEnabled(_ enabled: Bool)
}

@MainActor
protocol LoginItemManaging: AnyObject {
    var status: LaunchAtLoginStatus { get }
    func register() throws
    func unregister() throws
    func openSystemSettingsLoginItems()
}

/// File system scan for installed applications. Runs off the main actor, so the
/// result type and conformers must be sendable.
protocol ApplicationScanning: Sendable {
    func scan() -> ApplicationScanResult
}

/// Finds the program running in the foreground of a terminal's active tab.
@MainActor
protocol TerminalContextProviding: AnyObject {
    func supportsTerminal(bundleIdentifier: String) -> Bool
    func foregroundContext(bundleIdentifier: String) -> TerminalContextResult
    /// The same, asked without holding up the main thread.
    func foregroundContextInBackground(bundleIdentifier: String) async -> TerminalContextResult
}

/// Reads the text field that has keyboard focus in the frontmost application,
/// through the Accessibility API. Only structural attributes are read, never
/// the text in the field.
@MainActor
protocol FocusedFieldProviding: AnyObject {
    /// Whether the user allowed MoliSwitch to use Accessibility.
    var isTrusted: Bool { get }
    /// Shows the system prompt that leads to the Accessibility settings.
    func requestTrust()
    /// Reports the focused field of the frontmost application, which has to be
    /// the one named, whenever focus moves, until stopObserving() is called.
    func startObserving(bundleIdentifier: String, handler: @escaping @MainActor (FieldSignature?) -> Void)
    func stopObserving()
    /// The focused text field of the frontmost application, if any.
    func currentField() -> FieldSignature?
    /// Whether the caret of the focused text field is at the start of its
    /// input, or nil when the application does not tell. Only the caret
    /// position and the length are read.
    func isCaretAtStart() -> Bool?
    /// Everything the focused element tells, for the usage log: its role,
    /// labels, web page ids, window title, URL, caret and, when asked, the text
    /// in it. Empty when there is nothing focused.
    func currentFieldDetails(includeValue: Bool) -> [String: JSONValue]
}

extension FocusedFieldProviding {
    func currentFieldDetails(includeValue: Bool) -> [String: JSONValue] {
        [:]
    }
}

/// Sees the keys typed in every application, and can hold one back until the
/// input source changed. Needs the Accessibility permission.
@MainActor
protocol KeyEventMonitoring: AnyObject {
    var isRunning: Bool { get }
    /// Calls the handler for every key pressed, in any application, and when
    /// Shift is let go. Returning true for a key holds it back, along with the
    /// keys pressed after it, until releaseHeldKeys() is called. Returns false
    /// when monitoring could not start, for example without the permission.
    @discardableResult
    func start(_ handler: @escaping @MainActor (MonitoredKeyEvent) -> Bool) -> Bool
    func stop()
    /// Types the keys held back, in the order they were pressed.
    func releaseHeldKeys()
}
