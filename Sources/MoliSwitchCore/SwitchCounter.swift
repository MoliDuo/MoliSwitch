import Foundation

public final class SwitchCounter {
    private let defaults: UserDefaults
    private let key: String

    public init(
        defaults: UserDefaults = .standard,
        key: String = "switchCount"
    ) {
        self.defaults = defaults
        self.key = key
    }

    public var count: Int {
        defaults.integer(forKey: key)
    }

    public func recordSwitch() {
        defaults.set(count + 1, forKey: key)
    }
}
