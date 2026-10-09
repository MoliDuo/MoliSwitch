import AppKit
import ApplicationServices
import Foundation
import MoliSwitchCore

/// Follows keyboard focus in the frontmost application with an AXObserver.
@MainActor
final class SystemFocusedFieldProvider: FocusedFieldProviding {
    /// Focused elements with these roles are text fields; focus on anything else
    /// is reported as no field.
    private static let textRoles: Set<String> = ["AXTextField", "AXTextArea", "AXComboBox"]
    /// Ancestors kept in a signature, starting with the parent.
    private static let ancestorDepth = 4
    /// How far up the tree to look for a web page around the field.
    private static let maximumAncestorWalk = 40
    /// A busy application must not block the main thread for long.
    private static let messagingTimeout: Float = 0.2

    private var observer: AXObserver?
    private var observedApplication: AXUIElement?
    private var observedProcessIdentifier: pid_t?
    private var handler: (@MainActor (FieldSignature?) -> Void)?

    var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    func requestTrust() {
        // The value of kAXTrustedCheckOptionPrompt, which Swift 6 does not allow
        // to be read because it is a global var.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    func startObserving(bundleIdentifier: String, handler: @escaping @MainActor (FieldSignature?) -> Void) {
        stopObserving()

        guard
            isTrusted,
            let application = NSWorkspace.shared.frontmostApplication,
            application.bundleIdentifier == bundleIdentifier
        else {
            return
        }

        let processIdentifier = application.processIdentifier
        let element = Self.applicationElement(processIdentifier)
        if !bundleIdentifier.hasPrefix("com.apple.") {
            // Chromium and Electron only build their accessibility tree for
            // assistive applications that ask for it.
            AXUIElementSetAttributeValue(element, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        }

        var created: AXObserver?
        guard AXObserverCreate(processIdentifier, focusCallback, &created) == .success, let created else {
            return
        }

        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for notification in [kAXFocusedUIElementChangedNotification, kAXFocusedWindowChangedNotification] {
            AXObserverAddNotification(created, element, notification as CFString, refcon)
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(created), .commonModes)

        observer = created
        observedApplication = element
        observedProcessIdentifier = processIdentifier
        self.handler = handler
    }

    func stopObserving() {
        if let observer {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        }
        observer = nil
        observedApplication = nil
        observedProcessIdentifier = nil
        handler = nil
    }

    func currentField() -> FieldSignature? {
        guard let focused = focusedElement() else {
            return nil
        }
        return Self.signature(of: focused)
    }

    func isCaretAtStart() -> Bool? {
        guard
            let focused = focusedElement(),
            let role = Self.string(focused, kAXRoleAttribute),
            Self.textRoles.contains(role)
        else {
            return nil
        }

        if
            let value = Self.copyAttribute(focused, kAXSelectedTextRangeAttribute),
            CFGetTypeID(value) == AXValueGetTypeID()
        {
            var range = CFRange()
            if AXValueGetValue(unsafeDowncast(value, to: AXValue.self), .cfRange, &range) {
                return range.location == 0
            }
        }
        if let count = Self.copyAttribute(focused, kAXNumberOfCharactersAttribute) as? Int {
            return count == 0
        }
        return nil
    }

    func currentFieldDetails(includeValue: Bool) -> [String: JSONValue] {
        guard let focused = focusedElement() else { return [:] }
        return Self.details(of: focused, includeValue: includeValue)
    }

    private func focusedElement() -> AXUIElement? {
        guard isTrusted, let application = NSWorkspace.shared.frontmostApplication else {
            return nil
        }

        let element: AXUIElement = if let observedApplication,
                                      observedProcessIdentifier == application.processIdentifier
        {
            observedApplication
        } else {
            Self.applicationElement(application.processIdentifier)
        }
        return Self.element(element, kAXFocusedUIElementAttribute)
    }

    fileprivate func focusDidChange() {
        guard let handler else { return }
        handler(currentField())
    }

    // MARK: - Reading attributes

    private static func applicationElement(_ processIdentifier: pid_t) -> AXUIElement {
        let element = AXUIElementCreateApplication(processIdentifier)
        AXUIElementSetMessagingTimeout(element, messagingTimeout)
        return element
    }

    static func signature(of element: AXUIElement) -> FieldSignature? {
        guard let role = string(element, kAXRoleAttribute), textRoles.contains(role) else {
            return nil
        }

        var ancestorRoles: [String] = []
        var isInWebArea = false
        var current = element
        for _ in 0..<maximumAncestorWalk {
            guard
                let parent = self.element(current, kAXParentAttribute),
                let parentRole = string(parent, kAXRoleAttribute),
                parentRole != kAXApplicationRole
            else {
                break
            }
            if ancestorRoles.count < ancestorDepth {
                ancestorRoles.append(parentRole)
            }
            if parentRole == "AXWebArea" {
                isInWebArea = true
                break
            }
            current = parent
        }

        return FieldSignature(
            role: role,
            subrole: string(element, kAXSubroleAttribute),
            identifier: string(element, kAXIdentifierAttribute) ?? string(element, "AXDOMIdentifier"),
            descriptor: [kAXDescriptionAttribute, kAXPlaceholderValueAttribute, kAXTitleAttribute]
                .lazy
                .compactMap { string(element, $0) }
                .first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty },
            ancestorRoles: ancestorRoles,
            isInWebArea: isInWebArea
        )
    }

