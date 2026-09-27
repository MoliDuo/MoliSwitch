import Foundation

public struct AppRule: Codable, Equatable, Identifiable, Sendable {
    public var id: String { bundleIdentifier }

    public var bundleIdentifier: String
    public var applicationName: String
    public var inputSourceID: String
    public var inputSourceName: String

    public init(
        bundleIdentifier: String,
        applicationName: String,
        inputSourceID: String,
        inputSourceName: String
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.applicationName = applicationName
        self.inputSourceID = inputSourceID
        self.inputSourceName = inputSourceName
    }
}
