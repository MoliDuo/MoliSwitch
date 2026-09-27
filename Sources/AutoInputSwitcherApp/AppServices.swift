import AutoInputSwitcherCore
import Foundation

/// Keyboard input sources. Main-actor isolated because the underlying Carbon
/// APIs are only safe to call from the main thread.
@MainActor
protocol InputSourceManaging: AnyObject {
    func availableInputSources() -> [InputSource]
    func invalidateCache()
    func currentInputSource() -> InputSource?
    func selectInputSource(id: String) -> Bool
    func startMonitoringEnabledSources(_ handler: @escaping @MainActor () -> Void)
    func stopMonitoringEnabledSources()
    /// Called whenever the selected input source changes, whoever changed it.
    func startMonitoringSelectedSource(_ handler: @escaping @MainActor () -> Void)
    func stopMonitoringSelectedSource()
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
}

/// Reads the text field that has keyboard focus in the frontmost application,
/// through the Accessibility API. Only structural attributes are read, never
/// the text in the field.
@MainActor
protocol FocusedFieldProviding: AnyObject {
    /// Whether the user allowed AutoInputSwitcher to use Accessibility.
    var isTrusted: Bool { get }
    /// Shows the system prompt that leads to the Accessibility settings.
    func requestTrust()
    /// Reports the focused field of the frontmost application, which has to be
    /// the one named, whenever focus moves, until stopObserving() is called.
    func startObserving(bundleIdentifier: String, handler: @escaping @MainActor (FieldSignature?) -> Void)
    func stopObserving()
    /// The focused text field of the frontmost application, if any.
    func currentField() -> FieldSignature?
}
