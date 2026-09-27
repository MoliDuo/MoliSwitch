import XCTest

@testable import MoliSwitchApp

final class LaunchAtLoginStatusTests: XCTestCase {
    func testRegistrationSemantics() {
        XCTAssertTrue(LaunchAtLoginStatus.enabled.isRegistered)
        XCTAssertTrue(LaunchAtLoginStatus.requiresApproval.isRegistered)
        XCTAssertFalse(LaunchAtLoginStatus.notRegistered.isRegistered)
        XCTAssertFalse(LaunchAtLoginStatus.notFound.isRegistered)
    }

    func testOnlyTheEnabledStateCountsAsActive() {
        XCTAssertTrue(LaunchAtLoginStatus.enabled.isEnabled)
        XCTAssertFalse(LaunchAtLoginStatus.requiresApproval.isEnabled)
        XCTAssertFalse(LaunchAtLoginStatus.notRegistered.isEnabled)
        XCTAssertFalse(LaunchAtLoginStatus.notFound.isEnabled)
    }
}

