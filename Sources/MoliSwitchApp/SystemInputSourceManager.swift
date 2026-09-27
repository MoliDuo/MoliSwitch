import Carbon
import Foundation

@MainActor
final class SystemInputSourceManager: NSObject, InputSourceManaging {
    /// Same value as kTISNotifyEnabledKeyboardInputSourcesChanged. The literal is
    /// used so the behaviour does not depend on a Carbon constant being visible.
    private static let enabledInputSourcesChanged = Notification.Name(
        "AppleEnabledInputSourcesChangedNotification"
    )

    /// Same value as kTISNotifySelectedKeyboardInputSourceChanged.
    private static let selectedInputSourceChanged = Notification.Name(
        "com.apple.Carbon.TISNotifySelectedKeyboardInputSourceChanged"
    )

    /// Safety net for changes that never arrive as a distributed notification.
    private static let cacheLifetime: TimeInterval = 3

    private var cachedInputSources: [InputSource]?
    private var cacheDate: Date?
    private var changeHandler: (@MainActor () -> Void)?
    private var selectionHandler: (@MainActor () -> Void)?
    private var selectionObserver: NSObjectProtocol?

    func availableInputSources() -> [InputSource] {
        if
            let cached = cachedInputSources,
            let cacheDate,
            Date().timeIntervalSince(cacheDate) < Self.cacheLifetime
        {
            return cached
        }

        let sources = computeAvailableInputSources()
        cachedInputSources = sources
        cacheDate = Date()
        return sources
    }

    func invalidateCache() {
        cachedInputSources = nil
        cacheDate = nil
    }

    func startMonitoringEnabledSources(_ handler: @escaping @MainActor () -> Void) {
        changeHandler = handler

        guard observers.isEmpty else { return }

        let center = DistributedNotificationCenter.default()
        // The block form returns an observer token; the selector form returns
        // Void and would leave no way to unregister. Delivery is pinned to the
        // main queue so the main-actor handler never runs off the main thread.
        observers.append(
            center.addObserver(
                forName: Self.enabledInputSourcesChanged,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.handleEnabledInputSourcesChanged()
                }
            }
        )
    }

    func stopMonitoringEnabledSources() {
        changeHandler = nil
        let center = DistributedNotificationCenter.default()
        for observer in observers {
            center.removeObserver(observer)
        }
        observers.removeAll()
    }

    func startMonitoringSelectedSource(_ handler: @escaping @MainActor () -> Void) {
        selectionHandler = handler

        guard selectionObserver == nil else { return }

        selectionObserver = DistributedNotificationCenter.default().addObserver(
            forName: Self.selectedInputSourceChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.selectionHandler?()
            }
        }
    }

    func stopMonitoringSelectedSource() {
        selectionHandler = nil
        if let selectionObserver {
            DistributedNotificationCenter.default().removeObserver(selectionObserver)
            self.selectionObserver = nil
        }
    }

    private func handleEnabledInputSourcesChanged() {
        invalidateCache()
        changeHandler?()
    }

    func currentInputSource() -> InputSource? {
        let source = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
        guard
            let id = stringProperty(source, kTISPropertyInputSourceID),
            let name = stringProperty(source, kTISPropertyLocalizedName)
        else {
            return nil
        }

        return InputSource(id: id, name: name)
    }

    func selectInputSource(id: String) -> Bool {
        guard let source = inputSource(matching: id) else {
            return false
        }

        guard TISSelectInputSource(source) == noErr else {
            return false
        }

        // Some input methods accept the call without becoming current, for
        // example while they are being disabled. On this machine the switch to
        // third-party input methods (豆包) took effect for the frontmost text
        // field as well, so no retry is attempted; a mismatch is reported.
        return currentInputSource()?.id == id
    }

    private func computeAvailableInputSources() -> [InputSource] {
        let filters: [String: Any] = [
            kTISPropertyInputSourceCategory as String: kTISCategoryKeyboardInputSource as String,
            kTISPropertyInputSourceIsSelectCapable as String: true
        ]

        let list = TISCreateInputSourceList(filters as CFDictionary, false).takeRetainedValue()
        return (list as NSArray)
            .map { $0 as! TISInputSource }
            .compactMap { source in
                guard
                    let id = stringProperty(source, kTISPropertyInputSourceID),
                    let name = stringProperty(source, kTISPropertyLocalizedName)
                else {
                    return nil
                }

                return InputSource(id: id, name: name)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func inputSource(matching id: String) -> TISInputSource? {
        let filters: [String: Any] = [
            kTISPropertyInputSourceID as String: id
        ]
        let list = TISCreateInputSourceList(filters as CFDictionary, false).takeRetainedValue()
        return (list as NSArray).map { $0 as! TISInputSource }.first
    }

    private func stringProperty(_ source: TISInputSource, _ key: CFString) -> String? {
        guard let rawValue = TISGetInputSourceProperty(source, key) else {
            return nil
        }

        return Unmanaged<CFString>
            .fromOpaque(rawValue)
            .takeUnretainedValue() as String
    }

    private var observers: [NSObjectProtocol] = []
}
