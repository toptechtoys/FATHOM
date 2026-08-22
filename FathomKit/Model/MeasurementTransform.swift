import Foundation

public extension Measurement {
    /// Transforms a measured value while preserving which of the three states
    /// it is in.
    ///
    /// This is deliberately not a convenience accessor: it never collapses the
    /// three states, never returns an optional, and never invents a value for a
    /// reading macOS did not publish. `notPublished` keeps its reason and
    /// `notAttributable` transforms both halves, so a caller converting bytes
    /// to gigabytes cannot accidentally lose the fact that 0.9 GB of the total
    /// is unattributed.
    func map<Other>(
        _ transform: (Value) -> Other
    ) -> Measurement<Other> {
        switch self {
        case let .known(value, source):
            .known(transform(value), source: source)
        case let .notPublished(reason):
            .notPublished(reason: reason)
        case let .notAttributable(measured, explained):
            .notAttributable(
                measured: transform(measured),
                explained: transform(explained)
            )
        }
    }

    /// Combines two measurements into one, keeping the weakest state of the
    /// pair.
    ///
    /// A ratio of a published numerator to an unpublished denominator is not a
    /// ratio, it is a guess — so if either side is unpublished the result is
    /// unpublished, and the surviving reason says which side was missing. If
    /// either side is unattributed the result is too, because a total built on
    /// an unattributed part inherits the gap.
    func combined<Other, Result>(
        with other: Measurement<Other>,
        _ transform: (Value, Other) -> Result
    ) -> Measurement<Result> {
        switch (self, other) {
        case let (.known(a, source), .known(b, _)):
            .known(transform(a, b), source: source)
        case let (.notPublished(reason), _):
            .notPublished(reason: reason)
        case let (_, .notPublished(reason)):
            .notPublished(reason: reason)
        case let (.notAttributable(measuredA, explainedA), .known(b, _)):
            .notAttributable(
                measured: transform(measuredA, b),
                explained: transform(explainedA, b)
            )
        case let (.known(a, _), .notAttributable(measuredB, explainedB)):
            .notAttributable(
                measured: transform(a, measuredB),
                explained: transform(a, explainedB)
            )
        case let (
            .notAttributable(measuredA, explainedA),
            .notAttributable(measuredB, explainedB)
        ):
            .notAttributable(
                measured: transform(measuredA, measuredB),
                explained: transform(explainedA, explainedB)
            )
        }
    }
}

public extension MemorySnapshot {
    /// How much of physical memory is in use, 0 to 1.
    ///
    /// Unpublished if either half is unpublished: a fraction of an unknown
    /// total is not a fraction.
    var usedFraction: Measurement<Double> {
        totalBytes.combined(with: freeBytes) { total, free in
            guard total > 0 else { return 0 }
            return Double(total - min(free, total)) / Double(total)
        }
    }
}

public extension NetworkSnapshot {
    /// Bytes per second received across every active interface.
    ///
    /// Unpublished when the interface list is, rather than reporting zero —
    /// which would draw a flat line at the bottom of the chart and read as
    /// *no traffic* rather than *no reading*.
    var totalThroughput: Measurement<Double> {
        interfaces.map { list in
            list.reduce(0.0) { running, interface in
                guard case let .known(rate, _) = interface.receivedBytesPerSecond
                else { return running }
                return running + rate
            }
        }
    }
}
