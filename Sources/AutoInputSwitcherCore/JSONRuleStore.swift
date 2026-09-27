import Foundation

/// Persistence boundary for per-application rules.
///
/// Injectable so the app and the tests can substitute their own storage without
/// touching the real user configuration.
public protocol RuleStore: Sendable {
    var url: URL { get }
    func load() throws -> [AppRule]
    func save(_ rules: [AppRule]) throws
}

/// Persistence boundary for the rules of programs running in a terminal.
public protocol CommandRuleStore: Sendable {
    var url: URL { get }
    func load() throws -> [CommandRule]
    func save(_ rules: [CommandRule]) throws
}

public typealias JSONRuleStore = JSONFileStore<AppRule>
public typealias JSONCommandRuleStore = JSONFileStore<CommandRule>

extension JSONFileStore: RuleStore where Element == AppRule {
    public static func applicationSupportStore(
        appName: String = "AutoInputSwitcher"
    ) -> JSONRuleStore {
        JSONRuleStore(
            url: applicationSupportDirectory(appName: appName)
                .appendingPathComponent("rules.json")
        )
    }
}

extension JSONFileStore: CommandRuleStore where Element == CommandRule {
    public static func applicationSupportStore(
        appName: String = "AutoInputSwitcher"
    ) -> JSONCommandRuleStore {
        JSONCommandRuleStore(
            url: applicationSupportDirectory(appName: appName)
                .appendingPathComponent("command-rules.json")
        )
    }
}

/// Stores rules as a JSON array in a single file.
///
/// load() only returns an empty array when the file genuinely does not exist.
/// Every other failure (unreadable file, malformed JSON, permission problems)
/// is surfaced as a thrown error, so a broken file is never mistaken for an
/// empty rule set that would then be written back over the user's data.
public struct JSONFileStore<Element: Codable & Sendable>: Sendable {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    public static func applicationSupportDirectory(
        appName: String = "AutoInputSwitcher"
    ) -> URL {
        let baseURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)

        return baseURL.appendingPathComponent(appName, isDirectory: true)
    }

    public var fileExists: Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    public func load() throws -> [Element] {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            if Self.isMissingFileError(error) {
                return []
            }
            throw error
        }

        return try Self.makeDecoder().decode([Element].self, from: data)
    }

    public func save(_ rules: [Element]) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        let data = try Self.makeEncoder().encode(rules)
        try data.write(to: url, options: [.atomic])
    }

    /// True when the underlying Cocoa error means "there is no file here yet".
    static func isMissingFileError(_ error: Error) -> Bool {
        let nsError = error as NSError

        if nsError.domain == NSCocoaErrorDomain, nsError.code == NSFileReadNoSuchFileError {
            return true
        }

        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
            return isMissingFileError(underlying)
        }

        return false
    }

    // Encoders and decoders are created per call: they are cheap, and this keeps
    // the store free of shared mutable state.
    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    private static func makeDecoder() -> JSONDecoder {
        JSONDecoder()
    }
}
