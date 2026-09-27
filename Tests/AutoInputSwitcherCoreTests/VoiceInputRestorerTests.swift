import Foundation
import XCTest
@testable import AutoInputSwitcherCore

final class VoiceInputRestorerTests: XCTestCase {
    private let abc = "com.sogou.inputmethod.abc.shuangpin"
    private let doubao = "com.bytedance.inputmethod.doubaoime.pinyin"
    private let start = Date(timeIntervalSinceReferenceDate: 1_000)

    private func makeRestorer(current: String?) -> VoiceInputRestorer {
        VoiceInputRestorer(
            configuration: VoiceInputRestorer.Configuration(voiceSourceID: doubao),
            currentSourceID: current
        )
    }

    private func at(_ seconds: TimeInterval) -> Date {
        start.addingTimeInterval(seconds)
    }

    func testRestoresPreviousSourceAfterOverlayDisappears() {
        var restorer = makeRestorer(current: abc)

        XCTAssertEqual(restorer.handle(.sourceChanged(id: doubao), now: at(0)), [.captureOverlayBaseline])
        XCTAssertEqual(restorer.handle(.microphone(running: true), now: at(0.1)), [])
        XCTAssertEqual(
            restorer.handle(.microphone(running: false), now: at(3)),
            [.scheduleDeadline(at(11)), .startOverlayWatch]
        )
        XCTAssertEqual(restorer.handle(.overlay(visible: true), now: at(3.1)), [])
        XCTAssertEqual(
            restorer.handle(.overlay(visible: false), now: at(4)),
            [.scheduleDeadline(at(4.3))]
        )
        XCTAssertEqual(
            restorer.handle(.deadlineReached, now: at(4.3)),
            [.stopOverlayWatch, .restore(sourceID: abc)]
        )
        XCTAssertEqual(restorer.phase, .idle)
    }

    func testManualSwitchWithoutMicrophoneDoesNotRestore() {
        var restorer = makeRestorer(current: abc)

        _ = restorer.handle(.sourceChanged(id: doubao), now: at(0))
        XCTAssertEqual(restorer.handle(.overlay(visible: false), now: at(1)), [])
        XCTAssertEqual(restorer.handle(.deadlineReached, now: at(10)), [])
        XCTAssertEqual(restorer.phase, .armed(previous: abc))
    }

    func testOverlayThatNeverHidesFallsBackToTimeout() {
        var restorer = makeRestorer(current: abc)

        _ = restorer.handle(.sourceChanged(id: doubao), now: at(0))
        _ = restorer.handle(.microphone(running: true), now: at(0.1))
        _ = restorer.handle(.microphone(running: false), now: at(2))
        XCTAssertEqual(restorer.handle(.overlay(visible: true), now: at(2.2)), [])

        XCTAssertEqual(
            restorer.handle(.deadlineReached, now: at(10)),
            [.stopOverlayWatch, .restore(sourceID: abc)]
        )
    }

    func testOverlayReappearingRestoresTheTimeoutDeadline() {
        var restorer = makeRestorer(current: abc)

        _ = restorer.handle(.sourceChanged(id: doubao), now: at(0))
        _ = restorer.handle(.microphone(running: true), now: at(0.1))
        _ = restorer.handle(.microphone(running: false), now: at(2))
        _ = restorer.handle(.overlay(visible: false), now: at(2.1))

        XCTAssertEqual(
            restorer.handle(.overlay(visible: true), now: at(2.2)),
            [.scheduleDeadline(at(10))]
        )
    }

    func testMicrophoneRestartingWhileSettlingCancelsRestore() {
        var restorer = makeRestorer(current: abc)

        _ = restorer.handle(.sourceChanged(id: doubao), now: at(0))
        _ = restorer.handle(.microphone(running: true), now: at(0.1))
        _ = restorer.handle(.microphone(running: false), now: at(2))
        _ = restorer.handle(.overlay(visible: false), now: at(2.1))

        XCTAssertEqual(
            restorer.handle(.microphone(running: true), now: at(2.2)),
            [.cancelDeadline, .stopOverlayWatch]
        )
        XCTAssertEqual(restorer.phase, .recording(previous: abc))
        XCTAssertEqual(restorer.handle(.deadlineReached, now: at(2.4)), [])

        // The second utterance still ends with a restore.
        _ = restorer.handle(.microphone(running: false), now: at(5))
        _ = restorer.handle(.overlay(visible: false), now: at(5.1))
        XCTAssertEqual(
            restorer.handle(.deadlineReached, now: at(5.4)),
            [.stopOverlayWatch, .restore(sourceID: abc)]
        )
    }

    func testSwitchingAwayWhileWaitingEndsTheSession() {
        var restorer = makeRestorer(current: abc)

        _ = restorer.handle(.sourceChanged(id: doubao), now: at(0))
        _ = restorer.handle(.microphone(running: true), now: at(0.1))
        _ = restorer.handle(.microphone(running: false), now: at(2))

        XCTAssertEqual(
            restorer.handle(.sourceChanged(id: "com.apple.keylayout.US"), now: at(2.1)),
            [.cancelDeadline, .stopOverlayWatch]
        )
        XCTAssertEqual(restorer.phase, .idle)
        XCTAssertEqual(restorer.lastNormalSourceID, "com.apple.keylayout.US")
        XCTAssertEqual(restorer.handle(.deadlineReached, now: at(10)), [])
    }

