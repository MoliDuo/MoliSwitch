import Foundation
import XCTest

import MoliSwitchCore

@testable import MoliSwitchApp

final class AppRuntimeScanTests: XCTestCase {
    private let terminal = makeInstalledApplication("Terminal", "com.apple.Terminal")
    private let safari = makeInstalledApplication("Safari", "com.apple.Safari")

    private func failure(of root: String) -> URL {
        URL(fileURLWithPath: root, isDirectory: true)
    }

    @MainActor
    func testSuccessfulScanPublishesApplicationsAndInvalidatesIcons() async {
        let fixture = makeFixture(installedApplications: [terminal, safari])
        let generation = fixture.runtime.iconCacheGeneration

        fixture.runtime.refreshApplications()
        await waitUntil { !fixture.runtime.isScanning }

        XCTAssertEqual(
            fixture.runtime.installedApplications.map(\.bundleIdentifier),
            // The runtime publishes the scanner output as is; the search order
            // itself is covered by ApplicationScannerTests.
            ["com.apple.Terminal", "com.apple.Safari"]
        )
        XCTAssertGreaterThan(fixture.runtime.iconCacheGeneration, generation)
        XCTAssertNil(fixture.runtime.scanStatus)
    }

    @MainActor
    func testSecondRefreshIsIgnoredWhileAScanIsRunning() async {
        let fixture = makeFixture(installedApplications: [terminal], scanDelay: 0.25)

        fixture.runtime.refreshApplications()
        XCTAssertTrue(fixture.runtime.isScanning)
        await waitUntil { fixture.scanner.scanCount == 1 }

        // The refresh button is disabled in the interface, and the runtime must
        // refuse the request even when it is asked directly.
        fixture.runtime.refreshApplications()

        await waitUntil { !fixture.runtime.isScanning }

        XCTAssertEqual(fixture.scanner.scanCount, 1)
        XCTAssertEqual(fixture.runtime.installedApplications.count, 1)
        XCTAssertNil(fixture.runtime.scanStatus)
    }

    @MainActor
    func testTotalScanFailureKeepsThePreviousListAndReportsAnError() async {
        let fixture = makeFixture(installedApplications: [terminal])
        fixture.runtime.refreshApplications()
        await waitUntil { !fixture.runtime.isScanning }
        let generation = fixture.runtime.iconCacheGeneration

        fixture.scanner.setResult(
            ApplicationScanResult(
                applications: [],
                failedRoots: [failure(of: "/Applications")],
                rootCount: 1
            )
        )
        fixture.runtime.refreshApplications()
        await waitUntil { !fixture.runtime.isScanning }

        XCTAssertEqual(
            fixture.runtime.installedApplications.map(\.bundleIdentifier),
            ["com.apple.Terminal"]
        )
        XCTAssertEqual(fixture.runtime.scanStatus?.severity, .error)
        XCTAssertEqual(fixture.runtime.iconCacheGeneration, generation)
    }

    @MainActor
    func testPartialScanFailurePublishesWhatWasFoundAndWarns() async {
        let fixture = makeFixture(installedApplications: [terminal])
        let generation = fixture.runtime.iconCacheGeneration

        fixture.scanner.setResult(
            ApplicationScanResult(
                applications: [safari],
                failedRoots: [failure(of: "/System/Applications")],
                rootCount: 4
            )
        )
        fixture.runtime.refreshApplications()
        await waitUntil { !fixture.runtime.isScanning }

        XCTAssertEqual(
            fixture.runtime.installedApplications.map(\.bundleIdentifier),
            ["com.apple.Safari"]
        )
        XCTAssertEqual(fixture.runtime.scanStatus?.severity, .warning)
        XCTAssertGreaterThan(fixture.runtime.iconCacheGeneration, generation)
    }

    @MainActor
    func testPartialScanFailureWithoutResultsKeepsThePreviousList() async {
        let fixture = makeFixture(installedApplications: [terminal])
        fixture.runtime.refreshApplications()
        await waitUntil { !fixture.runtime.isScanning }
        let generation = fixture.runtime.iconCacheGeneration

        fixture.scanner.setResult(
            ApplicationScanResult(
                applications: [],
                failedRoots: [failure(of: "/Applications")],
                rootCount: 4
            )
        )
        fixture.runtime.refreshApplications()
        await waitUntil { !fixture.runtime.isScanning }

        XCTAssertEqual(
            fixture.runtime.installedApplications.map(\.bundleIdentifier),
            ["com.apple.Terminal"]
        )
        XCTAssertEqual(fixture.runtime.scanStatus?.severity, .warning)
        XCTAssertEqual(fixture.runtime.iconCacheGeneration, generation)
    }

    @MainActor
    func testRetryAfterATotalFailureRecovers() async {
        let fixture = makeFixture(installedApplications: [terminal])
        fixture.scanner.setResult(
            ApplicationScanResult(
                applications: [],
                failedRoots: [failure(of: "/Applications")],
                rootCount: 1
            )
        )
        fixture.runtime.refreshApplications()
        await waitUntil { !fixture.runtime.isScanning }
        XCTAssertNotNil(fixture.runtime.scanStatus)

        fixture.scanner.setResult(
            ApplicationScanResult(
                applications: [terminal, safari],
                failedRoots: [],
                rootCount: 1
            )
        )
        fixture.runtime.refreshApplications()
        await waitUntil { !fixture.runtime.isScanning }

        XCTAssertEqual(fixture.runtime.installedApplications.count, 2)
        XCTAssertNil(fixture.runtime.scanStatus)
    }

    @MainActor
    func testRefreshButtonIsDisabledWhileScanning() async {
        let fixture = makeFixture(installedApplications: [terminal], scanDelay: 0.25)

        XCTAssertFalse(fixture.runtime.isScanning)
        fixture.runtime.refreshApplications()
        XCTAssertTrue(fixture.runtime.isScanning)

        await waitUntil { !fixture.runtime.isScanning }
        XCTAssertFalse(fixture.runtime.isScanning)
    }
}
