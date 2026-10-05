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
///
/// Keys are chosen one by one, by their key codes in `ShiftKey`; a category
/// counts as chosen when all of its keys are.
public struct ShiftEnglishOptions: Codable, Equatable, Sendable {
    public var keyCodes: Set<Int>
    public var restoresOnRelease: Bool

    public init(keyCodes: Set<Int>, restoresOnRelease: Bool) {
        self.keyCodes = keyCodes
        self.restoresOnRelease = restoresOnRelease
    }

    /// Every key of the categories.
    public init(categories: Set<ShiftKeyCategory>, restoresOnRelease: Bool) {
        self.init(keyCodes: Self.keyCodes(of: categories), restoresOnRelease: restoresOnRelease)
    }

    /// Every key switches, and letting go switches back.
    public static let all = ShiftEnglishOptions(categories: Set(ShiftKeyCategory.allCases), restoresOnRelease: true)
    /// No key switches.
    public static let off = ShiftEnglishOptions(keyCodes: [], restoresOnRelease: true)

    public var switchesNothing: Bool {
        keyCodes.isEmpty
    }

    /// The categories all of whose keys switch; setting it chooses exactly
    /// the keys of those categories.
    public var categories: Set<ShiftKeyCategory> {
        get { Set(ShiftKeyCategory.allCases.filter { state(of: $0) == .all }) }
        set { keyCodes = Self.keyCodes(of: newValue) }
    }

    public enum CategoryState: Equatable, Sendable {
        case all, some, none
    }

    public func state(of category: ShiftKeyCategory) -> CategoryState {
        let keys = ShiftKey.keyCodes(in: category)
        let chosen = keys.intersection(keyCodes).count
        return chosen == 0 ? .none : chosen == keys.count ? .all : .some
    }

    /// Chooses or clears every key of the category.
    public mutating func set(_ category: ShiftKeyCategory, on: Bool) {
        let keys = ShiftKey.keyCodes(in: category)
        if on { keyCodes.formUnion(keys) } else { keyCodes.subtract(keys) }
    }

    public mutating func set(keyCode: Int, on: Bool) {
        let code = ShiftKey.key(forKeyCode: keyCode)?.keyCode ?? keyCode
        if on { keyCodes.insert(code) } else { keyCodes.remove(code) }
    }

    /// Whether Shift with the key switches. Keys outside `ShiftKey`, like the
    /// extra keys of ISO and JIS keyboards, follow their category.
    public func switches(keyCode: Int?, category: ShiftKeyCategory) -> Bool {
        if let keyCode, let key = ShiftKey.key(forKeyCode: keyCode) {
            return keyCodes.contains(key.keyCode)
        }
        return state(of: category) == .all
    }

    private static func keyCodes(of categories: Set<ShiftKeyCategory>) -> Set<Int> {
        categories.reduce(into: Set<Int>()) { $0.formUnion(ShiftKey.keyCodes(in: $1)) }
    }

    private enum CodingKeys: String, CodingKey {
        case keyCodes
        case categories
        case restoresOnRelease
    }

    /// Reads settings saved before keys were chosen one by one from their
    /// categories.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let keyCodes = try container.decodeIfPresent([Int].self, forKey: .keyCodes) {
            self.keyCodes = Set(keyCodes)
        } else {
            keyCodes = Self.keyCodes(of: try container.decode(Set<ShiftKeyCategory>.self, forKey: .categories))
        }
        restoresOnRelease = try container.decode(Bool.self, forKey: .restoresOnRelease)
    }

    /// Writes the keys in a fixed order, so the file does not change when the
    /// settings did not, and the whole categories for older versions.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(keyCodes.sorted(), forKey: .keyCodes)
        try container.encode(ShiftKeyCategory.allCases.filter(categories.contains), forKey: .categories)
        try container.encode(restoresOnRelease, forKey: .restoresOnRelease)
    }
}

/// How Shift works in one application, instead of the settings every other
/// application uses. No keys means Shift does not switch there.
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
