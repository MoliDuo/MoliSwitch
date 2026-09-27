import Foundation

public enum ApplicationListScope: String, Sendable {
    case all
    case configured
    case unconfigured
}

public struct ApplicationListEntry: Equatable, Sendable {
    public let displayName: String
    public let bundleIdentifier: String
    /// False for rules whose application is not installed any more.
    public let isInstalled: Bool

    public init(
        displayName: String,
        bundleIdentifier: String,
        isInstalled: Bool = true
    ) {
        self.displayName = displayName
        self.bundleIdentifier = bundleIdentifier
        self.isInstalled = isInstalled
    }
}

public struct ApplicationListFilter: Sendable {
    public let query: String
    public let scope: ApplicationListScope
    public let configuredBundleIdentifiers: Set<String>

    public init(
        query: String = "",
        scope: ApplicationListScope = .all,
        configuredBundleIdentifiers: Set<String> = []
    ) {
        self.query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        self.scope = scope
        self.configuredBundleIdentifiers = configuredBundleIdentifiers
    }

    public func includes(_ entry: ApplicationListEntry) -> Bool {
        let isConfigured = configuredBundleIdentifiers.contains(entry.bundleIdentifier)

        switch scope {
        case .all:
            break
        case .configured:
            // Configured rules stay visible even when the app is gone, otherwise
            // leftover rules could never be removed from the interface.
            guard isConfigured else { return false }
        case .unconfigured:
            // Only installed applications that have no rule yet.
            guard !isConfigured, entry.isInstalled else { return false }
        }

        guard !query.isEmpty else {
            return true
        }

        return entry.displayName.localizedCaseInsensitiveContains(query)
            || entry.bundleIdentifier.localizedCaseInsensitiveContains(query)
    }
}
