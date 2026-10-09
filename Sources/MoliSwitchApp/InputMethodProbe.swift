import AppKit
import ApplicationServices
import Carbon
import CoreGraphics
import Darwin
import MoliSwitchCore

/// Writes everything the system tells about input methods at one moment to the
/// usage log: what Text Input Sources reports, the input method processes, the
/// windows on screen above normal windows (candidate windows among them), the
/// focused element with the text around its caret, the HIToolbox preferences
/// and the modifier state.
///
/// This exists for the bug where an input method is selected but the
/// frontmost application still types plain letters. TIS says all is well then,
/// so the log needs what else could tell the two cases apart.
///
/// The Text Input Sources part is read on the main thread, where TIS has to be
/// called. Everything that may be slow, above all Accessibility calls into the
/// frontmost application, runs on a serial background queue, so the key path is
/// never blocked by it.
final class InputMethodProbe: @unchecked Sendable { // swiftlint:disable:this type_body_length
    struct Parts: OptionSet, Sendable {
        let rawValue: Int
        static let windows = Parts(rawValue: 1 << 0)
        static let processes = Parts(rawValue: 1 << 1)
        static let field = Parts(rawValue: 1 << 2)
        static let preferences = Parts(rawValue: 1 << 3)
        static let all: Parts = [.windows, .processes, .field, .preferences]
    }

    private let logger: any UsageLogging
    private let queue = DispatchQueue(label: "MoliSwitch.InputMethodProbe", qos: .utility)

    // Only touched on `queue`.
    private var processCache: (date: Date, list: [ProcessEntry])?
    private var lastProcessSignature: String?
    private var lastAttributeSignature: String?

    private var notificationObservers: [NSObjectProtocol] = []

    init(logger: any UsageLogging) {
        self.logger = logger
    }

    /// Logs `name` with `fields`, the TIS state at that moment and the parts
    /// asked for. With a delay, the whole reading happens that much later.
    @MainActor
    func record(_ name: String, _ fields: [String: JSONValue], parts: Parts, afterMs: Int = 0, mayLogText: Bool) {
        guard logger.isEnabled else { return }
        guard afterMs <= 0 else {
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(afterMs)) { [weak self] in
                MainActor.assumeIsolated {
                    self?.record(name, fields, parts: parts, mayLogText: mayLogText)
                }
            }
            return
        }

