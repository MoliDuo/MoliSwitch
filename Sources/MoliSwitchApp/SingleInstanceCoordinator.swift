import Foundation

/// Coordinates the primary instance and any later launch of the same app.
///
/// Only the process that holds the file lock creates a runtime. Every other
/// launch asks the primary instance to show its window and then exits, even when
/// that request cannot be delivered: a second set of listeners must never be
/// created.
@MainActor
final class SingleInstanceCoordinator: NSObject {
    static let showRequestNotification = Notification.Name(
        "com.moli.MoliSwitch.showWindowRequest"
    )
    static let showResponseNotification = Notification.Name(
        "com.moli.MoliSwitch.showWindowResponse"
    )

    private static let identifierKey = "identifier"
    private static let retryInterval: TimeInterval = 0.1
    private static let defaultTimeout: TimeInterval = 2

    private let lock: SingleInstanceLock
    private var receivedResponses: Set<String> = []
    private var isResponding = false
    private var showHandler: (@MainActor () -> Void)?

    init(lock: SingleInstanceLock) {
        self.lock = lock
        super.init()
    }

    /// - Returns: true when this process owns the single instance lock.
    func acquireExclusiveInstance() throws -> Bool {
        try lock.acquire()
    }

    var isPrimaryInstance: Bool {
        lock.isHeld
    }

    func releaseLock() {
        stopRespondingToShowRequests()
        lock.release()
    }

    /// Starts answering show requests. Call this only once the window can be shown.
    func startRespondingToShowRequests(handler: @escaping @MainActor () -> Void) {
        guard isPrimaryInstance, !isResponding else {
            return
        }

        isResponding = true
        showHandler = handler
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(handleShowRequest(_:)),
            name: Self.showRequestNotification,
            object: nil
        )
    }

    func stopRespondingToShowRequests() {
        guard isResponding else {
            return
        }

        isResponding = false
        showHandler = nil
        DistributedNotificationCenter.default().removeObserver(
            self,
            name: Self.showRequestNotification,
            object: nil
        )
    }

    /// Asks an already running instance to show its window.
    ///
    /// The request is retried because the primary instance may still be starting
    /// up and only begins listening once it is ready.
    /// - Returns: true when the primary instance acknowledged the request.
    @discardableResult
    func requestShowFromExistingInstance(timeout: TimeInterval = defaultTimeout) -> Bool {
        guard !isPrimaryInstance else {
            return true
        }

        let center = DistributedNotificationCenter.default()
        center.addObserver(
            self,
            selector: #selector(handleShowResponse(_:)),
            name: Self.showResponseNotification,
            object: nil
        )
        defer {
            center.removeObserver(
                self,
                name: Self.showResponseNotification,
                object: nil
            )
        }

        let identifier = UUID().uuidString
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            center.post(
                name: Self.showRequestNotification,
                object: nil,
                userInfo: [Self.identifierKey: identifier]
            )

            let nextAttempt = min(
                Date().addingTimeInterval(Self.retryInterval),
                deadline
            )
            RunLoop.current.run(mode: .default, before: nextAttempt)

            if receivedResponses.contains(identifier) {
                return true
            }
        }

        return false
    }

    @objc private func handleShowRequest(_ notification: Notification) {
        guard
            let identifier = notification.userInfo?[Self.identifierKey] as? String
        else {
            return
        }

        showHandler?()

        DistributedNotificationCenter.default().post(
            name: Self.showResponseNotification,
            object: nil,
            userInfo: [Self.identifierKey: identifier]
        )
    }

    @objc private func handleShowResponse(_ notification: Notification) {
        guard
            let identifier = notification.userInfo?[Self.identifierKey] as? String
        else {
            return
        }

        receivedResponses.insert(identifier)
    }
}
