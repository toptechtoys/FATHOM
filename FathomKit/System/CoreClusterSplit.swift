import Foundation

/// Which reported cores belong to which cluster.
///
/// `host_processor_info` returns one entry per logical CPU and does not say
/// which cluster each belongs to. The split has to be derived from
/// `hw.perflevel0.logicalcpu` — the **performance** count — and the order the
/// cores arrive in.
///
/// Apple silicon reports **efficiency cores first**: the reference machine's
/// per-core load reads `E1–E4, P1–P8`, recorded in `FATHOM-DATA-SOURCES.md`.
/// So the boundary is the *efficiency* count, which is total minus performance,
/// and not the performance count itself. Using the performance count directly
/// puts the boundary at the wrong end and labels every core backwards.
///
/// This lives in FathomKit rather than beside the chart because it makes a
/// claim: it asserts that core five is a performance core. Getting that
/// backwards is the single most common bug in Mac monitors, and this project
/// has already made it once — in the prototype, corrected only when the
/// reference machine disagreed.
public struct CoreClusterSplit: Sendable, Equatable {
    /// How many cores were reported.
    public let total: Int
    /// How many of them are performance cores, from `hw.perflevel0.logicalcpu`.
    public let performance: Int

    public var efficiency: Int { total - performance }

    /// `nil` when the split cannot be trusted, in which case a caller labels
    /// cores by index alone rather than guessing which cluster they are in.
    public init?(total: Int, performance: Int) {
        // A performance count larger than the number of cores reported means
        // the two readings disagree. Rather than clamping — which would
        // silently produce a plausible split — the split refuses to exist.
        guard total > 0, performance >= 0, performance <= total else {
            return nil
        }
        self.total = total
        self.performance = performance
    }

    /// True when the core at this index is a performance core.
    public func isPerformance(index: Int) -> Bool {
        guard index >= 0, index < total else { return false }
        return index >= efficiency
    }

    /// The label for a core: `E1…En` then `P1…Pn`, matching how the reference
    /// machine reports them and how the prototype draws them.
    public func label(index: Int) -> String? {
        guard index >= 0, index < total else { return nil }
        return isPerformance(index: index)
            ? "P\(index - efficiency + 1)"
            : "E\(index + 1)"
    }
}
