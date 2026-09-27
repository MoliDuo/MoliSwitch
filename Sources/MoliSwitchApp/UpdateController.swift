import AppKit
import Combine
import Sparkle

/// Thin wrapper around Sparkle's standard updater.
///
/// Sparkle already separates the two cases the app needs:
/// - a user initiated check (SPUUpdater.checkForUpdates) shows the standard
///   progress dialog, the "up to date" notice and any failure reason;
/// - the scheduled background check stays quiet about network errors and only
///   speaks up when a new version is available.
///
/// The wrapper adds the observable "can check" state that the menu item and the
/// main window need, plus a guard for bundles that were not packaged with a
/// usable update configuration. Development builds and partially configured
/// bundles therefore never start an updater that could only fail.
@MainActor
final class UpdateController: NSObject, ObservableObject {
    /// Mirrors SPUUpdater.canCheckForUpdates so the UI can disable the action
    /// while a check or an update session is already running.
    @Published private(set) var canCheckForUpdates = false

    private let hostBundle: Bundle
    private var canCheckForUpdatesObservation: NSKeyValueObservation?

    private lazy var updaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )

    init(hostBundle: Bundle = .main) {
        self.hostBundle = hostBundle
        super.init()
    }

    /// Builds a controller only when the packaged app carries both a feed URL
    /// and a public Ed25519 key.
    static func makeForHostBundle(_ hostBundle: Bundle = .main) -> UpdateController? {
        guard configuration(of: hostBundle) != nil else {
            return nil
        }

        return UpdateController(hostBundle: hostBundle)
    }

    static func configuration(of bundle: Bundle) -> (feedURL: URL, publicKey: String)? {
        guard
            let feedString = bundle.object(forInfoDictionaryKey: "SUFeedURL") as? String,
            let feedURL = URL(
                string: feedString.trimmingCharacters(in: .whitespacesAndNewlines)
            ),
            feedURL.scheme == "https" || feedURL.scheme == "http",
            let publicKey = bundle.object(forInfoDictionaryKey: "SUPublicEDKey") as? String,
            isUsablePublicKey(publicKey)
        else {
            return nil
        }

        return (
            feedURL,
            publicKey.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    /// A valid Ed25519 public key is exactly 32 bytes, which is 44 base64
    /// characters. Placeholders written by the packaging script must not count as
    /// configured.
    static func isUsablePublicKey(_ key: String) -> Bool {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty, !trimmed.hasPrefix("REPLACE") else {
            return false
        }

        return Data(base64Encoded: trimmed)?.count == 32
    }

    /// Starts the updater and begins observing whether a check is allowed.
    func start() {
        let updater = updaterController.updater
        canCheckForUpdates = updater.canCheckForUpdates

        // KVO delivers on the thread that changes the property. The updater is
        // main-thread only, so the work is simply moved to the main actor
        // instead of assuming isolation from a nonisolated callback.
        canCheckForUpdatesObservation = updater.observe(
            \.canCheckForUpdates,
            options: [.new]
        ) { [weak self] _, _ in
            Task { @MainActor [weak self] in
                self?.syncCanCheckForUpdates()
            }
        }
    }

    func stop() {
        canCheckForUpdatesObservation?.invalidate()
        canCheckForUpdatesObservation = nil
    }

    /// Message shown instead of starting a check, or nil when a check may run.
    var blockingReason: String? {
        if hostBundle.bundlePath.hasPrefix("/Volumes/") {
            return "MoliSwitch 正在只读磁盘映像中运行，请先把它拖到“应用程序”文件夹，然后再检查更新。"
        }

        return nil
    }

    /// Runs a user initiated check. Sparkle reports "already up to date" and any
    /// failure through its standard interface.
    func checkForUpdates() {
        if let reason = blockingReason {
            let alert = NSAlert()
            alert.messageText = "无法更新"
            alert.informativeText = reason
            alert.alertStyle = .warning
            alert.addButton(withTitle: "好")
            alert.runModal()
            return
        }

        updaterController.updater.checkForUpdates()
    }

    private func syncCanCheckForUpdates() {
        canCheckForUpdates = updaterController.updater.canCheckForUpdates
    }
}
