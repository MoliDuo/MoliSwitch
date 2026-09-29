import XCTest

@testable import MoliSwitchApp

@MainActor
final class AppRuntimeInputSourceIndicatorTests: XCTestCase {
    func testTurningTheIndicatorOffAndOn() {
        let fixture = makeFixture()
        XCTAssertTrue(fixture.runtime.inputSourceIndicatorEnabled)

        fixture.runtime.setInputSourceIndicatorEnabled(false)
        XCTAssertFalse(fixture.runtime.inputSourceIndicatorEnabled)
        XCTAssertFalse(fixture.indicator.isEnabled)

        fixture.runtime.setInputSourceIndicatorEnabled(true)
        XCTAssertTrue(fixture.runtime.inputSourceIndicatorEnabled)
        XCTAssertEqual(fixture.indicator.changes, [false, true])
    }

    func testChangesMadeOutsideAreReadAgain() {
        let fixture = makeFixture()
        fixture.indicator.isEnabled = false
        XCTAssertTrue(fixture.runtime.inputSourceIndicatorEnabled)

        fixture.runtime.refreshInputSourceIndicator()
        XCTAssertFalse(fixture.runtime.inputSourceIndicatorEnabled)
    }
}
