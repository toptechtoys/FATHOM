import CFathomHardware
import Foundation

public struct DiskThroughputSnapshot: Sendable, Equatable {
    public let bytesRead: UInt64
    public let bytesWritten: UInt64
    public let readBytesPerSecond: Measurement<Double>
    public let writtenBytesPerSecond: Measurement<Double>
    public let driverCount: UInt32

    public init(
        bytesRead: UInt64,
        bytesWritten: UInt64,
        readBytesPerSecond: Measurement<Double>,
        writtenBytesPerSecond: Measurement<Double>,
        driverCount: UInt32
    ) {
        self.bytesRead = bytesRead
        self.bytesWritten = bytesWritten
        self.readBytesPerSecond = readBytesPerSecond
        self.writtenBytesPerSecond = writtenBytesPerSecond
        self.driverCount = driverCount
    }
}

public actor DiskThroughputSampler {
    private var previous: (
        time: ContinuousClock.Instant,
        read: UInt64,
        written: UInt64
    )?
    private let clock = ContinuousClock()

    public init() {}

    public func sample() -> Measurement<DiskThroughputSnapshot> {
        var raw = fathom_disk_counters()
        var errorCode: Int32 = 0
        guard fathom_disk_read_counters(&raw, &errorCode) == 0 else {
            return .notPublished(
                reason: "IOBlockStorageDriver statistics are unavailable (IOReturn \(errorCode))"
            )
        }
        let now = clock.now
        let elapsed = previous.map {
            let duration = $0.time.duration(to: now).components
            return Double(duration.seconds) +
                Double(duration.attoseconds) / 1e18
        }
        let readRate = Self.rate(
            previous: previous?.read,
            current: raw.bytes_read,
            elapsed: elapsed
        )
        let writeRate = Self.rate(
            previous: previous?.written,
            current: raw.bytes_written,
            elapsed: elapsed
        )
        previous = (now, raw.bytes_read, raw.bytes_written)
        return .known(
            DiskThroughputSnapshot(
                bytesRead: raw.bytes_read,
                bytesWritten: raw.bytes_written,
                readBytesPerSecond: readRate,
                writtenBytesPerSecond: writeRate,
                driverCount: raw.drivers_publishing_statistics
            ),
            source: .ioBlockStorageDriverStatistics
        )
    }

    static func rate(
        previous: UInt64?,
        current: UInt64,
        elapsed: Double?
    ) -> Measurement<Double> {
        guard let previous, let elapsed, elapsed > 0 else {
            return .notPublished(reason: "A second disk counter sample is required")
        }
        guard current >= previous else {
            return .notPublished(reason: "A disk byte counter reset")
        }
        return .known(
            Double(current - previous) / elapsed,
            source: .ioBlockStorageDriverStatistics
        )
    }
}
