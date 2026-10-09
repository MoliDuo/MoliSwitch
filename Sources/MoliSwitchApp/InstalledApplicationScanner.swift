import Foundation

struct ApplicationScanResult: Equatable, Sendable {
    let applications: [InstalledApplication]
    let failedRoots: [URL]
    /// Number of search roots that were attempted, used to tell a partial
    /// failure apart from a total one.
    let rootCount: Int

    static let empty = ApplicationScanResult(applications: [], failedRoots: [], rootCount: 0)

    var isTotalFailure: Bool {
        rootCount > 0 && failedRoots.count >= rootCount
    }

    var isPartialFailure: Bool {
        !failedRoots.isEmpty && !isTotalFailure
    }
}

struct InstalledApplicationScanner: ApplicationScanning {
    /// When nil, the standard macOS locations are used in priority order.
    private let explicitRoots: [URL]?

    init(roots: [URL]? = nil) {
        explicitRoots = roots
    }

    /// Search roots in priority order. When the same bundle identifier is
    /// installed in more than one place the earliest root wins.
    func searchRoots() -> [URL] {
        if let explicitRoots {
            return explicitRoots
        }

        var roots: [URL] = []

        if let userApplications = FileManager.default.urls(
            for: .applicationDirectory,
            in: .userDomainMask
        ).first {
            roots.append(userApplications)
        }

        roots.append(URL(fileURLWithPath: "/Applications", isDirectory: true))
        roots.append(URL(fileURLWithPath: "/System/Applications", isDirectory: true))
        // Deliberately the parent of /System/Library/CoreServices/Applications so
        // that the two CoreServices locations are never scanned twice.
        roots.append(URL(fileURLWithPath: "/System/Library/CoreServices", isDirectory: true))

        return roots
    }

    func scan() -> ApplicationScanResult {
        let roots = searchRoots()
        let personalRoot = FileManager.default.urls(
            for: .applicationDirectory,
            in: .userDomainMask
        ).first

        var applicationsByBundleIdentifier: [String: InstalledApplication] = [:]
        var failedRoots: [URL] = []

        for root in roots {
            if FileManager.default.fileExists(atPath: root.path) {
                let discovered = applications(in: root, failedRoots: &failedRoots)

                // Applications found in an earlier (higher priority) root are kept.
                for application in discovered
                    where applicationsByBundleIdentifier[application.bundleIdentifier] == nil
                {
                    applicationsByBundleIdentifier[application.bundleIdentifier] = application
                }
            } else if root != personalRoot {
                // The personal Applications folder is absent on most Macs; the
                // shared locations are expected to exist.
                failedRoots.append(root)
            }
        }

        let sorted = applicationsByBundleIdentifier.values.sorted { lhs, rhs in
            let comparison = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
            if comparison == .orderedSame {
                return lhs.bundleIdentifier < rhs.bundleIdentifier
            }
            return comparison == .orderedAscending
        }

        return ApplicationScanResult(
            applications: sorted,
            failedRoots: failedRoots,
            rootCount: roots.count
        )
    }

    private func applications(in root: URL, failedRoots: inout [URL]) -> [InstalledApplication] {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isPackageKey]
        var enumerationFailed = false

        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles],
            errorHandler: { _, _ in
                // A permission problem inside a root makes the result incomplete;
                // report the root instead of silently returning fewer apps.
                enumerationFailed = true
                return true
            }
        ) else {
            failedRoots.append(root)
            return []
        }

        var urls: [URL] = []
        for case let url as URL in enumerator where url.pathExtension == "app" {
            urls.append(url)
            enumerator.skipDescendants()
        }

        if enumerationFailed {
            failedRoots.append(root)
        }

        // Sort inside a root so that the winner of a duplicate bundle identifier
        // does not depend on directory enumeration order.
        return urls
            .sorted { $0.standardizedFileURL.path < $1.standardizedFileURL.path }
            .compactMap { application(at: $0) }
    }

    private func application(at url: URL) -> InstalledApplication? {
        guard
            let bundle = Bundle(url: url),
            let bundleIdentifier = bundle.bundleIdentifier,
            !bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            !Self.isBackgroundHelper(bundle)
        else {
            return nil
        }

        let name = [
            bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String,
            bundle.object(forInfoDictionaryKey: "CFBundleName") as? String,
        ]
        .compactMap { $0.map(Self.visibleName) }
        .first { !$0.isEmpty }
        ?? url.deletingPathExtension().lastPathComponent

        return InstalledApplication(
            name: name,
            bundleIdentifier: bundleIdentifier,
            url: url
        )
    }

    /// Background-only programs, and agents without a Dock icon that have no
    /// icon of their own, such as the system's MediaRemoteUI. Nobody types in
    /// them, so they only clutter the list.
    static func isBackgroundHelper(_ bundle: Bundle) -> Bool {
        if boolValue(bundle.object(forInfoDictionaryKey: "LSBackgroundOnly")) {
            return true
        }

        let hasIcon = ["CFBundleIconFile", "CFBundleIconName"].contains { key in
            (bundle.object(forInfoDictionaryKey: key) as? String).map { !visibleName($0).isEmpty } ?? false
        }
        return boolValue(bundle.object(forInfoDictionaryKey: "LSUIElement")) && !hasIcon
    }

    /// Info.plist booleans appear as real booleans, numbers or strings like "1".
    private static func boolValue(_ value: Any?) -> Bool {
        switch value {
        case let bool as Bool:
            return bool
        case let number as NSNumber:
            return number.boolValue
        case let string as String:
            return ["1", "true", "yes"].contains(string.lowercased())
        default:
            return false
        }
    }

    /// Removes whitespace and invisible format characters: some system bundles
    /// use a lone left-to-right mark as their display name.
    private static func visibleName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines.union(.controlCharacters))
    }
}
