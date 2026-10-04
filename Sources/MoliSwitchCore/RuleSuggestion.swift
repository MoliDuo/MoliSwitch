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
