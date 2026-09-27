import Foundation
import XCTest

@testable import MoliSwitchApp

final class UpdateControllerTests: XCTestCase {
    @MainActor
    func testPublicKeyValidationAcceptsOnlyRealEd25519Keys() async {
        let realKey = Data(repeating: 7, count: 32).base64EncodedString()

        XCTAssertTrue(UpdateController.isUsablePublicKey(realKey))
        XCTAssertTrue(UpdateController.isUsablePublicKey("  " + realKey + "\n"))
        XCTAssertFalse(UpdateController.isUsablePublicKey(""))
        XCTAssertFalse(UpdateController.isUsablePublicKey("   "))
        XCTAssertFalse(
            UpdateController.isUsablePublicKey("REPLACE_WITH_SPARKLE_ED25519_PUBLIC_KEY")
        )
        XCTAssertFalse(UpdateController.isUsablePublicKey("tooshort"))
        XCTAssertFalse(
            UpdateController.isUsablePublicKey(
                Data(repeating: 1, count: 31).base64EncodedString()
            )
        )
    }

    @MainActor
    func testBundleWithoutUpdateConfigurationIsNotUpdatable() async {
        // The test bundle carries neither SUFeedURL nor SUPublicEDKey, so no
        // updater may be created for it.
        XCTAssertNil(UpdateController.configuration(of: .main))
        XCTAssertNil(UpdateController.makeForHostBundle(.main))
    }

    @MainActor
    func testControllerStaysIdleUntilStarted() async {
        let controller = UpdateController(hostBundle: .main)

        XCTAssertFalse(controller.canCheckForUpdates)
        XCTAssertNil(controller.blockingReason)

        // Stopping a controller that was never started must be harmless.
        controller.stop()
        controller.stop()
    }
}

