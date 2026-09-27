import Foundation

struct InstalledApplication: Identifiable, Equatable, Sendable {
    var id: String { bundleIdentifier }

    let name: String
    let bundleIdentifier: String
    /// Nil when the application only exists as a saved rule and could not be
    /// found on disk any more.
    let url: URL?

    var isInstalled: Bool {
        url != nil
    }
}
