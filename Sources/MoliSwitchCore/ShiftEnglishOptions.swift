import Foundation

/// Which key a character typed with Shift held comes from.
public enum ShiftKeyCategory: String, Codable, CaseIterable, Sendable {
    /// A to Z.
    case letter
    /// The number row and the keypad digits, which type ! @ # ( ) with Shift.
    case digit
    /// Every other key that types a character, like ? : " _ { }.
    case symbol
}

/// Which keys typed with Shift held switch to the English input source, and
/// whether letting go of Shift switches back.
public struct ShiftEnglishOptions: Codable, Equatable, Sendable {
    public var categories: Set<ShiftKeyCategory>
    public var restoresOnRelease: Bool

    public init(categories: Set<ShiftKeyCategory>, restoresOnRelease: Bool) {
        self.categories = categories
        self.restoresOnRelease = restoresOnRelease
    }

    /// Every key switches, and letting go switches back.
    public static let all = ShiftEnglishOptions(categories: Set(ShiftKeyCategory.allCases), restoresOnRelease: true)
    /// No key switches.
    public static let off = ShiftEnglishOptions(categories: [], restoresOnRelease: true)

    public var switchesNothing: Bool {
        categories.isEmpty
    }

    private enum CodingKeys: String, CodingKey {
        case categories
        case restoresOnRelease
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        categories = try container.decode(Set<ShiftKeyCategory>.self, forKey: .categories)
        restoresOnRelease = try container.decode(Bool.self, forKey: .restoresOnRelease)
    }

    /// Writes the categories in a fixed order, so the file does not change
    /// when the settings did not.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(ShiftKeyCategory.allCases.filter(categories.contains), forKey: .categories)
        try container.encode(restoresOnRelease, forKey: .restoresOnRelease)
    }
}

/// How Shift works in one application, instead of the settings every other
/// application uses. No categories means Shift does not switch there.
public struct ShiftAppRule: Codable, Equatable, Identifiable, Sendable {
    public var id: String { bundleIdentifier }

    public var bundleIdentifier: String
    public var applicationName: String
    public var options: ShiftEnglishOptions

    public init(bundleIdentifier: String, applicationName: String, options: ShiftEnglishOptions) {
        self.bundleIdentifier = bundleIdentifier
        self.applicationName = applicationName
        self.options = options
    }
}

/// The applications with their own Shift settings, each at most once, in the
/// order of their names.
public struct ShiftAppRuleList: Equatable, Sendable {
    public private(set) var rules: [ShiftAppRule]

    public init(rules: [ShiftAppRule] = []) {
        self.rules = []
        for rule in rules where self.rule(for: rule.bundleIdentifier) == nil {
            set(rule)
        }
    }

    /// Builds the list from persisted entries: invalid identifiers are dropped
    /// and the first entry seen for each application wins.
    public init(normalizing rules: [ShiftAppRule]) {
        self.init(rules: rules.filter { RuleSet.isValidIdentifier($0.bundleIdentifier) })
    }

    public func rule(for bundleIdentifier: String) -> ShiftAppRule? {
        rules.first { $0.bundleIdentifier == bundleIdentifier }
    }

    /// Adds the rule, or replaces the one of the same application.
    public mutating func set(_ rule: ShiftAppRule) {
        remove(bundleIdentifier: rule.bundleIdentifier)
        rules.append(rule)
        rules.sort { lhs, rhs in
            let comparison = lhs.applicationName.localizedCaseInsensitiveCompare(rhs.applicationName)
            if comparison == .orderedSame {
                return lhs.bundleIdentifier < rhs.bundleIdentifier
            }
            return comparison == .orderedAscending
        }
    }

    @discardableResult
    public mutating func remove(bundleIdentifier: String) -> ShiftAppRule? {
        guard let index = rules.firstIndex(where: { $0.bundleIdentifier == bundleIdentifier }) else {
            return nil
        }
        return rules.remove(at: index)
    }
}
