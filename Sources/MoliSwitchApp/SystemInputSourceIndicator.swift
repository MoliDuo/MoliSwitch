import Foundation

/// Reads and changes the system setting TSMLanguageIndicatorEnabled.
/// When it is on, macOS shows the new input source next to the caret after
/// every switch. Drawing that bubble holds up the frontmost application for a
/// moment, which is noticeable when a slash switches to English.
@MainActor
final class SystemInputSourceIndicator: InputSourceIndicatorControlling {
    private static let key = "TSMLanguageIndicatorEnabled" as CFString

    var isEnabled: Bool {
        CFPreferencesAppSynchronize(kCFPreferencesAnyApplication)
        switch CFPreferencesCopyAppValue(Self.key, kCFPreferencesAnyApplication) {
        case let number as NSNumber:
            return number.boolValue
        case let string as String:
            return (string as NSString).boolValue
        default:
            // The bubble is shown unless the setting turns it off.
            return true
        }
    }

    func setEnabled(_ enabled: Bool) {
        // Turning it back on removes the setting and restores the system default.
        CFPreferencesSetValue(
            Self.key,
            enabled ? nil : kCFBooleanFalse,
            kCFPreferencesAnyApplication,
            kCFPreferencesCurrentUser,
            kCFPreferencesAnyHost
        )
        CFPreferencesSynchronize(kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
    }
}