    func testSourcesSeenWhileDoubaoSelectsItselfAreNotRestored() {
        let us = "com.apple.keylayout.US"
        var restorer = makeRestorer(current: abc)

        // Doubao passes through U.S. twice before it stays selected.
        _ = restorer.handle(.sourceChanged(id: us), now: at(0))
        _ = restorer.handle(.sourceChanged(id: doubao), now: at(0.33))
        _ = restorer.handle(.sourceChanged(id: us), now: at(0.5))
        _ = restorer.handle(.sourceChanged(id: doubao), now: at(0.94))
        XCTAssertEqual(restorer.phase, .armed(previous: abc))

        _ = restorer.handle(.microphone(running: true), now: at(1.3))
        _ = restorer.handle(.microphone(running: false), now: at(5))
        _ = restorer.handle(.overlay(visible: false), now: at(5.6))
        XCTAssertEqual(
            restorer.handle(.deadlineReached, now: at(5.9)),
            [.stopOverlayWatch, .restore(sourceID: abc)]
        )
    }

    func testSourceKeptForAWhileBeforeSpeakingIsRestored() {
        let us = "com.apple.keylayout.US"
        var restorer = makeRestorer(current: abc)

        _ = restorer.handle(.sourceChanged(id: us), now: at(0))
        _ = restorer.handle(.sourceChanged(id: doubao), now: at(20))

        XCTAssertEqual(restorer.phase, .armed(previous: us))
        XCTAssertEqual(restorer.settledNormalSourceID, us)
    }

    func testMissedSelectionNotificationStillRestores() {
        var restorer = makeRestorer(current: abc)

        // A finished session whose restore did not take effect leaves Doubao
        // selected while the restorer is idle.
        _ = restorer.handle(.sourceChanged(id: doubao), now: at(0))
        _ = restorer.handle(.microphone(running: true), now: at(0.1))
        _ = restorer.handle(.microphone(running: false), now: at(1))
        _ = restorer.handle(.deadlineReached, now: at(9))
        XCTAssertEqual(restorer.phase, .idle)

        // The next recording starts without any selection notification.
        XCTAssertEqual(
            restorer.handle(.microphone(running: true), now: at(10)),
            [.captureOverlayBaseline]
        )
        XCTAssertEqual(restorer.phase, .recording(previous: abc))

        _ = restorer.handle(.microphone(running: false), now: at(12))
        _ = restorer.handle(.overlay(visible: false), now: at(12.5))
        XCTAssertEqual(
            restorer.handle(.deadlineReached, now: at(12.8)),
            [.stopOverlayWatch, .restore(sourceID: abc)]
        )
    }

    func testMicrophoneInIdleOnOtherSourceIsIgnored() {
        var restorer = makeRestorer(current: abc)

        XCTAssertEqual(restorer.handle(.microphone(running: true), now: at(0)), [])
        XCTAssertEqual(restorer.phase, .idle)
    }

    func testNoPreviousSourceMeansNoRestore() {
        var restorer = makeRestorer(current: nil)

        _ = restorer.handle(.sourceChanged(id: doubao), now: at(0))
        _ = restorer.handle(.microphone(running: true), now: at(0.1))
        _ = restorer.handle(.microphone(running: false), now: at(2))

        XCTAssertEqual(restorer.handle(.deadlineReached, now: at(10)), [.stopOverlayWatch])
        XCTAssertEqual(restorer.phase, .idle)
    }

    func testSettleDeadlineNeverExceedsTimeout() {
        var restorer = VoiceInputRestorer(
            configuration: VoiceInputRestorer.Configuration(
                voiceSourceID: doubao,
                settleDelay: 5,
                overlayTimeout: 1
            ),
            currentSourceID: abc
        )

        _ = restorer.handle(.sourceChanged(id: doubao), now: at(0))
        _ = restorer.handle(.microphone(running: true), now: at(0.1))
        _ = restorer.handle(.microphone(running: false), now: at(2))

        XCTAssertEqual(
            restorer.handle(.overlay(visible: false), now: at(2.5)),
            [.scheduleDeadline(at(3))]
        )
    }

    func testDoubaoDetection() {
        XCTAssertTrue(VoiceInputRestorer.isLikelyVoiceInputSource(id: "x", name: "豆包输入法"))
        XCTAssertTrue(
            VoiceInputRestorer.isLikelyVoiceInputSource(id: "com.bytedance.DoubaoIME", name: "Pinyin")
        )
        XCTAssertFalse(
            VoiceInputRestorer.isLikelyVoiceInputSource(id: "com.apple.keylayout.ABC", name: "ABC")
        )
    }
}
