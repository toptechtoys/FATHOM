import Darwin
import Foundation

/// This process's own CPU consumption.
///
/// FATHOM claims an idle cost in its own chrome, and rule 8 in `AGENTS.md`
/// makes that a shipped number rather than a target. A number the app asserts
/// about itself and never measures is exactly the kind of claim this product
/// exists to refuse, so it measures it.
///
/// `proc_pid_rusage` reports cumulative user and system time for the calling
/// process. A percentage needs two samples and the wall time between them —
/// one reading alone is a total, not a rate, which is why `sample()` returns
/// the counter and `ProcessCPUSampler` owns the delta.
public struct ProcessResourceSample: Sendable, Equatable {
    /// Cumulative CPU nanoseconds since the process started.
    public let cpuNanoseconds: UInt64
    /// Mach absolute time when this was read, for the wall-clock denominator.
    public let timestamp: UInt64

    public init(cpuNanoseconds: UInt64, timestamp: UInt64) {
        self.cpuNanoseconds = cpuNanoseconds
        self.timestamp = timestamp
    }
}

public struct ProcessResourceReader: Sendable {
    public init() {}

    public func read() -> Measurement<ProcessResourceSample> {
        var usage = rusage_info_current()
        let result = withUnsafeMutablePointer(to: &usage) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(getpid(), RUSAGE_INFO_CURRENT, $0)
            }
        }
        guard result == 0 else {
            return .notPublished(
                reason: "proc_pid_rusage did not publish resource usage for this process (errno \(errno))"
            )
        }
        let cpu = usage.ri_user_time &+ usage.ri_system_time
        return .known(
            ProcessResourceSample(
                cpuNanoseconds: cpu,
                timestamp: mach_absolute_time()
            ),
            source: .procPidRusage
        )
    }
}

/// Turns two resource samples into a percentage of one core.
///
/// Deliberately not an average of everything since launch: the idle cost is
/// what the widget costs *while idle*, and a lifetime average is dominated by
/// whatever the process did at startup. Each call reports the interval since
/// the previous one.
public actor ProcessCPUSampler {
    private let reader: ProcessResourceReader
    private var previous: ProcessResourceSample?
    private let nanosecondsPerTick: Double

    public init(reader: ProcessResourceReader = ProcessResourceReader()) {
        self.reader = reader
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        nanosecondsPerTick = info.denom > 0
            ? Double(info.numer) / Double(info.denom)
            : 1
    }

    /// Percentage of one core used since the previous call.
    ///
    /// The first call establishes a baseline and reports not-published rather
    /// than a figure: there is no interval to divide by yet, and reporting the
    /// lifetime average in its place would answer a different question.
    public func sample() -> Measurement<Double> {
        switch reader.read() {
        case let .known(current, source):
            defer { previous = current }
            guard let previous else {
                return .notPublished(
                    reason: "A percentage needs two samples. This is the first."
                )
            }
            let elapsedTicks = current.timestamp &- previous.timestamp
            let elapsedNanoseconds = Double(elapsedTicks) * nanosecondsPerTick
            guard elapsedNanoseconds > 0 else {
                return .notPublished(
                    reason: "No wall-clock time elapsed between samples."
                )
            }
            // Saturating rather than wrapping: a counter that went backwards is
            // a reading we cannot use, not a negative percentage.
            guard current.cpuNanoseconds >= previous.cpuNanoseconds else {
                return .notPublished(
                    reason: "The CPU counter moved backwards between samples."
                )
            }
            let cpuNanoseconds = Double(
                current.cpuNanoseconds - previous.cpuNanoseconds
            )
            return .known(cpuNanoseconds / elapsedNanoseconds * 100, source: source)
        case let .notPublished(reason):
            return .notPublished(reason: reason)
        case .notAttributable:
            return .notPublished(
                reason: "Process resource usage is not attributable."
            )
        }
    }

    /// Percentage-of-one-core from two samples, without touching the actor's
    /// own state. Exposed so the arithmetic is testable without a live process.
    public nonisolated static func percentage(
        from previous: ProcessResourceSample,
        to current: ProcessResourceSample,
        nanosecondsPerTick: Double
    ) -> Measurement<Double> {
        let elapsed = Double(current.timestamp &- previous.timestamp)
            * nanosecondsPerTick
        guard elapsed > 0 else {
            return .notPublished(
                reason: "No wall-clock time elapsed between samples."
            )
        }
        guard current.cpuNanoseconds >= previous.cpuNanoseconds else {
            return .notPublished(
                reason: "The CPU counter moved backwards between samples."
            )
        }
        let cpu = Double(current.cpuNanoseconds - previous.cpuNanoseconds)
        return .known(cpu / elapsed * 100, source: .procPidRusage)
    }
}

/// What the release gate checks the measured figure against.
///
/// The budget lives here rather than in a script so the thresholds, the
/// measurement and the test all read the same numbers. `AGENTS.md` rule 8 is
/// the source: at most 0.2% CPU with four items, and 0.5% blocks the release.
public enum IdleCostBudget: Sendable {
    /// The figure FATHOM is willing to print about itself.
    public static let targetCPUPercent = 0.2
    /// Past this, the release does not ship.
    public static let blockingCPUPercent = 0.5

    public enum Verdict: Sendable, Equatable {
        case withinTarget
        case overTargetWithinBlocking
        case blocking
    }

    public static func verdict(forCPUPercent percent: Double) -> Verdict {
        if percent <= targetCPUPercent { return .withinTarget }
        if percent < blockingCPUPercent { return .overTargetWithinBlocking }
        return .blocking
    }
}
