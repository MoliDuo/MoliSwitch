import Foundation

enum LaunchAtLoginStatus: Equatable, Sendable {
    case notRegistered
    case enabled
    case requiresApproval
    case notFound

    var isEnabled: Bool {
        self == .enabled
    }

    /// Covers both "currently active" and "waiting for the user to allow it in
    /// System Settings". Both states must be unregistered rather than registered
    /// again, so the toggle treats them as on.
    var isRegistered: Bool {
        self == .enabled || self == .requiresApproval
    }
}
