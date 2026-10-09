import Foundation

/// Input source rule for a program running in the foreground of a terminal tab,
/// such as claude or vim.
public struct CommandRule: Codable, Equatable, Identifiable, Sendable {
    public var id: String {
        CommandRuleSet.matchKey(command)
    }

    public var command: String
    public var inputSourceID: String
    public var inputSourceName: String

    public init(command: String, inputSourceID: String, inputSourceName: String) {
        self.command = command
        self.inputSourceID = inputSourceID
        self.inputSourceName = inputSourceName
    }
}

/// In-memory collection of command rules. Commands are compared without regard
/// to case, and each command has at most one rule.
public struct CommandRuleSet: Equatable, Sendable {
    public private(set) var rules: [CommandRule]

    public init(rules: [CommandRule] = []) {
        self.rules = rules
    }

    /// Builds a rule set from persisted rules: names are trimmed, invalid entries
    /// are dropped and the first rule seen for each command wins.
    public init(normalizing rules: [CommandRule]) {
        var seenKeys: Set<String> = []
        var normalized: [CommandRule] = []

        for rule in rules {
            var trimmed = rule
            trimmed.command = Self.normalizedCommand(rule.command)

            guard
                !trimmed.command.isEmpty,
                RuleSet.isValidIdentifier(trimmed.inputSourceID),
                seenKeys.insert(Self.matchKey(trimmed.command)).inserted
            else {
                continue
            }
            normalized.append(trimmed)
        }

        self.rules = normalized
    }

    /// The command name as it is stored: surrounding whitespace, a directory
    /// and the dash of a login shell are removed.
    public static func normalizedCommand(_ command: String) -> String {
        var name = command.trimmingCharacters(in: .whitespacesAndNewlines)
        if let slash = name.lastIndex(of: "/") {
            name = String(name[name.index(after: slash)...])
        }
        while name.hasPrefix("-") {
            name.removeFirst()
        }
        return name
    }

    public static func matchKey(_ command: String) -> String {
        normalizedCommand(command).lowercased()
    }

    public func rule(forCommand command: String) -> CommandRule? {
        let key = Self.matchKey(command)
        return rules.first { $0.id == key }
    }

    /// The rule for the first candidate that has one. Candidates are ordered
    /// from the most to the least specific name of the program.
    public func rule(matchingAnyOf candidates: [String]) -> CommandRule? {
        for candidate in candidates {
            if let rule = rule(forCommand: candidate) {
                return rule
            }
        }
        return nil
    }

    public mutating func upsert(_ rule: CommandRule) {
        var normalized = rule
        normalized.command = Self.normalizedCommand(rule.command)

        if let index = rules.firstIndex(where: { $0.id == normalized.id }) {
            rules[index] = normalized
        } else {
            rules.append(normalized)
        }
    }

    @discardableResult
    public mutating func remove(command: String) -> CommandRule? {
        let key = Self.matchKey(command)
        guard let index = rules.firstIndex(where: { $0.id == key }) else {
            return nil
        }
        return rules.remove(at: index)
    }
}
