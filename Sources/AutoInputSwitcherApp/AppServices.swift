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
    /// Bundle identifier of the process that provides the input source.
    func bundleIdentifier(forSourceID id: String) -> String?
}

/// Whether any process is using the default audio input device. Only the usage
/// flag is read, nothing is recorded.
@MainActor
protocol MicrophoneActivityMonitoring: AnyObject {
    var isRunning: Bool { get }
    /// The handler receives changes of the running state.
    func start(_ handler: @escaping @MainActor (Bool) -> Void)
    func stop()
}

/// Detects the floating overlay a voice input method shows while it records and
/// recognises speech.
@MainActor
protocol VoiceOverlayDetecting: AnyObject {
    /// Records the windows that already exist, so they are not taken for the overlay.
    func captureBaseline(bundleIdentifier: String?)
    /// Reports visibility changes until stop() is called.
    func start(bundleIdentifier: String?, handler: @escaping @MainActor (Bool) -> Void)
    func stop()
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
