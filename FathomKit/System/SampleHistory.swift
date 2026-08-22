import Foundation

/// A fixed-length window of recent samples that remembers where it has none.
///
/// The sparklines draw sixty seconds at 1 Hz. The interesting part is not the
/// ring buffer, it is that a sample macOS did not publish is stored as a gap
/// rather than dropped or carried forward. Dropping it slides older samples
/// rightward and quietly redates them; carrying the last value forward draws a
/// flat line that looks like a measurement and is not one.
///
/// A chart that hides its own blind spots is worse than no chart, so a gap is
/// preserved here and the sparkline breaks its line across it.
public struct SampleHistory<Value: BinaryFloatingPoint & Sendable>: Sendable {
    /// How many samples the window holds. Sixty at 1 Hz is sixty seconds.
    public let capacity: Int

    /// One entry per elapsed interval, oldest first. `nil` is a gap.
    public private(set) var samples: [Value?]

    public init(capacity: Int = 60) {
        precondition(capacity > 0, "a history with no capacity records nothing")
        self.capacity = capacity
        samples = []
    }

    /// Records a reading, or a gap when the reading was not published.
    ///
    /// `notAttributable` records the measured figure: it is a real reading, and
    /// what cannot be attributed is which parts of the system produced it. The
    /// caller states that separately; the line itself is not a lie.
    public mutating func record(_ measurement: Measurement<Value>) {
        switch measurement {
        case let .known(value, _):
            append(value)
        case .notPublished:
            append(nil)
        case let .notAttributable(measured, _):
            append(measured)
        }
    }

    /// Records a reading directly, for values that are never unpublished.
    public mutating func record(_ value: Value) {
        append(value)
    }

    /// Records a gap without a measurement — a tick that produced no reading.
    public mutating func recordGap() {
        append(nil)
    }

    private mutating func append(_ value: Value?) {
        samples.append(value)
        if samples.count > capacity {
            samples.removeFirst(samples.count - capacity)
        }
    }

    /// True until the first reading or gap arrives.
    public var isEmpty: Bool { samples.isEmpty }

    /// The most recent reading, skipping trailing gaps.
    public var latest: Value? { samples.reversed().compactMap { $0 }.first }

    /// How many intervals produced no reading.
    public var gapCount: Int { samples.count { $0 == nil } }

    /// True when nothing in the window was published. A sparkline with no
    /// readings at all should say so rather than draw an empty box.
    public var isEntirelyGaps: Bool { !samples.isEmpty && gapCount == samples.count }

    /// The largest reading in the window, for scaling a chart that has no
    /// natural ceiling. `nil` when there is nothing to scale.
    public var peak: Value? { samples.compactMap { $0 }.max() }

    /// Contiguous runs of readings, oldest first, each with the index it starts
    /// at. A sparkline draws one polyline per run, so the line breaks at a gap
    /// instead of leaping across it.
    public var runs: [(start: Int, values: [Value])] {
        var result: [(start: Int, values: [Value])] = []
        var current: [Value] = []
        var start = 0
        for (index, sample) in samples.enumerated() {
            if let sample {
                if current.isEmpty { start = index }
                current.append(sample)
            } else if !current.isEmpty {
                result.append((start, current))
                current = []
            }
        }
        if !current.isEmpty { result.append((start, current)) }
        return result
    }
}
