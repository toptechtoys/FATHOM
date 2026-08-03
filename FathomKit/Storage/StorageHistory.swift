import Darwin
import Foundation

public struct StorageHistorySample: Sendable, Equatable, Codable, Identifiable {
    public let wallTimestamp: Date
    public let monotonicTicks: UInt64
    public let volumePath: String
    public let actuallyFree: Measurement<UInt64>
    public let sizeOnDisk: Measurement<UInt64>
    public let freedIfDeleted: Measurement<UInt64>
    public let purgeable: Measurement<UInt64>
    public let topLevel: [StorageHistoryNode]?

    public var id: String {
        "\(volumePath):\(wallTimestamp.timeIntervalSince1970):\(monotonicTicks)"
    }

    public init(
        wallTimestamp: Date = Date(),
        monotonicTicks: UInt64 = mach_absolute_time(),
        volumePath: String,
        actuallyFree: Measurement<UInt64>,
        sizeOnDisk: Measurement<UInt64>,
        freedIfDeleted: Measurement<UInt64>,
        purgeable: Measurement<UInt64>,
        topLevel: [StorageHistoryNode]? = nil
    ) {
        self.wallTimestamp = wallTimestamp
        self.monotonicTicks = monotonicTicks
        self.volumePath = volumePath
        self.actuallyFree = actuallyFree
        self.sizeOnDisk = sizeOnDisk
        self.freedIfDeleted = freedIfDeleted
        self.purgeable = purgeable
        self.topLevel = topLevel
    }
}

public struct StorageHistoryNode: Sendable, Equatable, Codable, Identifiable {
    public let path: String
    public let name: String
    public let sizeOnDisk: Measurement<UInt64>
    public let freedIfDeleted: Measurement<UInt64>

    public var id: String { path }

    public init(
        path: String,
        name: String,
        sizeOnDisk: Measurement<UInt64>,
        freedIfDeleted: Measurement<UInt64>
    ) {
        self.path = path
        self.name = name
        self.sizeOnDisk = sizeOnDisk
        self.freedIfDeleted = freedIfDeleted
    }
}

public struct StorageHistoryDelta: Sendable, Equatable {
    public let actuallyFree: Measurement<Int64>
    public let sizeOnDisk: Measurement<Int64>
    public let freedIfDeleted: Measurement<Int64>
    public let purgeable: Measurement<Int64>
    public let topLevel: Measurement<[StorageHistoryNodeDelta]>
}

public struct StorageHistoryNodeDelta: Sendable, Equatable, Identifiable {
    public let path: String
    public let name: String
    public let sizeOnDisk: Measurement<Int64>
    public let freedIfDeleted: Measurement<Int64>

    public var id: String { path }
}

public enum StorageHistoryComparison {
    public static func compare(
        from start: StorageHistorySample,
        to end: StorageHistorySample
    ) -> StorageHistoryDelta {
        StorageHistoryDelta(
            actuallyFree: delta(start.actuallyFree, end.actuallyFree),
            sizeOnDisk: delta(start.sizeOnDisk, end.sizeOnDisk),
            freedIfDeleted: delta(
                start.freedIfDeleted,
                end.freedIfDeleted
            ),
            purgeable: delta(start.purgeable, end.purgeable),
            topLevel: topLevelDelta(start.topLevel, end.topLevel)
        )
    }

    static func delta(
        _ start: Measurement<UInt64>,
        _ end: Measurement<UInt64>
    ) -> Measurement<Int64> {
        switch (start, end) {
        case let (.known(first, _), .known(last, _)):
            guard first <= UInt64(Int64.max),
                  last <= UInt64(Int64.max) else {
                return .notPublished(
                    reason: "The history delta exceeds Int64"
                )
            }
            return .known(
                Int64(last) - Int64(first),
                source: .persistedStorageHistoryDelta
            )
        case let (.notPublished(reason), _),
             let (_, .notPublished(reason)):
            return .notPublished(reason: reason)
        case (.notAttributable, _), (_, .notAttributable):
            return .notPublished(
                reason: "One history endpoint is not attributable"
            )
        }
    }

    private static func topLevelDelta(
        _ start: [StorageHistoryNode]?,
        _ end: [StorageHistoryNode]?
    ) -> Measurement<[StorageHistoryNodeDelta]> {
        guard let start, let end else {
            return .notPublished(
                reason: "Top-level rollups were not stored for both scans"
            )
        }
        let first = Dictionary(uniqueKeysWithValues: start.map { ($0.path, $0) })
        let last = Dictionary(uniqueKeysWithValues: end.map { ($0.path, $0) })
        let paths = Set(first.keys).union(last.keys)
        let rows = paths.map { path in
            let name = last[path]?.name ?? first[path]?.name ?? path
            return StorageHistoryNodeDelta(
                path: path,
                name: name,
                sizeOnDisk: nodeDelta(
                    first[path]?.sizeOnDisk,
                    last[path]?.sizeOnDisk
                ),
                freedIfDeleted: nodeDelta(
                    first[path]?.freedIfDeleted,
                    last[path]?.freedIfDeleted
                )
            )
        }.sorted { left, right in
            magnitude(left.sizeOnDisk) > magnitude(right.sizeOnDisk)
        }
        return .known(rows, source: .persistedStorageHistoryDelta)
    }

    private static func nodeDelta(
        _ start: Measurement<UInt64>?,
        _ end: Measurement<UInt64>?
    ) -> Measurement<Int64> {
        if start == nil, case let .known(value, _)? = end,
           value <= UInt64(Int64.max) {
            return .known(Int64(value), source: .persistedStorageHistoryDelta)
        }
        if end == nil, case let .known(value, _)? = start,
           value <= UInt64(Int64.max) {
            return .known(-Int64(value), source: .persistedStorageHistoryDelta)
        }
        guard let start, let end else {
            return .notPublished(
                reason: "A top-level endpoint is not published"
            )
        }
        return delta(start, end)
    }

    private static func magnitude(
        _ measurement: Measurement<Int64>
    ) -> UInt64 {
        guard case let .known(value, _) = measurement else { return 0 }
        return value.magnitude
    }
}

public struct StorageHistoryGap: Sendable, Equatable {
    public let duration: TimeInterval

    public init(duration: TimeInterval) {
        self.duration = max(0, duration)
    }
}

public enum StorageHistoryClock {
    /// Finds wall time for which the monotonic clock did not advance. A
    /// backwards stamp also means continuity was interrupted, such as reboot.
    public static func gap(
        from earlier: StorageHistorySample,
        to later: StorageHistorySample,
        tolerance: TimeInterval = 5
    ) -> StorageHistoryGap? {
        let wallDelta = later.wallTimestamp.timeIntervalSince(
            earlier.wallTimestamp
        )
        guard wallDelta > 0 else { return nil }
        guard later.monotonicTicks >= earlier.monotonicTicks else {
            return StorageHistoryGap(duration: wallDelta)
        }
        var timebase = mach_timebase_info_data_t()
        guard mach_timebase_info(&timebase) == KERN_SUCCESS,
              timebase.denom != 0 else {
            return StorageHistoryGap(duration: wallDelta)
        }
        let ticks = later.monotonicTicks - earlier.monotonicTicks
        let monotonicDelta = Double(ticks) * Double(timebase.numer) /
            Double(timebase.denom) / 1_000_000_000
        let missing = wallDelta - monotonicDelta
        return missing > tolerance ? StorageHistoryGap(duration: missing) : nil
    }
}
