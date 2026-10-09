import Foundation

/// An application in which a slash typed at the start of the input switches to
/// the English input source, because it starts a command there.
public struct SlashCommandApp: Codable, Equatable, Identifiable, Sendable {
    public var id: String {
        bundleIdentifier
    }

    public var bundleIdentifier: String
    public var applicationName: String

    public init(bundleIdentifier: String, applicationName: String) {
        self.bundleIdentifier = bundleIdentifier
        self.applicationName = applicationName
    }

    /// Terminal emulators report the caret at the end of everything on screen,
    /// not in the line being typed.
    private static let terminalBundleIdentifiers: Set<String> = [
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "com.mitchellh.ghostty",
        "dev.warp.Warp-Stable",
        "com.github.wez.wezterm",
        "net.kovidgoyal.kitty",
        "org.alacritty",
        "co.zeit.hyper",
        "com.raphaelamorim.rio",
    ]

    /// Whether Accessibility tells where the caret is in the input of the
    /// application, or the start of the input has to be guessed from the keys.
    public static func reportsCaretPosition(bundleIdentifier: String) -> Bool {
        !terminalBundleIdentifiers.contains(bundleIdentifier)
    }
}

/// The applications with slash commands, each at most once, in the order of
/// their names.
public struct SlashCommandAppList: Equatable, Sendable {
    public private(set) var apps: [SlashCommandApp]

    public init(apps: [SlashCommandApp] = []) {
        self.apps = []
        for app in apps {
            insert(app)
        }
    }

    /// Builds the list from persisted entries: invalid identifiers are dropped
    /// and the first entry seen for each application wins.
    public init(normalizing apps: [SlashCommandApp]) {
        self.init(apps: apps.filter { RuleSet.isValidIdentifier($0.bundleIdentifier) })
    }

    public func contains(bundleIdentifier: String) -> Bool {
        apps.contains { $0.bundleIdentifier == bundleIdentifier }
    }

    public mutating func insert(_ app: SlashCommandApp) {
        guard !contains(bundleIdentifier: app.bundleIdentifier) else { return }
        apps.append(app)
        apps.sort { lhs, rhs in
            let comparison = lhs.applicationName.localizedCaseInsensitiveCompare(rhs.applicationName)
            if comparison == .orderedSame {
                return lhs.bundleIdentifier < rhs.bundleIdentifier
            }
            return comparison == .orderedAscending
        }
    }

    @discardableResult
    public mutating func remove(bundleIdentifier: String) -> SlashCommandApp? {
        guard let index = apps.firstIndex(where: { $0.bundleIdentifier == bundleIdentifier }) else {
            return nil
        }
        return apps.remove(at: index)
    }
}