    /// How much of the text in a field is kept, from the end, where typing is.
    private static let maximumValueLength = 2000

    // One flat list of attribute reads, each with its own check.
    // swiftlint:disable:next cyclomatic_complexity
    static func details(of element: AXUIElement, includeValue: Bool) -> [String: JSONValue] {
        var details: [String: JSONValue] = [:]
        let strings: [(String, String)] = [
            ("role", kAXRoleAttribute), ("subrole", kAXSubroleAttribute),
            ("roleDescription", kAXRoleDescriptionAttribute), ("title", kAXTitleAttribute),
            ("description", kAXDescriptionAttribute), ("placeholder", kAXPlaceholderValueAttribute),
            ("help", kAXHelpAttribute), ("identifier", kAXIdentifierAttribute),
            ("domId", "AXDOMIdentifier"),
        ]
        for (name, attribute) in strings {
            if let value = string(element, attribute), !value.isEmpty {
                details[name] = .string(value)
            }
        }
        if let classes = copyAttribute(element, "AXDOMClassList") as? [String], !classes.isEmpty {
            details["domClasses"] = .strings(classes)
        }

        if let window = self.element(element, kAXWindowAttribute) {
            if let title = string(window, kAXTitleAttribute), !title.isEmpty {
                details["windowTitle"] = .string(title)
            }
            if let document = string(window, kAXDocumentAttribute), !document.isEmpty {
                details["windowDocument"] = .string(document)
            }
        }

        // The page address, from the web area around a field in a browser.
        var current = element
        for _ in 0..<maximumAncestorWalk {
            guard let parent = self.element(current, kAXParentAttribute) else { break }
            if string(parent, kAXRoleAttribute) == "AXWebArea" {
                if let url = copyAttribute(parent, "AXURL") {
                    details["url"] = .string((url as? URL)?.absoluteString ?? String(describing: url))
                }
                if let title = string(parent, kAXTitleAttribute), !title.isEmpty {
                    details["pageTitle"] = .string(title)
                }
                break
            }
            current = parent
        }

        if let count = copyAttribute(element, kAXNumberOfCharactersAttribute) as? Int {
            details["length"] = .int(count)
        }
        if
            let value = copyAttribute(element, kAXSelectedTextRangeAttribute),
            CFGetTypeID(value) == AXValueGetTypeID()
        {
            var range = CFRange()
            if AXValueGetValue(unsafeDowncast(value, to: AXValue.self), .cfRange, &range) {
                details["caret"] = .int(range.location)
                details["selection"] = .int(range.length)
            }
        }

        let isSecure = string(element, kAXSubroleAttribute) == "AXSecureTextField"
        details["secure"] = .bool(isSecure)
        if includeValue, !isSecure, let text = copyAttribute(element, kAXValueAttribute) as? String {
            if text.count > maximumValueLength {
                details["value"] = .string(String(text.suffix(maximumValueLength)))
                details["valueTruncated"] = true
            } else {
                details["value"] = .string(text)
            }
        }
        return details
    }

    private static func copyAttribute(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        return value
    }

    private static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        copyAttribute(element, attribute) as? String
    }

    private static func element(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        guard let value = copyAttribute(element, attribute), CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return nil
        }
        return unsafeDowncast(value, to: AXUIElement.self)
    }
}

/// The observer's run loop source is on the main run loop, so the callback runs
/// on the main thread.
private let focusCallback: AXObserverCallback = { _, _, _, refcon in
    // The address is passed as an integer, which may cross into the main actor.
    guard let address = refcon.map(UInt.init(bitPattern:)) else { return }
    MainActor.assumeIsolated {
        guard let pointer = UnsafeMutableRawPointer(bitPattern: address) else { return }
        Unmanaged<SystemFocusedFieldProvider>.fromOpaque(pointer).takeUnretainedValue().focusDidChange()
    }
}
