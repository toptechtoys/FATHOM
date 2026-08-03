import CFathomHardware
import Darwin
import Foundation

public struct CPUCoreLoad: Sendable, Equatable, Identifiable {
    public let index: Int
    public let user: Double
    public let system: Double
    public let idle: Double
    public let nice: Double

    public var id: Int { index }
    public var busy: Double { user + system + nice }

    public init(
        index: Int,
        user: Double,
        system: Double,
        idle: Double,
        nice: Double
    ) {
        self.index = index
        self.user = user
        self.system = system
        self.idle = idle
        self.nice = nice
    }
}

public struct CPULoadSnapshot: Sendable, Equatable {
    public let cores: Measurement<[CPUCoreLoad]>
    public let aggregateBusy: Measurement<Double>
    public let aggregateUser: Measurement<Double>
    public let aggregateSystem: Measurement<Double>
    public let aggregateIdle: Measurement<Double>
    public let loadAverages: Measurement<[Double]>
    public let performanceLogicalCPUCount: Measurement<UInt64>
    public let efficiencyLogicalCPUCount: Measurement<UInt64>

    public init(
        cores: Measurement<[CPUCoreLoad]>,
        aggregateBusy: Measurement<Double>,
        aggregateUser: Measurement<Double>,
        aggregateSystem: Measurement<Double>,
        aggregateIdle: Measurement<Double>,
        loadAverages: Measurement<[Double]>,
        performanceLogicalCPUCount: Measurement<UInt64>,
        efficiencyLogicalCPUCount: Measurement<UInt64>
    ) {
        self.cores = cores
        self.aggregateBusy = aggregateBusy
        self.aggregateUser = aggregateUser
        self.aggregateSystem = aggregateSystem
        self.aggregateIdle = aggregateIdle
        self.loadAverages = loadAverages
        self.performanceLogicalCPUCount = performanceLogicalCPUCount
        self.efficiencyLogicalCPUCount = efficiencyLogicalCPUCount
    }
}

public actor CPUSampler {
    private var previous: CPUTickSnapshot?

    public init() {}

    public func sample() -> CPULoadSnapshot {
        let topology = CPUTopologyReader().read()
        let loadAverages = CPULoadAverageReader.read()
        let current: CPUTickSnapshot
        do {
            current = try CPUTickReader().read()
        } catch {
            let reason = "CPU tick read failed: \(error)"
            return CPULoadSnapshot(
                cores: .notPublished(reason: reason),
                aggregateBusy: .notPublished(reason: reason),
                aggregateUser: .notPublished(reason: reason),
                aggregateSystem: .notPublished(reason: reason),
                aggregateIdle: .notPublished(reason: reason),
                loadAverages: loadAverages,
                performanceLogicalCPUCount:
                    topology.performanceLogicalCPUCount,
                efficiencyLogicalCPUCount:
                    topology.efficiencyLogicalCPUCount
            )
        }
        guard let prior = previous else {
            previous = current
            let reason = "A second CPU tick sample is required"
            return CPULoadSnapshot(
                cores: .notPublished(reason: reason),
                aggregateBusy: .notPublished(reason: reason),
                aggregateUser: .notPublished(reason: reason),
                aggregateSystem: .notPublished(reason: reason),
                aggregateIdle: .notPublished(reason: reason),
                loadAverages: loadAverages,
                performanceLogicalCPUCount:
                    topology.performanceLogicalCPUCount,
                efficiencyLogicalCPUCount:
                    topology.efficiencyLogicalCPUCount
            )
        }
        previous = current
        let loads = Self.loads(previous: prior, current: current)
        guard !loads.isEmpty else {
            let reason = "CPU topology changed between samples"
            return CPULoadSnapshot(
                cores: .notPublished(reason: reason),
                aggregateBusy: .notPublished(reason: reason),
                aggregateUser: .notPublished(reason: reason),
                aggregateSystem: .notPublished(reason: reason),
                aggregateIdle: .notPublished(reason: reason),
                loadAverages: loadAverages,
                performanceLogicalCPUCount:
                    topology.performanceLogicalCPUCount,
                efficiencyLogicalCPUCount:
                    topology.efficiencyLogicalCPUCount
            )
        }
        guard let aggregate = Self.aggregate(
            previous: prior,
            current: current
        ) else {
            let reason = "CPU tick totals did not advance"
            return CPULoadSnapshot(
                cores: .known(loads, source: .hostProcessorLoadInfo),
                aggregateBusy: .notPublished(reason: reason),
                aggregateUser: .notPublished(reason: reason),
                aggregateSystem: .notPublished(reason: reason),
                aggregateIdle: .notPublished(reason: reason),
                loadAverages: loadAverages,
                performanceLogicalCPUCount:
                    topology.performanceLogicalCPUCount,
                efficiencyLogicalCPUCount:
                    topology.efficiencyLogicalCPUCount
            )
        }
        return CPULoadSnapshot(
            cores: .known(loads, source: .hostProcessorLoadInfo),
            aggregateBusy: .known(
                aggregate.busy,
                source: .hostProcessorLoadInfo
            ),
            aggregateUser: .known(
                aggregate.user,
                source: .hostProcessorLoadInfo
            ),
            aggregateSystem: .known(
                aggregate.system,
                source: .hostProcessorLoadInfo
            ),
            aggregateIdle: .known(
                aggregate.idle,
                source: .hostProcessorLoadInfo
            ),
            loadAverages: loadAverages,
            performanceLogicalCPUCount:
                topology.performanceLogicalCPUCount,
            efficiencyLogicalCPUCount:
                topology.efficiencyLogicalCPUCount
        )
    }

    static func loads(
        previous: CPUTickSnapshot,
        current: CPUTickSnapshot
    ) -> [CPUCoreLoad] {
        guard previous.cores.count == current.cores.count else { return [] }
        return zip(previous.cores, current.cores).enumerated().map {
            index, pair in
            let user = tickDelta(pair.0.user, pair.1.user)
            let system = tickDelta(pair.0.system, pair.1.system)
            let idle = tickDelta(pair.0.idle, pair.1.idle)
            let nice = tickDelta(pair.0.nice, pair.1.nice)
            let total = user + system + idle + nice
            guard total > 0 else {
                return CPUCoreLoad(
                    index: index,
                    user: 0,
                    system: 0,
                    idle: 1,
                    nice: 0
                )
            }
            return CPUCoreLoad(
                index: index,
                user: Double(user) / Double(total),
                system: Double(system) / Double(total),
                idle: Double(idle) / Double(total),
                nice: Double(nice) / Double(total)
            )
        }
    }

    static func aggregate(
        previous: CPUTickSnapshot,
        current: CPUTickSnapshot
    ) -> CPUCoreLoad? {
        guard previous.cores.count == current.cores.count else { return nil }
        var user: UInt64 = 0
        var system: UInt64 = 0
        var idle: UInt64 = 0
        var nice: UInt64 = 0
        for (prior, latest) in zip(previous.cores, current.cores) {
            user += tickDelta(prior.user, latest.user)
            system += tickDelta(prior.system, latest.system)
            idle += tickDelta(prior.idle, latest.idle)
            nice += tickDelta(prior.nice, latest.nice)
        }
        let total = user + system + idle + nice
        guard total > 0 else { return nil }
        return CPUCoreLoad(
            index: -1,
            user: Double(user) / Double(total),
            system: Double(system) / Double(total),
            idle: Double(idle) / Double(total),
            nice: Double(nice) / Double(total)
        )
    }

    private static func tickDelta(
        _ previous: UInt64,
        _ current: UInt64
    ) -> UInt64 {
        if current >= previous { return current - previous }
        return UInt64(UInt32.max) - previous + 1 + current
    }
}

