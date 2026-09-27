import AppKit
import AutoInputSwitcherCore
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuItemValidation {
    private enum DefaultsKey {
        /// Set once the first run window has actually been shown, so later cold
        /// launches stay in the menu bar.
        static let hasCompletedInitialSetup = "hasCompletedInitialSetup"
    }

    private let defaults: UserDefaults
    private let ruleStore: JSONRuleStore
    private let coordinator: SingleInstanceCoordinator

    private var runtime: AppRuntime?
    private var window: NSWindow?
    private var statusItem: NSStatusItem?
    private var menuBarIconObservation: AnyCancellable?
    private var isPresentingStatusMenu = false

    init(
        defaults: UserDefaults = .standard,
        ruleStore: JSONRuleStore = .applicationSupportStore()
    ) {
        self.defaults = defaults
        self.ruleStore = ruleStore
        self.coordinator = SingleInstanceCoordinator(
            lock: SingleInstanceLock(
                url: ruleStore.url
                    .deletingLastPathComponent()
                    .appendingPathComponent("instance.lock")
            )
        )
        super.init()
    }

    // MARK: - Launch

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        defaults.register(defaults: [AppRuntime.showMenuBarIconKey: true])

        guard claimSingleInstance() else {
            NSApp.terminate(nil)
            return
        }

        // The runtime and the updater are created only by the process that holds
        // the single instance lock, so a second launch never installs a second
        // set of observers.
        let runtime = AppRuntime(
            store: ruleStore,
            commandStore: JSONCommandRuleStore(
                url: ruleStore.url.deletingLastPathComponent().appendingPathComponent("command-rules.json")
            ),
            defaults: defaults,
            updateController: UpdateController.makeForHostBundle()
        )
        self.runtime = runtime

        menuBarIconObservation = runtime.$showMenuBarIcon
            .removeDuplicates()
            .sink { [weak self] isVisible in
                self?.statusItem?.isVisible = isVisible
            }

        setupMenuBar()
        runtime.start()

        coordinator.startRespondingToShowRequests { [weak self] in
            self?.showWindow()
        }

        // A rule file that could not be read has to be visible: the user cannot
        // fix it from the menu bar without opening the window.
        if runtime.hasStorageFailure || shouldShowWindowOnFirstLaunch() {
            showWindow()
        }
    }

    private func claimSingleInstance() -> Bool {
        do {
            if try coordinator.acquireExclusiveInstance() {
                return true
            }
        } catch {
            presentLaunchFailure(String(describing: error))
            return false
        }

        // Another instance already holds the lock. Ask it to show its window and
        // then exit even when the request could not be delivered: continuing here
        // would create a second runtime with a second set of listeners.
        coordinator.requestShowFromExistingInstance()
        return false
    }

    private func presentLaunchFailure(_ reason: String) {
        let alert = NSAlert()
        alert.messageText = "无法启动 AutoInputSwitcher"
        alert.informativeText = reason
        alert.alertStyle = .critical
        alert.addButton(withTitle: "退出")
        alert.runModal()
    }

    private func shouldShowWindowOnFirstLaunch() -> Bool {
        if defaults.bool(forKey: DefaultsKey.hasCompletedInitialSetup) {
            return false
        }

        // Migration: a user who already has a rule file has used the app before
        // the flag existed and must not see the first run window again.
        if ruleStore.fileExists {
            defaults.set(true, forKey: DefaultsKey.hasCompletedInitialSetup)
            return false
        }

        return true
    }

    // MARK: - Windows

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        showWindow()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        menuBarIconObservation = nil
        runtime?.stop()
        coordinator.releaseLock()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        true
    }

    func showWindow() {
        if window == nil {
            guard let runtime else {
                return
            }

            let contentView = MainWindowView(runtime: runtime) {
                NSApp.terminate(nil)
            }
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 760, height: 600),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "AutoInputSwitcher"
            window.contentView = NSHostingView(rootView: contentView)
            window.center()
            window.delegate = self
            window.isReleasedWhenClosed = false
            self.window = window
        }

        guard let window else {
            return
        }

        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        // Only a window that really appeared marks the first run as done.
        defaults.set(true, forKey: DefaultsKey.hasCompletedInitialSetup)
    }

    // MARK: - Menu bar

    private func setupMenuBar() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let button = item.button
        button?.image = NSImage(
            systemSymbolName: "keyboard",
            accessibilityDescription: "AutoInputSwitcher"
        )
        button?.toolTip = "AutoInputSwitcher"
        button?.target = self
        button?.action = #selector(statusItemClicked(_:))
        // A menu is attached only while the right button is handled, so the left
        // click keeps toggling the window instead of opening a menu.
        button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        item.isVisible = runtime?.showMenuBarIcon ?? true
        statusItem = item
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            presentStatusMenu()
        } else {
            toggleWindow()
        }
    }

    private func presentStatusMenu() {
        guard let statusItem, !isPresentingStatusMenu else {
            return
        }

        isPresentingStatusMenu = true
        defer {
            statusItem.menu = nil
            isPresentingStatusMenu = false
        }

        statusItem.menu = makeStatusMenu()
        statusItem.button?.performClick(nil)
    }

    private func makeStatusMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(
            makeMenuItem(
                title: "显示主窗口",
                action: #selector(showWindowFromMenu),
                keyEquivalent: ""
            )
        )
        menu.addItem(.separator())
        menu.addItem(
            makeMenuItem(
                title: "检查更新…",
                action: #selector(checkForUpdatesFromMenu),
                keyEquivalent: ""
            )
        )
        menu.addItem(.separator())
        menu.addItem(
            makeMenuItem(
                title: "关于 AutoInputSwitcher",
                action: #selector(showAboutPanel),
                keyEquivalent: ""
            )
        )
        menu.addItem(.separator())
        menu.addItem(
            makeMenuItem(
                title: "退出 AutoInputSwitcher",
                action: #selector(terminateApp),
                keyEquivalent: "q"
            )
        )
        return menu
    }

    /// Menu item targets are always set explicitly so the actions never depend on
    /// the responder chain.
    private func makeMenuItem(
        title: String,
        action: Selector,
        keyEquivalent: String
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = self
        return item
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(checkForUpdatesFromMenu) {
            return runtime?.canCheckForUpdates ?? false
        }

        return true
    }

    @objc private func toggleWindow() {
        guard let window else {
            showWindow()
            return
        }

        if window.isVisible && window.isKeyWindow {
            window.orderOut(nil)
        } else {
            showWindow()
        }
    }

    @objc private func showWindowFromMenu() {
        showWindow()
    }

    @objc private func checkForUpdatesFromMenu() {
        runtime?.checkForUpdates()
    }

    @objc private func showAboutPanel() {
        NSApp.orderFrontStandardAboutPanel(nil)
    }

    @objc private func terminateApp() {
        NSApp.terminate(nil)
    }
}
