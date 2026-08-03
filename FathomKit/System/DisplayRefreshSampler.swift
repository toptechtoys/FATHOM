import CFathomHardware
import Foundation

public enum DisplayRefreshSamplerError: Error, Sendable, Equatable {
    case unavailable(code: Int32)
}

public actor DisplayRefreshSampler {
    private let handle: DisplayRefreshHandle
    private let clock = ContinuousClock()
    private var previous: (count: UInt64, time: ContinuousClock.Instant)?

    public init() throws {
        var pointer: fathom_display_refresh_sampler?
        var errorCode: Int32 = 0
        guard fathom_display_refresh_sampler_create(
            &pointer,
            &errorCode
        ) == 0, let pointer else {
            throw DisplayRefreshSamplerError.unavailable(code: errorCode)
        }
        handle = DisplayRefreshHandle(pointer: pointer)
    }

    public func sample() -> Measurement<Double> {
        let current = fathom_display_refresh_sampler_count(handle.pointer)
        let now = clock.now
        defer { previous = (current, now) }
        guard let previous else {
            return .notPublished(
                reason: "A second display-link sample is required"
            )
        }
        let duration = previous.time.duration(to: now).components
        let elapsed = Double(duration.seconds) +
            Double(duration.attoseconds) / 1e18
        return Self.rate(
            previous: previous.count,
            current: current,
            elapsed: elapsed
        )
    }

    static func rate(
        previous: UInt64,
        current: UInt64,
        elapsed: Double
    ) -> Measurement<Double> {
        guard elapsed > 0 else {
            return .notPublished(reason: "The display sample interval is zero")
        }
        guard current >= previous else {
            return .notPublished(reason: "The display callback counter reset")
        }
        return .known(
            Double(current - previous) / elapsed,
            source: .cvDisplayLinkCallbackDelta
        )
    }
}

private final class DisplayRefreshHandle: @unchecked Sendable {
    let pointer: fathom_display_refresh_sampler

    init(pointer: fathom_display_refresh_sampler) {
        self.pointer = pointer
    }

    deinit {
        fathom_display_refresh_sampler_destroy(pointer)
    }
}
