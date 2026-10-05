import Foundation

/// A change to the rules that the usage log suggests.
public struct RuleSuggestion: Identifiable, Equatable, Sendable {
    public enum Action: Equatable, Sendable {
        /// Use this input source by default in the application.
        case setAppRule(bundleIdentifier: String, applicationName: String, inputSourceID: String)
        /// Use this input source in one text field of the application.
        case addFieldRule(
            bundleIdentifier: String,
            applicationName: String,
            signature: FieldSignature,
            inputSourceID: String
        )
        /// Use this input source while the program runs in the terminal.
        case setCommandRule(command: String, inputSourceID: String)
        /// Whether Shift with this key switches to English, in one application
        /// or, without one, everywhere.
        case setShiftKey(bundleIdentifier: String?, applicationName: String?, keyCode: Int, enabled: Bool)
        /// Whether letting go of Shift switches back, in one application or everywhere.
        case setShiftRestore(bundleIdentifier: String?, applicationName: String?, enabled: Bool)
    }

    /// What a suggestion changes, for showing them in groups.
    public enum Kind: Int, CaseIterable, Comparable, Sendable {
        case application, command, field, shift

        public static func < (lhs: Kind, rhs: Kind) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    public var kind: Kind {
        switch action {
        case .setAppRule: .application
        case .setCommandRule: .command
        case .addFieldRule: .field
        case .setShiftKey, .setShiftRestore: .shift
        }
    }

    /// Stable for the same suggestion, so a dismissed one stays dismissed.
    public var id: String
    public var title: String
    /// What in the log led to it, in a sentence.
    public var evidence: String
    public var action: Action

    public init(id: String, title: String, evidence: String, action: Action) {
        self.id = id
        self.title = title
        self.evidence = evidence
        self.action = action
    }
}

/// A suggestion the user applied, with what it replaced, so it can be undone.
public struct AppliedSuggestion: Codable, Equatable, Identifiable, Sendable {
    public enum Change: Codable, Equatable, Sendable {
        /// The rule the application had before, if any.
        case appRule(bundleIdentifier: String, previous: AppRule?)
        /// The field rule that was added.
        case fieldRule(id: UUID)
        /// The rule the program had before, if any.
        case commandRule(command: String, previous: CommandRule?)
        /// The Shift settings before: the application's own, if it had them,
        /// or, without an application, the settings for everywhere.
        case shiftOptions(bundleIdentifier: String?, previous: ShiftEnglishOptions?)
    }

    public var id: String
    public var title: String
    public var appliedAt: Date
    public var change: Change

    public init(id: String, title: String, appliedAt: Date, change: Change) {
        self.id = id
        self.title = title
        self.appliedAt = appliedAt
        self.change = change
    }
}
