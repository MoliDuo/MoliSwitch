import Foundation
import XCTest

@testable import AutoInputSwitcherApp

final class AppRuntimeVoiceRestoreTests: XCTestCase {
    @MainActor
    private func makeVoiceFixture() -> RuntimeFixture {
        let fixture = makeFixture(
            sources: TestInputSources.all + [TestInputSources.doubao],
            current: TestInputSources.abc
        )
        fixture.runtime.startVoiceRestore()
        return fixture
    }

    @MainActor
    private func speak(in fixture: RuntimeFixture) {
        fixture.inputSources.simulateSelection(of: TestInputSources.doubao)
        fixture.microphone.simulate(running: true)
        fixture.microphone.simulate(running: false)
    }

    @MainActor
    func testDoubaoIsDetectedAutomatically() async {
        let fixture = makeVoiceFixture()

        XCTAssertEqual(fixture.runtime.effectiveVoiceInputSource, TestInputSources.doubao)
        XCTAssertTrue(fixture.microphone.isMonitoring)
    }

    @MainActor
    func testVoiceSessionRestoresPreviousInputSource() async {
        let fixture = makeVoiceFixture()

        speak(in: fixture)
        XCTAssertTrue(fixture.overlay.isWatching)
        XCTAssertEqual(fixture.overlay.baselineCount, 1)
        fixture.overlay.simulate(visible: false)

        await waitUntil { fixture.inputSources.current == TestInputSources.abc }

        XCTAssertEqual(fixture.inputSources.current, TestInputSources.abc)
        XCTAssertEqual(fixture.runtime.currentInputSource, TestInputSources.abc)
        XCTAssertEqual(fixture.runtime.switchCount, 1)
        XCTAssertFalse(fixture.overlay.isWatching)
    }

    @MainActor
    func testRestoringAKeyboardLayoutSelectsTheChineseInputMethodFirst() async {
        let fixture = makeFixture(
            sources: [TestInputSources.us, TestInputSources.shuangpin, TestInputSources.doubao],
            current: TestInputSources.us
        )
        fixture.runtime.startVoiceRestore()

        speak(in: fixture)
        fixture.overlay.simulate(visible: false)

        await waitUntil { !fixture.inputSources.selectedIDs.isEmpty }

        // Caps Lock then returns to Shuangpin instead of Doubao.
        XCTAssertEqual(
            fixture.inputSources.selectedIDs,
            [TestInputSources.shuangpin.id, TestInputSources.us.id]
        )
        XCTAssertEqual(fixture.inputSources.current, TestInputSources.us)
        XCTAssertEqual(fixture.runtime.switchCount, 1)
    }

    @MainActor
    func testRestoringAnInputMethodSelectsOnlyIt() async {
        let fixture = makeFixture(
            sources: [TestInputSources.us, TestInputSources.shuangpin, TestInputSources.doubao],
            current: TestInputSources.shuangpin
        )
        fixture.runtime.startVoiceRestore()

        speak(in: fixture)
        fixture.overlay.simulate(visible: false)

        await waitUntil { !fixture.inputSources.selectedIDs.isEmpty }

        XCTAssertEqual(fixture.inputSources.selectedIDs, [TestInputSources.shuangpin.id])
    }

    @MainActor
    func testOverlayTimeoutStillRestores() async {
        let fixture = makeVoiceFixture()

        speak(in: fixture)

        await waitUntil { fixture.inputSources.current == TestInputSources.abc }

        XCTAssertEqual(fixture.inputSources.current, TestInputSources.abc)
    }

    @MainActor
    func testManualSwitchToDoubaoWithoutSpeakingIsKept() async {
        let fixture = makeVoiceFixture()

        fixture.inputSources.simulateSelection(of: TestInputSources.doubao)
        try? await Task.sleep(for: .milliseconds(700))

        XCTAssertEqual(fixture.inputSources.current, TestInputSources.doubao)
        XCTAssertEqual(fixture.runtime.switchCount, 0)
    }

    @MainActor
    func testDisabledFeatureDoesNotRestore() async {
        let fixture = makeVoiceFixture()
        fixture.runtime.voiceRestoreEnabled = false

        XCTAssertFalse(fixture.microphone.isMonitoring)

        speak(in: fixture)
        fixture.overlay.simulate(visible: false)
        try? await Task.sleep(for: .milliseconds(700))

        XCTAssertEqual(fixture.inputSources.current, TestInputSources.doubao)
        XCTAssertEqual(fixture.runtime.switchCount, 0)
        XCTAssertEqual(fixture.defaults.object(forKey: AppRuntime.voiceRestoreEnabledKey) as? Bool, false)
    }

    @MainActor
    func testFeatureIsInactiveWithoutAVoiceInputSource() async {
        let fixture = makeFixture(current: TestInputSources.abc)
        fixture.runtime.startVoiceRestore()

        XCTAssertNil(fixture.runtime.effectiveVoiceInputSource)
        XCTAssertFalse(fixture.microphone.isMonitoring)
    }

    @MainActor
    func testRuleChoicesHideTheVoiceInputSource() async {
        let fixture = makeVoiceFixture()
        let terminal = makeInstalledApplication("Terminal", "com.apple.Terminal")
        let doubaoID = TestInputSources.doubao.id

        XCTAssertFalse(fixture.runtime.inputSourceChoices(for: terminal).contains { $0.id == doubaoID })
        XCTAssertTrue(fixture.runtime.voiceInputSourceChoices.contains { $0.id == doubaoID })

        // A rule that already uses the voice input source keeps showing it by name.
        fixture.runtime.voiceRestoreEnabled = false
        fixture.runtime.setInputSourceID(doubaoID, for: terminal)
        fixture.runtime.voiceRestoreEnabled = true

        XCTAssertEqual(
            fixture.runtime.inputSourceChoices(for: terminal).first { $0.id == doubaoID },
            InputSourceChoice(id: doubaoID, name: TestInputSources.doubao.name)
        )
    }

    @MainActor
    func testExplicitVoiceInputSourceIsPersistedAndUsed() async {
        let fixture = makeVoiceFixture()

        fixture.runtime.voiceInputSourceSelection = TestInputSources.us.id

        XCTAssertEqual(fixture.runtime.effectiveVoiceInputSource, TestInputSources.us)
        XCTAssertEqual(
            fixture.defaults.string(forKey: AppRuntime.voiceInputSourceIDKey),
            TestInputSources.us.id
        )

        fixture.runtime.voiceInputSourceSelection = AppRuntime.automaticInputSourceID

        XCTAssertNil(fixture.defaults.string(forKey: AppRuntime.voiceInputSourceIDKey))
        XCTAssertEqual(fixture.runtime.effectiveVoiceInputSource, TestInputSources.doubao)
    }
}
