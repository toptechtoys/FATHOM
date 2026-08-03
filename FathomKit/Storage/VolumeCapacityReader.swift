import Darwin
import Foundation

public struct VolumeCapacitySnapshot: Sendable, Equatable {
    public let actuallyFree: Measurement<UInt64>
    public let finderAvailable: Measurement<UInt64>
    public let purgeable: Measurement<UInt64>

    public init(
        actuallyFree: Measurement<UInt64>,
        finderAvailable: Measurement<UInt64>,
        purgeable: Measurement<UInt64>
    ) {
        self.actuallyFree = actuallyFree
        self.finderAvailable = finderAvailable
        self.purgeable = purgeable
    }
}

public struct VolumeCapacityReader: Sendable {
    public init() {}

    public func read(volumeURL: URL) -> VolumeCapacitySnapshot {
        let actuallyFree = importantUsageCapacity(volumeURL: volumeURL)
        let finderAvailable = statfsCapacity(volumeURL: volumeURL)
        let purgeable: Measurement<UInt64>
        switch (actuallyFree, finderAvailable) {
        case let (.known(important, _), .known(finder, _)):
            if finder >= important {
                purgeable = .known(
                    finder - important,
                    source: .derivedPurgeableCapacity
                )
            } else {
                purgeable = .notPublished(
                    reason: "The two capacity APIs changed during the read"
                )
            }
        case let (.notPublished(reason), _),
             let (_, .notPublished(reason)):
            purgeable = .notPublished(reason: reason)
        case (.notAttributable, _):
            purgeable = .notPublished(
                reason: "Important-usage capacity is not attributable"
            )
        case (_, .notAttributable):
            purgeable = .notPublished(
                reason: "Finder capacity is not attributable"
            )
        }
        return VolumeCapacitySnapshot(
            actuallyFree: actuallyFree,
            finderAvailable: finderAvailable,
            purgeable: purgeable
        )
    }

    private func importantUsageCapacity(
        volumeURL: URL
    ) -> Measurement<UInt64> {
        do {
            let values = try volumeURL.resourceValues(
                forKeys: [.volumeAvailableCapacityForImportantUsageKey]
            )
            guard
                let bytes = values.volumeAvailableCapacityForImportantUsage,
                bytes >= 0
            else {
                return .notPublished(
                    reason: "macOS did not publish important-usage capacity"
                )
            }
            return .known(
                UInt64(bytes),
                source: .volumeAvailableCapacityForImportantUsage
            )
        } catch {
            return .notPublished(
                reason: "Important-usage capacity read failed: \(error)"
            )
        }
    }

    private func statfsCapacity(
        volumeURL: URL
    ) -> Measurement<UInt64> {
        var statistics = statfs()
        let result = volumeURL.withUnsafeFileSystemRepresentation { path in
            guard let path else {
                return Int32(-1)
            }
            return statfs(path, &statistics)
        }
        guard result == 0 else {
            return .notPublished(
                reason: "statfs(2) failed with errno \(errno)"
            )
        }
        let blocks = UInt64(statistics.f_bavail)
        let blockSize = UInt64(statistics.f_bsize)
        let (bytes, overflow) = blocks.multipliedReportingOverflow(
            by: blockSize
        )
        guard !overflow else {
            return .notPublished(
                reason: "Finder-style available capacity overflowed"
            )
        }
        return .known(bytes, source: .statfsAvailableCapacity)
    }
}
