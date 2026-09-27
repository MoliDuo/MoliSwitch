import Foundation
import XCTest

@testable import MoliSwitchApp

final class SingleInstanceLockTests: XCTestCase {
    private func withTemporaryDirectory(_ body: (URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "MoliSwitchLockTests-" + UUID().uuidString,
                isDirectory: true
            )

        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        try body(directory)
    }

    func testSecondLockOnTheSameFileIsRejected() throws {
        try withTemporaryDirectory { directory in
            let url = directory.appendingPathComponent("instance.lock")
            let first = SingleInstanceLock(url: url)
            let second = SingleInstanceLock(url: url)

            XCTAssertTrue(try first.acquire())
            XCTAssertTrue(first.isHeld)

            XCTAssertFalse(try second.acquire())
            XCTAssertFalse(second.isHeld)

            first.release()
            XCTAssertFalse(first.isHeld)

            XCTAssertTrue(try second.acquire())
            second.release()
        }
    }

    func testLockFileIsKeptOnDiskAfterRelease() throws {
        try withTemporaryDirectory { directory in
            let url = directory.appendingPathComponent("instance.lock")
            let lock = SingleInstanceLock(url: url)

            XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
            XCTAssertTrue(try lock.acquire())
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))

            lock.release()

            // The file stays behind on purpose: deleting it would let two
            // processes believe they hold the same lock.
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        }
    }

    func testAcquiringTwiceOnTheSameInstanceKeepsTheLock() throws {
        try withTemporaryDirectory { directory in
            let lock = SingleInstanceLock(url: directory.appendingPathComponent("instance.lock"))

            XCTAssertTrue(try lock.acquire())
            XCTAssertTrue(try lock.acquire())
            XCTAssertTrue(lock.isHeld)

            lock.release()
            XCTAssertFalse(lock.isHeld)
        }
    }

    func testReleaseWithoutAcquireIsHarmless() throws {
        try withTemporaryDirectory { directory in
            let lock = SingleInstanceLock(url: directory.appendingPathComponent("instance.lock"))

            lock.release()
            lock.release()

            XCTAssertFalse(lock.isHeld)
        }
    }

    func testAcquireReportsFailureWhenTheDirectoryCannotBeCreated() throws {
        try withTemporaryDirectory { directory in
            let blocker = directory.appendingPathComponent("blocker")
            try Data("not a directory".utf8).write(to: blocker)

            let lock = SingleInstanceLock(
                url: blocker.appendingPathComponent("instance.lock")
            )

            XCTAssertThrowsError(try lock.acquire())
            XCTAssertFalse(lock.isHeld)
        }
    }

    func testApplicationSupportLockPathUsesTheGivenApplicationName() {
        let lock = SingleInstanceLock.applicationSupportLock(appName: "MoliSwitchTests")

        XCTAssertEqual(lock.url.lastPathComponent, "instance.lock")
        XCTAssertEqual(
            lock.url.deletingLastPathComponent().lastPathComponent,
            "MoliSwitchTests"
        )
    }
}
