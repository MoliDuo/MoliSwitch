import AppKit

/// Process entry point.
///
/// The app code lives in a library target so that the test target can exercise
/// it without a duplicate main entry point. The executable target only calls
/// this function.
@MainActor
public enum ApplicationEntryPoint {
    /// NSApplication does not retain its delegate strongly, so the delegate is
    /// kept alive here for the whole process lifetime.
    private static var delegate: AppDelegate?

    public static func run() {
        let application = NSApplication.shared
        let appDelegate = AppDelegate()
        Self.delegate = appDelegate
        application.delegate = appDelegate
        application.run()
    }
}
