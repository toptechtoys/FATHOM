import Foundation

public struct CloudEvictionPlan: Sendable, Equatable, Codable {
    public let createdAt: Date
    public let items: [CloudItemRecord]

    public init(createdAt: Date = Date(), items: [CloudItemRecord]) {
        self.createdAt = createdAt
        self.items = items
    }

    /// What eviction would free, with the three states intact.
    ///
    /// This used to be `knownFreeableBytes: UInt64?`, the optional-returning
    /// convenience accessor the contract bans: it collapsed *not published*,
    /// *not attributable* and an arithmetic overflow into one `nil`, and the
    /// views rendered every one of them as *not published* with a reason they
    /// invented on the spot.
    public var freeableBytes: Measurement<UInt64> {
        Measurement.sum(
            items.map(\.freedIfEvicted),
            source: .ubiquitousAllocatedSize
        ) { missing, count in
            "\(missing) of \(count) items in the plan did not publish "
                + "a freeable size."
        }
    }
}

public struct CloudEvictionOutcome: Sendable, Equatable, Codable {
    public let path: String
    public let evicted: Bool
    public let detail: String
}

public struct CloudEvictionEngine: Sendable {
    public init() {}

    public func dryRun(_ records: [CloudItemRecord]) -> CloudEvictionPlan {
        CloudEvictionPlan(
            items: records.filter {
                guard case let .known(bytes, _) = $0.freedIfEvicted else {
                    return false
                }
                return bytes > 0
            }
        )
    }

    public func execute(
        _ plan: CloudEvictionPlan,
        journalURL: URL
    ) -> [CloudEvictionOutcome] {
        plan.items.map { planned in
            guard let current = CloudItemReader().readItem(planned.url),
                  current == planned else {
                return CloudEvictionOutcome(
                    path: planned.url.path,
                    evicted: false,
                    detail: "Downloading, pin, or allocation state changed after dry run"
                )
            }
            do {
                try appendIntent(planned, journalURL: journalURL)
                try FileManager.default.evictUbiquitousItem(at: planned.url)
                do {
                    try appendRecord(
                        CloudJournalRecord(
                            timestamp: Date(),
                            phase: .outcome,
                            path: planned.url.path,
                            sizeOnDisk: planned.sizeOnDisk,
                            freedIfEvicted: planned.freedIfEvicted,
                            detail: "Local bytes evicted; the item remains in iCloud"
                        ),
                        journalURL: journalURL
                    )
                } catch {
                    return CloudEvictionOutcome(
                        path: planned.url.path,
                        evicted: true,
                        detail: "Local bytes were evicted, but the outcome journal failed: \(error)"
                    )
                }
                return CloudEvictionOutcome(
                    path: planned.url.path,
                    evicted: true,
                    detail: "Local bytes evicted; the item remains in iCloud"
                )
            } catch {
                return CloudEvictionOutcome(
                    path: planned.url.path,
                    evicted: false,
                    detail: "\(error)"
                )
            }
        }
    }

    private func appendIntent(
        _ item: CloudItemRecord,
        journalURL: URL
    ) throws {
        try appendRecord(
            CloudJournalRecord(
                timestamp: Date(),
                phase: .intent,
                path: item.url.path,
                sizeOnDisk: item.sizeOnDisk,
                freedIfEvicted: item.freedIfEvicted,
                detail: "Approved dry-run cloud state"
            ),
            journalURL: journalURL
        )
    }

    private func appendRecord(
        _ record: CloudJournalRecord,
        journalURL: URL
    ) throws {
        let directory = journalURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        if !FileManager.default.fileExists(atPath: journalURL.path) {
            guard FileManager.default.createFile(
                atPath: journalURL.path,
                contents: nil
            ) else { throw CocoaError(.fileWriteUnknown) }
        }
        var data = try JSONEncoder().encode(record)
        data.append(0x0A)
        let handle = try FileHandle(forWritingTo: journalURL)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
        try handle.synchronize()
    }
}

private struct CloudJournalRecord: Codable {
    enum Phase: String, Codable {
        case intent
        case outcome
    }

    let timestamp: Date
    let phase: Phase
    let path: String
    let sizeOnDisk: Measurement<UInt64>
    let freedIfEvicted: Measurement<UInt64>
    let detail: String
}
