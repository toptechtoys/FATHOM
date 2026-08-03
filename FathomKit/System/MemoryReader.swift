import CFathomHardware
import Darwin
import Foundation

public struct MemorySnapshot: Sendable, Equatable {
    public let totalBytes: Measurement<UInt64>
    public let freeBytes: Measurement<UInt64>
    public let activeBytes: Measurement<UInt64>
    public let inactiveBytes: Measurement<UInt64>
    public let speculativeBytes: Measurement<UInt64>
    public let wiredBytes: Measurement<UInt64>
    public let compressedBytes: Measurement<UInt64>
    public let purgeableBytes: Measurement<UInt64>
    public let swapUsedBytes: Measurement<UInt64>
    public let swapTotalBytes: Measurement<UInt64>

    public init(
        totalBytes: Measurement<UInt64>,
        freeBytes: Measurement<UInt64>,
        activeBytes: Measurement<UInt64>,
        inactiveBytes: Measurement<UInt64>,
        speculativeBytes: Measurement<UInt64>,
        wiredBytes: Measurement<UInt64>,
        compressedBytes: Measurement<UInt64>,
        purgeableBytes: Measurement<UInt64>,
        swapUsedBytes: Measurement<UInt64>,
        swapTotalBytes: Measurement<UInt64>
    ) {
        self.totalBytes = totalBytes
        self.freeBytes = freeBytes
        self.activeBytes = activeBytes
        self.inactiveBytes = inactiveBytes
        self.speculativeBytes = speculativeBytes
        self.wiredBytes = wiredBytes
        self.compressedBytes = compressedBytes
        self.purgeableBytes = purgeableBytes
        self.swapUsedBytes = swapUsedBytes
        self.swapTotalBytes = swapTotalBytes
    }
}

public struct MemoryReader: Sendable {
    public init() {}

    public func read() -> MemorySnapshot {
        var raw = fathom_memory_counters()
        var errorCode: Int32 = 0
        guard fathom_memory_read_counters(&raw, &errorCode) == 0 else {
            return Self.notPublished(
                reason: "Mach VM statistics failed with code \(errorCode)"
            )
        }
        func bytes(_ pages: UInt64) -> Measurement<UInt64> {
            let (value, overflow) = pages.multipliedReportingOverflow(
                by: raw.page_size
            )
            return overflow
                ? .notPublished(reason: "VM page count overflowed")
                : .known(value, source: .hostVMStatistics64)
        }
        return MemorySnapshot(
            totalBytes: Self.readPhysicalMemory(),
            freeBytes: bytes(raw.free_pages),
            activeBytes: bytes(raw.active_pages),
            inactiveBytes: bytes(raw.inactive_pages),
            speculativeBytes: bytes(raw.speculative_pages),
            wiredBytes: bytes(raw.wired_pages),
            compressedBytes: bytes(raw.compressed_pages),
            purgeableBytes: bytes(raw.purgeable_pages),
            swapUsedBytes: .known(
                raw.swap_used_bytes,
                source: .sysctlSwapUsage
            ),
            swapTotalBytes: .known(
                raw.swap_total_bytes,
                source: .sysctlSwapUsage
            )
        )
    }

    static func readPhysicalMemory() -> Measurement<UInt64> {
        var value: UInt64 = 0
        var size = MemoryLayout.size(ofValue: value)
        guard sysctlbyname("hw.memsize", &value, &size, nil, 0) == 0,
              size == MemoryLayout<UInt64>.size else {
            return .notPublished(
                reason: "sysctl hw.memsize did not publish physical memory"
            )
        }
        return .known(value, source: .sysctlPhysicalMemory)
    }

    private static func notPublished(reason: String) -> MemorySnapshot {
        MemorySnapshot(
            totalBytes: Self.readPhysicalMemory(),
            freeBytes: .notPublished(reason: reason),
            activeBytes: .notPublished(reason: reason),
            inactiveBytes: .notPublished(reason: reason),
            speculativeBytes: .notPublished(reason: reason),
            wiredBytes: .notPublished(reason: reason),
            compressedBytes: .notPublished(reason: reason),
            purgeableBytes: .notPublished(reason: reason),
            swapUsedBytes: .notPublished(reason: reason),
            swapTotalBytes: .notPublished(reason: reason)
        )
    }
}
