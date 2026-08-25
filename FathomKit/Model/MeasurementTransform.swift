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

public extension Measurement where Value == UInt64 {
    /// Sums byte measurements without collapsing what any of them said.
    ///
    /// This is the one way to total a list of readings. The alternatives are
    /// the two collapses the contract bans: skipping the rows that did not
    /// publish, which yields a smaller number wearing the total's label, and
    /// `notAttributable(measured: sum, explained: sum)`, which asserts the gap
    /// is exactly zero — the opposite of the fact being reported.
    ///
    /// The rules, weakest state first:
    /// - Any `notPublished` part makes the total not published, and the reason
    ///   counts the missing parts rather than repeating one of their reasons.
    /// - Otherwise, any `notAttributable` part makes the total unattributed,
    ///   and **both halves are real sums**: a known value contributes itself
    ///   to each half, so the gap keeps its true magnitude.
    /// - Otherwise the total is known, with the provenance the caller states.
    /// - A sum that overflows `UInt64` is not a byte count; it comes back
    ///   not published saying so, never wrapped or clamped.
    static func sum(
        _ values: [Measurement<UInt64>],
        source: DataSource,
        missing: (_ count: Int, _ of: Int) -> String = {
            "\($0) of \($1) items did not publish a size."
        }
    ) -> Measurement<UInt64> {
        var measuredTotal: UInt64 = 0
        var explainedTotal: UInt64 = 0
        var notPublishedCount = 0
        var hasGap = false
        for value in values {
            let halves: (measured: UInt64, explained: UInt64)
            switch value {
            case let .known(bytes, _):
                halves = (bytes, bytes)
            case .notPublished:
                notPublishedCount += 1
                continue
            case let .notAttributable(measured, explained):
                hasGap = true
                halves = (measured, explained)
            }
            let (nextMeasured, overflowM) =
                measuredTotal.addingReportingOverflow(halves.measured)
            let (nextExplained, overflowE) =
                explainedTotal.addingReportingOverflow(halves.explained)
            guard !overflowM, !overflowE else {
                return .notPublished(
                    reason: "The sum of \(values.count) items is larger than "
                        + "a byte count can represent."
                )
            }
            measuredTotal = nextMeasured
            explainedTotal = nextExplained
        }
        guard notPublishedCount == 0 else {
            return .notPublished(
                reason: missing(notPublishedCount, values.count)
            )
        }
        guard !hasGap else {
            return .notAttributable(
                measured: measuredTotal,
                explained: explainedTotal
            )
        }
        return .known(measuredTotal, source: source)
    }
}

public extension Measurement {
    /// The measurement as words, with all three states sayable.
    ///
    /// For every place a measurement has to become a plain string — a dialog
    /// title, a row value, a spoken label — rather than a
    /// `MeasurementValueView`. Written once so that `notAttributable` cannot
    /// quietly borrow the words of a state it is not: it is neither a figure
    /// nor *not published*, and it reads as what it is, both halves stated.
    func described(_ format: (Value) -> String) -> String {
        switch self {
        case let .known(value, _):
            format(value)
        case .notPublished:
            "not published"
        case let .notAttributable(measured, explained):
            "\(format(measured)) measured · \(format(explained)) explained"
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