        let time = Date()
        let mono = UsageEvent.currentMonotonicMilliseconds()
        var fields = fields
        fields["tis"] = .object(Self.systemState())
        let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        guard !parts.isEmpty else {
            logger.log(UsageEvent(name, fields, time: time, mono: mono))
            return
        }
        let mainFields = fields
        queue.async { [self] in
            var fields = mainFields
            let start = UsageEvent.currentMonotonicMilliseconds()
            if parts.contains(.processes) || parts.contains(.windows) {
                fields["imeProcesses"] = .strings(imeProcesses().map(\.description))
            }
            if parts.contains(.windows) {
                fields["windows"] = windows(frontmostPID: frontmostPID)
            }
            if parts.contains(.field) {
                fields["ax"] = .object(focusedElement(mayLogText: mayLogText))
            }
            if parts.contains(.preferences) {
                fields["prefs"] = .object(Self.preferences())
            }
            fields["probeMs"] = .double(UsageEvent.currentMonotonicMilliseconds() - start)
            fields["probeLagMs"] = .double(start - mono)
            logger.log(UsageEvent(name, fields, time: time, mono: mono))
        }
    }

    /// Logs every distributed notification about input sources and keyboards.
    @MainActor
    func startObservingNotifications() {
        guard notificationObservers.isEmpty else { return }
        let names = [
            "com.apple.Carbon.TISNotifySelectedKeyboardInputSourceChanged",
            "com.apple.Carbon.TISNotifyEnabledKeyboardInputSourcesChanged",
            "AppleSelectedInputSourcesChangedNotification",
            "AppleEnabledInputSourcesChangedNotification",
            "AppleKeyboardPreferencesChangedNotification",
            "com.apple.HIToolbox.TISNotifyInputSourceStateChanged",
            "com.apple.inputmethod.SCIM.TISNotify",
            "com.apple.TextInputMenuAgent.selectionChanged",
            "com.apple.TextInputSwitcher.didShow",
            "AppleInterfaceThemeChangedNotification",
            "com.apple.accessibility.api",
            "com.apple.screenIsLocked",
            "com.apple.screenIsUnlocked",
        ]
        let center = DistributedNotificationCenter.default()
        for name in names {
            notificationObservers.append(
                center.addObserver(forName: Notification.Name(name), object: nil, queue: .main) { [weak self] note in
                    let object = note.object.map { String(describing: $0) }
                    let info = note.userInfo.map { String(describing: $0) }
                    let noteName = note.name.rawValue
                    MainActor.assumeIsolated {
                        self?.record(
                            "distributedNotification",
                            ["name": .string(noteName), "object": .optional(object), "userInfo": .optional(info)],
                            parts: [],
                            mayLogText: false
                        )
                    }
                }
            )
        }
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [
            NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification,
            NSWorkspace.didWakeNotification, NSWorkspace.willSleepNotification,
            NSWorkspace.sessionDidBecomeActiveNotification, NSWorkspace.sessionDidResignActiveNotification,
            NSWorkspace.screensDidWakeNotification, NSWorkspace.screensDidSleepNotification,
        ] {
            notificationObservers.append(
                workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                    let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                    let bundle = app?.bundleIdentifier
                    let pid = app.map { Int($0.processIdentifier) }
                    let noteName = note.name.rawValue
                    MainActor.assumeIsolated {
                        self?.record(
                            "workspaceNotification",
                            [
                                "name": .string(noteName),
                                "bundle": .optional(bundle),
                                "pid": pid.map(JSONValue.int) ?? .null,
                            ],
                            parts: [.processes],
                            mayLogText: false
                        )
                    }
                }
            )
        }
    }

    // MARK: - Text Input Sources, on the main thread

    @MainActor
    static func systemState() -> [String: JSONValue] {
        var state: [String: JSONValue] = [:]
        state["current"] = .optional(id(of: TISCopyCurrentKeyboardInputSource()?.takeRetainedValue()))
        state["layout"] = .optional(id(of: TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue()))
        state["asciiCapable"] = .optional(id(of: TISCopyCurrentASCIICapableKeyboardInputSource()?.takeRetainedValue()))
        state["asciiLayout"] = .optional(
            id(of: TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue())
        )
        state["layoutOverride"] = .optional(id(of: TISCopyInputMethodKeyboardLayoutOverride()?.takeRetainedValue()))

        let filter = [kTISPropertyInputSourceIsSelected as String: true] as CFDictionary
        if let list = TISCreateInputSourceList(filter, false)?.takeRetainedValue() as? [TISInputSource] {
            state["selected"] = .strings(list.compactMap { id(of: $0) })
        }

        let combined = CGEventSource.flagsState(.combinedSessionState)
        let hid = CGEventSource.flagsState(.hidSystemState)
        state["flags"] = .strings(flagNames(combined))
        if hid != combined {
            state["hidFlags"] = .strings(flagNames(hid))
        }
        state["secureInput"] = .bool(IsSecureEventInputEnabled())
        state["keyboardType"] = .int(Int(LMGetKbdType()))

        let workspace = NSWorkspace.shared
        if let front = workspace.frontmostApplication {
            state["front"] = .string("\(front.bundleIdentifier ?? "?")#\(front.processIdentifier)")
        }
        if let owner = workspace.menuBarOwningApplication {
            state["menuBarOwner"] = .string("\(owner.bundleIdentifier ?? "?")#\(owner.processIdentifier)")
        }
        return state
    }

    private static func id(of source: TISInputSource?) -> String? {
        guard let source, let raw = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { return nil }
        return Unmanaged<CFString>.fromOpaque(raw).takeUnretainedValue() as String
    }

    static func flagNames(_ flags: CGEventFlags) -> [String] {
        [
            (CGEventFlags.maskAlphaShift, "caps"), (.maskShift, "shift"), (.maskControl, "ctrl"),
            (.maskAlternate, "alt"), (.maskCommand, "cmd"), (.maskSecondaryFn, "fn"), (.maskNumericPad, "numpad"),
            (.maskHelp, "help"), (.maskNonCoalesced, "nonCoalesced"),
        ]
        .filter { flags.contains($0.0) }
        .map(\.1)
    }

    // MARK: - Input method processes

    struct ProcessEntry: Sendable {
        let pid: Int32
        let path: String
        let started: Int

        var description: String {
            "\((path as NSString).lastPathComponent)#\(pid)@\(started)"
        }
    }

    private static let imeProcessMarkers = [
        "/Input Methods/", "TextInput", "imklaunchagent", "CursorUIViewService", "SCIM", "TCIM",
        "InputMethod", "PressAndHold", "CharacterPalette", "TextInputSwitcher", "KeyboardSetupAssistant",
        "inputmethod", "universalaccessd", "talagent",
    ]

    /// Read at most every two seconds; a change is logged on its own.
    private func imeProcesses() -> [ProcessEntry] {
        if let processCache, Date().timeIntervalSince(processCache.date) < 2 {
            return processCache.list
        }
        let list = Self.listIMEProcesses()
        processCache = (Date(), list)
        let signature = list.map(\.description).joined(separator: ",")
        if let lastProcessSignature, lastProcessSignature != signature {
            logger.log(
                UsageEvent(
                    "imeProcessesChanged",
                    ["before": .string(lastProcessSignature), "after": .string(signature)]
                )
            )
        }
        lastProcessSignature = signature
        return list
    }

    private static func listIMEProcesses() -> [ProcessEntry] {
        let capacity = Int(proc_listallpids(nil, 0)) + 64
        guard capacity > 64 else { return [] }
        var pids = [pid_t](repeating: 0, count: capacity)
        let count = Int(proc_listallpids(&pids, Int32(capacity * MemoryLayout<pid_t>.size)))
        var result: [ProcessEntry] = []
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        for pid in pids.prefix(max(0, count)) where pid > 0 {
            let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
            guard length > 0 else { continue }
            let path = String(decoding: buffer.prefix(Int(length)).map { UInt8(bitPattern: $0) }, as: UTF8.self)
            guard imeProcessMarkers.contains(where: { path.contains($0) }) else { continue }
            var info = proc_bsdinfo()
            let size = Int32(MemoryLayout<proc_bsdinfo>.size)
            let started = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size ? Int(info.pbi_start_tvsec) : 0
            result.append(ProcessEntry(pid: pid, path: path, started: started))
        }
        return result.sorted { $0.pid < $1.pid }
    }

    // MARK: - Windows

    /// The windows above normal ones, except the menu bar and its items, plus
    /// every window of the input method processes and of the frontmost app.
    /// Candidate windows are among the first, wherever they belong.
    private func windows(frontmostPID: pid_t?) -> JSONValue {
        guard
            let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]]
        else {
            return .null
        }
        let imePIDs = Set(imeProcesses().map(\.pid))
        var entries: [JSONValue] = []
        var imeWindows = 0
        var popups = 0
        for window in list {
            let layer = window[kCGWindowLayer as String] as? Int ?? 0
            let pid = (window[kCGWindowOwnerPID as String] as? Int).map(Int32.init) ?? 0
            let owner = window[kCGWindowOwnerName as String] as? String ?? "?"
            let isIME = imePIDs.contains(pid)
            let isFront = pid == frontmostPID
            let isPopup = layer > 0 && layer != 24 && layer != 25
            guard isIME || isFront || isPopup else { continue }
            if isIME {
                imeWindows += 1
            }
            if isPopup {
                popups += 1
            }
            let bounds = window[kCGWindowBounds as String] as? [String: Any] ?? [:]
            func number(_ key: String) -> Int {
                Int((bounds[key] as? Double) ?? Double(bounds[key] as? Int ?? 0))
            }
            let alpha = window[kCGWindowAlpha as String] as? Double ?? 1
            let name = window[kCGWindowName as String] as? String
            var text = "\(owner)#\(pid) L\(layer) \(number("Width"))x\(number("Height"))@\(number("X")),\(number("Y"))"
            if alpha < 1 {
                text += " a\(alpha)"
            }
            if let name, !name.isEmpty {
                text += " \"\(name)\""
            }
            if let id = window[kCGWindowNumber as String] as? Int {
                text += " n\(id)"
            }
            if isIME {
                text += " IME"
            }
            entries.append(.string(text))
        }
        return .object([
            "list": .array(entries),
            "onScreen": .int(list.count),
            "imeWindows": .int(imeWindows),
            "popups": .int(popups),
        ])
    }

    // MARK: - Focused element

    private static let markAttributeMarkers = ["Mark", "Composition", "Insertion", "Edit", "TextInput", "Input"]

    // A diagnostic read from top to bottom; easier to follow in one piece.
    // swiftlint:disable function_body_length cyclomatic_complexity
    /// The focused element of the whole system, with the caret, the text
    /// around it, and every attribute whose name may tell about marked text.
    private func focusedElement(mayLogText: Bool) -> [String: JSONValue] {
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.25)
        let start = UsageEvent.currentMonotonicMilliseconds()
        var details: [String: JSONValue] = [:]
        guard let element = Self.element(system, kAXFocusedUIElementAttribute) else {
            details["focused"] = false
            return details
        }
        AXUIElementSetMessagingTimeout(element, 0.25)
        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)
        details["pid"] = .int(Int(pid))
        for (name, attribute) in [("role", kAXRoleAttribute), ("subrole", kAXSubroleAttribute)] {
            if let value = Self.copy(element, attribute) as? String {
                details[name] = .string(value)
            }
        }
        if let count = Self.copy(element, kAXNumberOfCharactersAttribute) as? Int {
            details["length"] = .int(count)
        }
        var caret: CFRange?
        if let value = Self.copy(element, kAXSelectedTextRangeAttribute), CFGetTypeID(value) == AXValueGetTypeID() {
            var range = CFRange()
            if AXValueGetValue(unsafeDowncast(value, to: AXValue.self), .cfRange, &range) {
                caret = range
                details["caret"] = .int(range.location)
                details["selection"] = .int(range.length)
            }
        }
        if let value = Self.copy(element, "AXInsertionPointLineNumber") as? Int {
            details["line"] = .int(value)
        }

        var names: [CFArray?] = [nil, nil]
        AXUIElementCopyAttributeNames(element, &names[0])
        AXUIElementCopyParameterizedAttributeNames(element, &names[1])
        let attributes = (names[0] as? [String]) ?? []
        let parameterized = (names[1] as? [String]) ?? []
        let signature = "\(pid)|\(attributes.joined(separator: ","))|\(parameterized.joined(separator: ","))"
        if signature != lastAttributeSignature {
            details["attributes"] = .strings(attributes)
            details["parameterizedAttributes"] = .strings(parameterized)
            lastAttributeSignature = signature
        }

        let isSecure = details["subrole"] == "AXSecureTextField"
        let mayReadText = mayLogText && !isSecure
        var marked: [String: JSONValue] = [:]
        for name in attributes where Self.markAttributeMarkers.contains(where: { name.contains($0) }) {
            guard let value = Self.copy(element, name) else { continue }
            var text = Self.describe(value)
            if !mayReadText, CFGetTypeID(value) == CFStringGetTypeID() {
                text = "<\(text.count) chars>"
            }
            marked[name] = .string(String(text.prefix(300)))
        }
        if !marked.isEmpty {
            details["markAttributes"] = .object(marked)
        }

        if mayReadText, let caret {
            let location = max(0, caret.location - 40)
            var range = CFRange(location: location, length: caret.location - location + max(caret.length, 0) + 10)
            if case let .int(length)? = details["length"] {
                range.length = max(0, min(range.length, length - location))
            }
            if
                range.length > 0,
                let rangeValue = AXValueCreate(.cfRange, &range)
            {
                var text: CFTypeRef?
                if AXUIElementCopyParameterizedAttributeValue(
                    element, kAXStringForRangeParameterizedAttribute as CFString, rangeValue, &text
                ) == .success, let text = text as? String {
                    details["nearCaret"] = .string(text)
                    details["nearCaretFrom"] = .int(location)
                } else if let value = Self.copy(element, kAXValueAttribute) as? String {
                    let string = value as NSString
                    let clamped = NSIntersectionRange(
                        NSRange(location: range.location, length: range.length),
                        NSRange(location: 0, length: string.length)
                    )
                    details["nearCaret"] = .string(string.substring(with: clamped))
                    details["nearCaretFrom"] = .int(clamped.location)
                    details["nearCaretVia"] = "value"
                }
            }
            if caret.length > 0, let selected = Self.copy(element, kAXSelectedTextAttribute) as? String {
                details["selectedText"] = .string(String(selected.prefix(200)))
            }
        }
        details["axMs"] = .double(UsageEvent.currentMonotonicMilliseconds() - start)
        return details
    }

    // swiftlint:enable function_body_length cyclomatic_complexity

    private static func copy(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value
    }

    private static func element(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        guard let value = copy(element, attribute), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return unsafeDowncast(value, to: AXUIElement.self)
    }

    private static func describe(_ value: CFTypeRef) -> String {
        if CFGetTypeID(value) == AXValueGetTypeID() {
            let axValue = unsafeDowncast(value, to: AXValue.self)
            var range = CFRange()
            if AXValueGetType(axValue) == .cfRange, AXValueGetValue(axValue, .cfRange, &range) {
                return "range(\(range.location),\(range.length))"
            }
        }
        if CFGetTypeID(value) == AXUIElementGetTypeID() {
            let element = unsafeDowncast(value, to: AXUIElement.self)
            return "element(\(copy(element, kAXRoleAttribute) as? String ?? "?"))"
        }
        return String(describing: value)
    }

    // MARK: - HIToolbox preferences

    private static func preferences() -> [String: JSONValue] {
        let domain = "com.apple.HIToolbox" as CFString
        CFPreferencesAppSynchronize(domain)
        var result: [String: JSONValue] = [:]
        func ids(_ key: String) -> JSONValue {
            guard let list = CFPreferencesCopyAppValue(key as CFString, domain) as? [[String: Any]]
            else { return .null }
            return .strings(list.map { entry in
                (entry["Input Mode"] as? String)
                    ?? (entry["Bundle ID"] as? String)
                    ?? (entry["KeyboardLayout Name"] as? String).map { "layout:" + $0 }
                    ?? String(describing: entry)
            })
        }
        result["history"] = ids("AppleInputSourceHistory")
        result["selected"] = ids("AppleSelectedInputSources")
        for key in [
            "AppleCurrentKeyboardLayoutInputSourceID", "AppleGlobalTextInputProperties",
            "AppleCapsLockPressAndHoldToggleOff", "TSMLanguageIndicatorEnabled",
        ] {
            if let value = CFPreferencesCopyAppValue(key as CFString, domain) {
                result[key] = .string(String(describing: value))
            }
        }
        return result
    }
}
