import AppKit
import MoliSwitchCore
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuDelegate, NSMenuItemValidation {
    private static let appName = AppInfo.name
    private static let windowFrameName = "MainWindow"
    /// Launches this soon after boot with launch at login turned on are treated
    /// as login item launches when the system did not mark them as such.
    private static let loginLaunchUptimeLimit: TimeInterval = 180

    private let defaults: UserDefaults
    private let ruleStore: JSONRuleStore
    private let coordinator: SingleInstanceCoordinator

    private var runtime: AppRuntime?
    private var window: NSWindow?
    private var statusItem: NSStatusItem?
    private var menuBarIconObservation: AnyCancellable?
    private var launchedAsLoginItem = false

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

    func applicationWillFinishLaunching(_ notification: Notification) {
        // The launch event is only available until launching finishes.
        launchedAsLoginItem = Self.launchEventIsLoginItem()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        guard claimSingleInstance() else {
            NSApp.terminate(nil)
            return
        }

        LegacyMigration.forCurrentUser(defaults: defaults).migrateIfNeeded()
        defaults.register(defaults: [AppRuntime.showMenuBarIconKey: true])

        // The runtime and the updater are created only by the process that holds
        // the single instance lock, so a second launch never installs a second
        // set of observers.
        let usageLogger = JSONLUsageLogger()
        let runtime = AppRuntime(
            store: ruleStore,
            commandStore: JSONCommandRuleStore(
                url: ruleStore.url.deletingLastPathComponent().appendingPathComponent("command-rules.json")
            ),
            fieldStore: JSONFieldRuleStore(
                url: ruleStore.url.deletingLastPathComponent().appendingPathComponent("field-rules.json")
            ),
            usageLogger: usageLogger,
            inputMethodProbe: InputMethodProbe(logger: usageLogger),
            defaults: defaults,
            updateController: UpdateController.makeForHostBundle()
        )
        self.runtime = runtime

        NSApp.mainMenu = makeMainMenu()
        setupStatusItem()
        menuBarIconObservation = runtime.$showMenuBarIcon
            .removeDuplicates()
            .sink { [weak self] isVisible in
                self?.statusItem?.isVisible = isVisible
            }

        runtime.start()

        coordinator.startRespondingToShowRequests { [weak self] in
            self?.showWindow()
        }

        // Opening the app shows its window. Only a launch at login stays in the
        // menu bar, unless a rule file could not be read: that has to be visible.
        let isLoginLaunch = launchedAsLoginItem
            || (runtime.isLaunchAtLoginEnabled
                && ProcessInfo.processInfo.systemUptime < Self.loginLaunchUptimeLimit)
        if !isLoginLaunch || runtime.hasStorageFailure {
            showWindow()
        }

        DispatchQueue.main.async { [weak self] in
            self?.offerToQuitLegacyApp()
        }
    }

    /// AutoInputSwitcher is the previous name of this app. Both running at the
    /// same time would switch input sources twice.
    private func offerToQuitLegacyApp() {
        let running = NSRunningApplication.runningApplications(
            withBundleIdentifier: LegacyMigration.legacyBundleIdentifier
        )
        guard !running.isEmpty else {
            return
        }

        let alert = NSAlert()
        alert.messageText = "AutoInputSwitcher 仍在运行"
        alert.informativeText = Self.appName + " 是 AutoInputSwitcher 的新版本，已经导入了原来的设置。"
            + "两个同时运行会重复切换输入法。\n\n"
            + "退出旧版后，请在 系统设置 › 通用 › 登录项 中移除 AutoInputSwitcher，并删除旧的应用。"
        alert.addButton(withTitle: "退出旧版")
        alert.addButton(withTitle: "稍后")
        NSApp.activate(ignoringOtherApps: true)

        if alert.runModal() == .alertFirstButtonReturn {
            running.forEach { $0.terminate() }
        }
    }

    private static func launchEventIsLoginItem() -> Bool {
        guard
            let event = NSAppleEventManager.shared().currentAppleEvent,
            event.eventID == AEEventID(kAEOpenApplication)
        else {
            return false
        }

        return event.paramDescriptor(forKeyword: AEKeyword(keyAEPropData))?.enumCodeValue
            == OSType(keyAELaunchedAsLogInItem)
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
        alert.messageText = "无法启动 " + Self.appName
        alert.informativeText = reason
        alert.alertStyle = .critical
        alert.addButton(withTitle: "退出")
        alert.runModal()
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

    func showWindow() {
        if window == nil {
            guard let runtime else {
                return
            }

            let controller = NSHostingController(rootView: MainWindowView(runtime: runtime))
            controller.sceneBridgingOptions = [.toolbars, .title]
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 1040, height: 620),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.contentViewController = controller
            window.title = Self.appName
            window.toolbarStyle = .unified
            window.contentMinSize = NSSize(width: 900, height: 520)
            window.setContentSize(NSSize(width: 1040, height: 620))
            if !window.setFrameUsingName(Self.windowFrameName) {
                window.center()
            } else if window.contentLayoutRect.width < window.contentMinSize.width {
                // A frame saved before the settings column beside the table.
                window.setContentSize(NSSize(width: 1040, height: max(window.contentLayoutRect.height, 620)))
            }
            window.setFrameAutosaveName(Self.windowFrameName)
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
    }

    // MARK: - Main menu

    /// An accessory app shows no menu bar, but its main menu still handles the
    /// standard key equivalents such as ⌘W, ⌘Q and ⌘V in text fields.
    private func makeMainMenu() -> NSMenu {
        let mainMenu = NSMenu()

        let appMenu = NSMenu(title: Self.appName)
        appMenu.addItem(makeMenuItem(title: "关于 " + Self.appName, action: #selector(showAboutPanel)))
        appMenu.addItem(.separator())
        appMenu.addItem(makeMenuItem(title: "设置…", action: #selector(showWindowFromMenu), keyEquivalent: ","))
        appMenu.addItem(.separator())
        appMenu.addItem(
            NSMenuItem(title: "隐藏 " + Self.appName, action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        )
        appMenu.addItem(.separator())
        appMenu.addItem(
            NSMenuItem(title: "退出 " + Self.appName, action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        )
        addSubmenu(appMenu, to: mainMenu)

        let editMenu = NSMenu(title: "编辑")
        editMenu.addItem(NSMenuItem(title: "撤销", action: Selector(("undo:")), keyEquivalent: "z"))
        let redo = NSMenuItem(title: "重做", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(redo)
        editMenu.addItem(.separator())
        editMenu.addItem(NSMenuItem(title: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: "拷贝", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        addSubmenu(editMenu, to: mainMenu)

        let windowMenu = NSMenu(title: "窗口")
        windowMenu.addItem(NSMenuItem(title: "关闭", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
        windowMenu.addItem(
            NSMenuItem(title: "最小化", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        )
        addSubmenu(windowMenu, to: mainMenu)
        NSApp.windowsMenu = windowMenu

        return mainMenu
    }

    private func addSubmenu(_ submenu: NSMenu, to menu: NSMenu) {
        let item = NSMenuItem(title: submenu.title, action: nil, keyEquivalent: "")
        item.submenu = submenu
        menu.addItem(item)
    }

    // MARK: - Status item

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = BrandMark.menuBarImage()
        item.button?.toolTip = Self.appName

        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        item.isVisible = runtime?.showMenuBarIcon ?? true
        statusItem = item
    }

    /// The status menu is rebuilt each time it opens, so the remember item
    /// describes the field that has focus right now.
    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === statusItem?.menu else {
            return
        }

        menu.removeAllItems()
        menu.addItem(makeRememberFieldItem())
        menu.addItem(.separator())
        menu.addItem(makeMenuItem(title: "打开 " + Self.appName + "…", action: #selector(showWindowFromMenu), keyEquivalent: ","))
        menu.addItem(makeMenuItem(title: "检查更新…", action: #selector(checkForUpdatesFromMenu)))
        menu.addItem(.separator())
        menu.addItem(makeMenuItem(title: "关于 " + Self.appName, action: #selector(showAboutPanel)))
        menu.addItem(makeMenuItem(title: "退出 " + Self.appName, action: #selector(terminateApp), keyEquivalent: "q"))
    }

    /// Opening a status item menu does not activate the app, so the field the
    /// user was typing in still has keyboard focus.
    private func makeRememberFieldItem() -> NSMenuItem {
        switch runtime?.fieldCaptureState() ?? .noField {
        case .ready(let applicationName, let inputSourceName):
            return makeMenuItem(
                title: "记住当前输入框（" + applicationName + " · " + inputSourceName + "）",
                action: #selector(rememberFocusedField)
            )
        case .needsAccessibility:
            return makeMenuItem(
                title: "记住当前输入框（需要辅助功能权限）…",
                action: #selector(requestAccessibilityFromMenu)
            )
        case .noField:
            // No action, so the item is shown disabled.
            return NSMenuItem(title: "记住当前输入框", action: nil, keyEquivalent: "")
        }
    }

    /// Menu item targets are always set explicitly so the actions never depend on
    /// the responder chain.
    private func makeMenuItem(
        title: String,
        action: Selector,
        keyEquivalent: String = ""
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

    @objc private func showWindowFromMenu() {
        showWindow()
    }

    @objc private func rememberFocusedField() {
        runtime?.rememberFocusedField()
    }

    @objc private func requestAccessibilityFromMenu() {
        runtime?.requestAccessibilityTrust()
    }

    @objc private func checkForUpdatesFromMenu() {
        runtime?.checkForUpdates()
    }

    @objc private func showAboutPanel() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(nil)
    }

    @objc private func terminateApp() {
        NSApp.terminate(nil)
    }
}
