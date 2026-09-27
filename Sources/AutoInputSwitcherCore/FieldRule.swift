import Foundation

/// What identifies a text field inside an application, read from its
/// accessibility attributes. Only structural attributes are kept; the text the
/// user typed is never part of a signature.
public struct FieldSignature: Codable, Hashable, Sendable {
    /// AXRole, for example AXTextField.
    public var role: String
    /// AXSubrole, for example AXSearchField.
    public var subrole: String?
    /// AXIdentifier, or the id attribute of a field on a web page.
    public var identifier: String?
    /// The first non-empty of AXDescription, AXPlaceholderValue and AXTitle.
    public var descriptor: String?
    /// Roles of the nearest ancestors, starting with the parent.
    public var ancestorRoles: [String]
    /// True when the field is part of a web page (it has an AXWebArea ancestor).
    public var isInWebArea: Bool

    public init(
        role: String,
        subrole: String? = nil,
        identifier: String? = nil,
        descriptor: String? = nil,
        ancestorRoles: [String] = [],
        isInWebArea: Bool = false
    ) {
        self.role = role
        self.subrole = Self.nonEmpty(subrole)
        self.identifier = Self.nonEmpty(identifier)
        self.descriptor = Self.nonEmpty(descriptor)
        self.ancestorRoles = ancestorRoles
        self.isInWebArea = isInWebArea
    }

    /// Whether a saved signature describes the focused field. A field with an
    /// identifier is recognised by it alone, because its position in the window
    /// may change; otherwise every structural attribute has to agree.
    public func matches(_ field: FieldSignature) -> Bool {
        guard role == field.role, isInWebArea == field.isInWebArea else {
            return false
        }

        if let identifier {
            return identifier == field.identifier
        }

        return field.identifier == nil
            && subrole == field.subrole
            && descriptor == field.descriptor
            && ancestorRoles == field.ancestorRoles
    }

    /// A readable name for a field, used until the user renames the rule.
    public var suggestedLabel: String {
        if let descriptor {
            return descriptor
        }
        if subrole == "AXSearchField" {
            return "搜索框"
        }
        switch role {
        case "AXTextArea":
            return "多行输入框"
        case "AXComboBox":
            return "组合框"
        default:
            return "输入框"
        }
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}

/// Input source rule for one text field of an application.
public struct FieldRule: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var bundleIdentifier: String
    public var applicationName: String
    /// Shown to the user, for example “搜索框”.
    public var label: String
    public var signature: FieldSignature
    public var inputSourceID: String
    public var inputSourceName: String

    public init(
        id: UUID = UUID(),
        bundleIdentifier: String,
        applicationName: String,
        label: String,
        signature: FieldSignature,
        inputSourceID: String,
        inputSourceName: String
    ) {
        self.id = id
        self.bundleIdentifier = bundleIdentifier
        self.applicationName = applicationName
        self.label = label
        self.signature = signature
        self.inputSourceID = inputSourceID
        self.inputSourceName = inputSourceName
    }
}

/// In-memory collection of field rules. The first matching rule wins, and each
/// field of an application has at most one rule.
public struct FieldRuleSet: Equatable, Sendable {
    public private(set) var rules: [FieldRule]

    public init(rules: [FieldRule] = []) {
        self.rules = rules
    }

    /// Builds a rule set from persisted rules, dropping invalid entries and
    /// repeated identifiers or fields.
    public init(normalizing rules: [FieldRule]) {
        var result = FieldRuleSet()
        for rule in rules
        where RuleSet.isValidIdentifier(rule.bundleIdentifier)
            && RuleSet.isValidIdentifier(rule.inputSourceID)
            && !rule.signature.role.isEmpty
            && !result.rules.contains(where: { $0.id == rule.id })
            && result.rule(forBundleIdentifier: rule.bundleIdentifier, signature: rule.signature) == nil
        {
            result.rules.append(rule)
        }
        self = result
    }

    public func hasRules(forBundleIdentifier bundleIdentifier: String) -> Bool {
        rules.contains { $0.bundleIdentifier == bundleIdentifier }
    }

    /// The rule whose saved field matches the focused field.
    public func rule(forBundleIdentifier bundleIdentifier: String, matching field: FieldSignature) -> FieldRule? {
        rules.first { $0.bundleIdentifier == bundleIdentifier && $0.signature.matches(field) }
    }

    /// The rule saved for exactly this field.
    public func rule(forBundleIdentifier bundleIdentifier: String, signature: FieldSignature) -> FieldRule? {
        rules.first { $0.bundleIdentifier == bundleIdentifier && $0.signature == signature }
    }

    public func rule(id: UUID) -> FieldRule? {
        rules.first { $0.id == id }
    }

    public mutating func upsert(_ rule: FieldRule) {
        if let index = rules.firstIndex(where: { $0.id == rule.id }) {
            rules[index] = rule
        } else {
            rules.append(rule)
        }
    }

    @discardableResult
    public mutating func remove(id: UUID) -> FieldRule? {
        guard let index = rules.firstIndex(where: { $0.id == id }) else {
            return nil
        }
        return rules.remove(at: index)
    }
}

/// Recognises the address bar of the common browsers, so it can switch to an
/// input source of its own without the user capturing it first.
public enum AddressBarDetector {
    static let safariBundleIdentifiers: Set<String> = [
        "com.apple.Safari",
        "com.apple.SafariTechnologyPreview",
    ]

    static let chromiumBundleIdentifiers: Set<String> = [
        "com.google.Chrome",
        "com.google.Chrome.beta",
        "com.google.Chrome.dev",
        "com.google.Chrome.canary",
        "org.chromium.Chromium",
        "com.microsoft.edgemac",
        "com.brave.Browser",
        "com.vivaldi.Vivaldi",
        "com.operasoftware.Opera",
    ]

    static let firefoxBundleIdentifiers: Set<String> = [
        "org.mozilla.firefox",
        "org.mozilla.firefoxdeveloperedition",
        "org.mozilla.nightly",
    ]

    static let safariAddressBarIdentifier = "WEB_BROWSER_ADDRESS_AND_SEARCH_FIELD"
    static let firefoxAddressBarIdentifier = "urlbar-input"

    /// AXDescription of the Chromium omnibox in the languages the app is used in.
    static let chromiumAddressBarDescriptors: Set<String> = [
        "Address and search bar",
        "地址和搜索栏",
        "網址與搜尋列",
    ]

    public static func isBrowser(bundleIdentifier: String) -> Bool {
        safariBundleIdentifiers.contains(bundleIdentifier)
            || chromiumBundleIdentifiers.contains(bundleIdentifier)
            || firefoxBundleIdentifiers.contains(bundleIdentifier)
    }

    public static func isAddressBar(bundleIdentifier: String, field: FieldSignature) -> Bool {
        if safariBundleIdentifiers.contains(bundleIdentifier) {
            return field.identifier == safariAddressBarIdentifier
        }
        if firefoxBundleIdentifiers.contains(bundleIdentifier) {
            return field.identifier == firefoxAddressBarIdentifier
        }
        if chromiumBundleIdentifiers.contains(bundleIdentifier) {
            return !field.isInWebArea
                && (field.role == "AXTextField" || field.role == "AXComboBox")
                && field.descriptor.map(chromiumAddressBarDescriptors.contains) == true
        }
        return false
    }
}
