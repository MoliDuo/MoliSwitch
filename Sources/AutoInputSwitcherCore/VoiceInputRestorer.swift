import Foundation

/// Decides when a voice input session in a dedicated voice input method (such as
/// Doubao) has finished, and which input source to return to afterwards.
///
/// The type only reacts to events and returns actions; timers, system
/// notifications and window inspection live in the caller, so every transition
/// can be driven with explicit timestamps.
public struct VoiceInputRestorer: Sendable {
    public struct Configuration: Equatable, Sendable {
        public var voiceSourceID: String
        /// How long the overlay must stay hidden before switching back.
        public var settleDelay: TimeInterval
        /// Upper bound after the microphone stops, for overlays that are never
        /// detected as hidden.
        public var overlayTimeout: TimeInterval
        /// How long an input source must stay selected to count as the one the
        /// user was typing with. Doubao passes through other input sources for a
        /// moment while it selects itself.
        public var transientSourceDuration: TimeInterval

        public init(
            voiceSourceID: String,
            settleDelay: TimeInterval = 0.3,
            overlayTimeout: TimeInterval = 8,
            transientSourceDuration: TimeInterval = 1
        ) {
            self.voiceSourceID = voiceSourceID
            self.settleDelay = settleDelay
            self.overlayTimeout = overlayTimeout
            self.transientSourceDuration = transientSourceDuration
        }
    }

    public enum Event: Equatable, Sendable {
        case sourceChanged(id: String?)
        case microphone(running: Bool)
        case overlay(visible: Bool)
        case deadlineReached
    }

    public enum Action: Equatable, Sendable {
        case restore(sourceID: String)
        case scheduleDeadline(Date)
        case cancelDeadline
        /// Remember which voice input windows exist before recording, so that
        /// permanent windows are not mistaken for the recording overlay.
        case captureOverlayBaseline
        case startOverlayWatch
        case stopOverlayWatch
    }

    public enum Phase: Equatable, Sendable {
        case idle
        /// Switched to the voice input source, microphone not used yet.
        case armed(previous: String?)
        case recording(previous: String?)
        /// Microphone stopped; waiting for the overlay to go away.
        case finishing(previous: String?, timeoutAt: Date, overlayHiddenSince: Date?)
    }

    public let configuration: Configuration
    public private(set) var phase: Phase = .idle
    /// The most recent input source that was not the voice input source.
    public private(set) var lastNormalSourceID: String?
    private var lastNormalSelectedAt: Date?
    /// The most recent input source that was not the voice input source and
    /// stayed selected longer than a moment: the one a session returns to.
    public private(set) var settledNormalSourceID: String?
    private var currentSourceID: String?

    public init(configuration: Configuration, currentSourceID: String?) {
        self.configuration = configuration
        self.currentSourceID = currentSourceID
        if let currentSourceID, currentSourceID != configuration.voiceSourceID {
            lastNormalSourceID = currentSourceID
            lastNormalSelectedAt = .distantPast
            settledNormalSourceID = currentSourceID
        }
    }

    public mutating func handle(_ event: Event, now: Date) -> [Action] {
        switch event {
        case .sourceChanged(let id):
            return handleSourceChanged(id, now: now)
        case .microphone(let running):
            return running ? handleMicrophoneStarted(now: now) : handleMicrophoneStopped(now: now)
        case .overlay(let visible):
            return handleOverlay(visible: visible, now: now)
        case .deadlineReached:
            return handleDeadline()
        }
    }

    /// True for input sources that look like Doubao, used to pick a default.
    public static func isLikelyVoiceInputSource(id: String, name: String) -> Bool {
        name.contains("豆包") || id.lowercased().contains("doubao")
    }

    // MARK: - Transitions

    private mutating func handleSourceChanged(_ id: String?, now: Date) -> [Action] {
        settleNormalSource(now: now)
        currentSourceID = id

        if id == configuration.voiceSourceID {
            guard phase == .idle else { return [] }
            phase = .armed(previous: settledNormalSourceID)
            return [.captureOverlayBaseline]
        }

        if let id {
            lastNormalSourceID = id
            lastNormalSelectedAt = now
        }

        // Leaving the voice input source by any means ends the session: the user,
        // the rule engine or our own restore already chose the next source.
        let actions = endSession()
        phase = .idle
        return actions
    }

    private mutating func handleMicrophoneStarted(now: Date) -> [Action] {
        switch phase {
        case .idle:
            // The selection notification may have been missed; the current source
            // still tells us that the voice input source is recording.
            guard currentSourceID == configuration.voiceSourceID else { return [] }
            settleNormalSource(now: now)
            phase = .recording(previous: settledNormalSourceID)
            return [.captureOverlayBaseline]
        case .armed(let previous):
            phase = .recording(previous: previous)
            return []
        case .recording:
            return []
        case .finishing(let previous, _, _):
            // Another utterance right after the previous one.
            phase = .recording(previous: previous)
            return [.cancelDeadline, .stopOverlayWatch]
        }
    }

    private mutating func handleMicrophoneStopped(now: Date) -> [Action] {
        guard case .recording(let previous) = phase else { return [] }

        let timeoutAt = now.addingTimeInterval(configuration.overlayTimeout)
        phase = .finishing(previous: previous, timeoutAt: timeoutAt, overlayHiddenSince: nil)
        // The deadline comes first so that an overlay report delivered while the
        // watch starts can still replace it with the shorter settle deadline.
        return [.scheduleDeadline(timeoutAt), .startOverlayWatch]
    }

    private mutating func handleOverlay(visible: Bool, now: Date) -> [Action] {
        guard case .finishing(let previous, let timeoutAt, let hiddenSince) = phase else {
            return []
        }

        if visible {
            guard hiddenSince != nil else { return [] }
            phase = .finishing(previous: previous, timeoutAt: timeoutAt, overlayHiddenSince: nil)
            return [.scheduleDeadline(timeoutAt)]
        }

        guard hiddenSince == nil else { return [] }
        phase = .finishing(previous: previous, timeoutAt: timeoutAt, overlayHiddenSince: now)
        let settleAt = min(now.addingTimeInterval(configuration.settleDelay), timeoutAt)
        return [.scheduleDeadline(settleAt)]
    }

    private mutating func handleDeadline() -> [Action] {
        guard case .finishing(let previous, _, _) = phase else { return [] }

        phase = .idle
        var actions: [Action] = [.stopOverlayWatch]
        if let previous, previous != configuration.voiceSourceID {
            actions.append(.restore(sourceID: previous))
        }
        return actions
    }

    /// Remembers the current input source as settled once it has stayed
    /// selected long enough.
    private mutating func settleNormalSource(now: Date) {
        guard
            let id = currentSourceID,
            id != configuration.voiceSourceID,
            id == lastNormalSourceID,
            let selectedAt = lastNormalSelectedAt,
            now.timeIntervalSince(selectedAt) >= configuration.transientSourceDuration
        else {
            return
        }

        settledNormalSourceID = id
    }

    private func endSession() -> [Action] {
        if case .finishing = phase {
            return [.cancelDeadline, .stopOverlayWatch]
        }
        return []
    }
}