enum CPULoadAverageReader {
    static func read() -> Measurement<[Double]> {
        var values = [Double](repeating: 0, count: 3)
        let count = values.withUnsafeMutableBufferPointer { buffer in
            getloadavg(buffer.baseAddress, Int32(buffer.count))
        }
        guard count == values.count else {
            return .notPublished(
                reason: "getloadavg did not publish all three intervals"
            )
        }
        return .known(values, source: .getLoadAverage)
    }
}

struct CPUTickSnapshot: Sendable, Equatable {
    struct Core: Sendable, Equatable {
        let user: UInt64
        let system: UInt64
        let idle: UInt64
        let nice: UInt64
    }

    let cores: [Core]
}

private enum CPUReadError: Error {
    case unavailable(code: Int32)
    case invalidCoreCount(UInt32)
}

private struct CPUTickReader {
    func read() throws -> CPUTickSnapshot {
        var raw = fathom_cpu_ticks()
        var errorCode: Int32 = 0
        guard fathom_cpu_read_ticks(&raw, &errorCode) == 0 else {
            throw CPUReadError.unavailable(code: errorCode)
        }
        guard raw.core_count > 0,
              raw.core_count <= UInt32(FATHOM_MAX_CPU_CORES) else {
            throw CPUReadError.invalidCoreCount(raw.core_count)
        }
        let count = Int(raw.core_count)
        let user = values(of: &raw.user, count: count)
        let system = values(of: &raw.system, count: count)
        let idle = values(of: &raw.idle, count: count)
        let nice = values(of: &raw.nice, count: count)
        return CPUTickSnapshot(
            cores: (0..<count).map {
                .init(
                    user: user[$0],
                    system: system[$0],
                    idle: idle[$0],
                    nice: nice[$0]
                )
            }
        )
    }

    private func values<T>(
        of tuple: inout T,
        count: Int
    ) -> [UInt64] {
        withUnsafeBytes(of: &tuple) { bytes in
            Array(bytes.bindMemory(to: UInt64.self).prefix(count))
        }
    }
}

private struct CPUTopologyReader {
    func read() -> (
        performanceLogicalCPUCount: Measurement<UInt64>,
        efficiencyLogicalCPUCount: Measurement<UInt64>
    ) {
        (
            read(
                "hw.perflevel0.logicalcpu",
                source: .sysctlPerformanceLogicalCPU
            ),
            read(
                "hw.perflevel1.logicalcpu",
                source: .sysctlEfficiencyLogicalCPU
            )
        )
    }

    private func read(
        _ name: String,
        source: DataSource
    ) -> Measurement<UInt64> {
        var value: UInt64 = 0
        var size = MemoryLayout.size(ofValue: value)
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else {
            return .notPublished(
                reason: "sysctl \(name) is not published on this Mac"
            )
        }
        return .known(value, source: source)
    }
}
