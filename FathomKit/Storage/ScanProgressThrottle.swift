import Foundation

/// What a running scan can say about itself, between phase messages.
public struct LiveScanProgress: Sendable, Equatable {
    public let currentDirectory: String
    public let entryCount: UInt64
    public let bytesOnDisk: UInt64

    public init(
        currentDirectory: String,
        entryCount: UInt64,
        bytesOnDisk: UInt64
    ) {
        self.currentDirectory = currentDirectory
        self.entryCount = entryCount
        self.bytesOnDisk = bytesOnDisk
    }
}

/// Turns millions of walk callbacks into a readout a person can follow.
public struct ScanProgressThrottle: Sendable {
    private let interval: TimeInterval
    private let home: String
    private var entryCount: UInt64 = 0
    private var bytesOnDisk: UInt64 = 0
    private var lastPublishedAt: Date?

    public init(
        interval: TimeInterval = 0.1,
        home: String = FileManager.default
            .homeDirectoryForCurrentUser.path
    ) {
        self.interval = interval
        self.home = home
    }

    /// The data volume's firmlinked path, where a walk that starts at the
    /// volume root actually meets the home directory. `/Users/me` and
    /// `/System/Volumes/Data/Users/me` are one directory with one inode.
    private static let dataVolumePrefix = "/System/Volumes/Data"

    /// A walk spends most of its time deep under the home directory, and the
    /// absolute path is too long to read at a glance. `~` is what the owner
    /// would have written anyway.
    private func abbreviate(_ directory: String) -> String {
        guard !home.isEmpty else { return directory }
        for root in [home, Self.dataVolumePrefix + home] {
            if directory == root { return "~" }
            if directory.hasPrefix(root + "/") {
                return "~" + directory.dropFirst(root.count)
            }
        }
        return directory
    }

    public mutating func accumulate(
        path: String,
        isDirectory: Bool = false,
        bytesOnDisk newBytes: UInt64?,
        now: Date
    ) -> LiveScanProgress? {
        entryCount += 1
        if let newBytes {
            bytesOnDisk += newBytes
        }
        if let lastPublishedAt,
           now.timeIntervalSince(lastPublishedAt) < interval {
            return nil
        }
        lastPublishedAt = now
        let directory = isDirectory
            ? path
            : (path as NSString).deletingLastPathComponent
        return LiveScanProgress(
            currentDirectory: abbreviate(directory),
            entryCount: entryCount,
            bytesOnDisk: bytesOnDisk
        )
    }
}
