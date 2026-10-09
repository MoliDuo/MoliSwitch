import Foundation
import MoliSwitchCore

#if canImport(Darwin)
    import Darwin
#else
    import Glibc
#endif

/// Non-blocking advisory lock that keeps a single running instance of the app.
///
/// The lock file is intentionally never deleted: the file descriptor stays open
/// for the whole process lifetime and the operating system releases the lock when
/// the process exits. Deleting the file would let two processes hold what looks
/// like the same lock.
final class SingleInstanceLock {
    enum LockFailure: Error, CustomStringConvertible {
        case unableToCreateDirectory(URL, Error)
        case unableToOpenFile(URL, Int32)

        var description: String {
            switch self {
            case let .unableToCreateDirectory(url, error):
                return "无法创建应用支持目录 " + url.path + "：" + error.localizedDescription
            case let .unableToOpenFile(url, code):
                return "无法打开单实例锁文件 " + url.path + "（错误码 " + String(code) + "）"
            }
        }
    }

    let url: URL

    private var fileDescriptor: Int32 = -1

    init(url: URL) {
        self.url = url
    }

    static func applicationSupportLock(
        appName: String = "MoliSwitch"
    ) -> SingleInstanceLock {
        SingleInstanceLock(
            url: JSONRuleStore.applicationSupportDirectory(appName: appName)
                .appendingPathComponent("instance.lock")
        )
    }

    var isHeld: Bool {
        fileDescriptor >= 0
    }

    /// Tries to take the lock without blocking.
    /// - Returns: true when this process is the only instance.
    @discardableResult
    func acquire() throws -> Bool {
        guard fileDescriptor < 0 else {
            return true
        }

        let directory = url.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        } catch {
            throw LockFailure.unableToCreateDirectory(directory, error)
        }

        let descriptor = open(url.path, O_CREAT | O_RDWR, 0o644)
        guard descriptor >= 0 else {
            throw LockFailure.unableToOpenFile(url, errno)
        }

        if flock(descriptor, LOCK_EX | LOCK_NB) != 0 {
            close(descriptor)
            return false
        }

        fileDescriptor = descriptor
        return true
    }

    func release() {
        guard fileDescriptor >= 0 else {
            return
        }

        flock(fileDescriptor, LOCK_UN)
        close(fileDescriptor)
        fileDescriptor = -1
    }

    deinit {
        if fileDescriptor >= 0 {
            close(fileDescriptor)
        }
    }
}
