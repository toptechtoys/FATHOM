import Foundation

/// The four reads the menu bar widget can make, as injectable work.
///
/// The widget's sampler used to construct `CPUSampler`, `NetworkSampler`,
/// `VolumeCapacityReader` and `TemperatureSensorReader` itself, inside a target
/// with no test scheme, which meant no test could ever ask what it renders when
/// a read fails — the one question a widget that publishes a cost has to be
/// able to answer. Injecting the reads leaves the live wiring in `live()` and
/// makes every gap reachable from a test.
public struct FathomBarReaders: Sendable {
    /// The first CPU and network reads produce no delta, so the live wiring
    /// throws a pair away before the first published figure. A stub does
    /// nothing, which is also why the tests do not pay the 250 ms.
    public var prime: @Sendable () async -> Void
    public var cpu: @Sendable () async -> CPULoadSnapshot
    public var network: @Sendable () async -> NetworkSnapshot
    public var capacity: @Sendable () async -> VolumeCapacitySnapshot
    public var temperatures: @Sendable () async
        -> Measurement<[TemperatureSensorReading]>

    public init(
        prime: @escaping @Sendable () async -> Void = {},
        cpu: @escaping @Sendable () async -> CPULoadSnapshot,
        network: @escaping @Sendable () async -> NetworkSnapshot,
        capacity: @escaping @Sendable () async -> VolumeCapacitySnapshot,
        temperatures: @escaping @Sendable () async
            -> Measurement<[TemperatureSensorReading]>
    ) {
        self.prime = prime
        self.cpu = cpu
        self.network = network
        self.capacity = capacity
        self.temperatures = temperatures
    }

    /// What the shipping widget reads.
    ///
    /// Capacity and the temperature inventory stay on detached utility tasks:
    /// both touch the file system or IOKit, and rule 8 caps what this process
    /// may cost while it does.
    public static func live(
        volumeURL: URL = URL(fileURLWithPath: "/")
    ) -> FathomBarReaders {
        let cpu = CPUSampler()
        let network = NetworkSampler()
        return FathomBarReaders(
            prime: {
                _ = await cpu.sample()
                _ = await network.sample()
                try? await Task.sleep(for: .milliseconds(250))
            },
            cpu: { await cpu.sample() },
            network: { await network.sample() },
            capacity: {
                await Task.detached(priority: .utility) {
                    VolumeCapacityReader().read(volumeURL: volumeURL)
                }.value
            },
            temperatures: {
                await Task.detached(priority: .utility) {
                    TemperatureSensorReader().read()
                }.value
            }
        )
    }
}

/// One reading, and how long it is allowed to stand in for a fresh one.
///
/// The widget reads capacity every other tick and the temperature inventory
/// every third, so on the ticks in between it re-renders the previous value.
/// That is a cadence, not a licence: the sampling loop is cancelled whenever
/// the menu bar is hidden or the Mac sleeps, and without an age limit the first
/// tick after a resume can redraw a figure measured before the machine slept as
/// though it were current. A reading older than the cadence that produced it is
/// refused, and the item renders not published instead.
public struct FathomBarReadingCache<Value: Sendable>: Sendable {
    private struct Entry: Sendable {
        let value: Value
        let takenAt: Date
    }

    public let maximumAge: TimeInterval
    private var entry: Entry?

    public init(maximumAge: TimeInterval) {
        self.maximumAge = maximumAge
    }

    public mutating func store(_ value: Value, at date: Date) {
        entry = Entry(value: value, takenAt: date)
    }

    /// The stored reading, or nil when there is none or it has aged out.
    public func value(at now: Date) -> Value? {
        guard let entry else { return nil }
        let age = now.timeIntervalSince(entry.takenAt)
        guard age >= 0, age <= maximumAge else { return nil }
        return entry.value
    }
}

/// Assembles one menu bar draw from the reads the cadence allows.
public actor FathomBarSampler {
    private let readers: FathomBarReaders
    private let configuration: @Sendable () -> FathomBarConfiguration
    private let now: @Sendable () -> Date
    private var primed = false
    private var tick: UInt64 = 0
    private var cpuCache = FathomBarReadingCache<CPULoadSnapshot>(
        maximumAge: FathomBarSamplingPlan.reuseWindow(everyTicks: 1)
    )
    private var networkCache = FathomBarReadingCache<NetworkSnapshot>(
        maximumAge: FathomBarSamplingPlan.reuseWindow(everyTicks: 1)
    )
    private var capacityCache = FathomBarReadingCache<VolumeCapacitySnapshot>(
        maximumAge: FathomBarSamplingPlan.reuseWindow(
            everyTicks: FathomBarSamplingPlan.capacityEveryTicks
        )
    )
    private var temperatureCache = FathomBarReadingCache<
        Measurement<[TemperatureSensorReading]>
    >(
        maximumAge: FathomBarSamplingPlan.reuseWindow(
            everyTicks: FathomBarSamplingPlan.temperatureEveryTicks
        )
    )

    public init(
        readers: FathomBarReaders = .live(),
        configuration: @escaping @Sendable () -> FathomBarConfiguration = {
            FathomBarConfiguration.load()
        },
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.readers = readers
        self.configuration = configuration
        self.now = now
    }

    public func sample() async -> FathomBarPresentation {
        let configuration = self.configuration()
        let plan = FathomBarSamplingPlan(
            tick: tick,
            configuration: configuration
        )
        if !primed {
            primed = true
            await readers.prime()
        }
        let cpuTask = plan.readsCPU
            ? Task { [readers] in await readers.cpu() }
            : nil
        let networkTask = plan.readsNetwork
            ? Task { [readers] in await readers.network() }
            : nil
        let capacityTask = plan.readsCapacity
            ? Task { [readers] in await readers.capacity() }
            : nil
        let temperatureTask = plan.readsTemperatureInventory
            ? Task { [readers] in await readers.temperatures() }
            : nil
        let freshCPU = await cpuTask?.value
        let freshNetwork = await networkTask?.value
        let freshCapacity = await capacityTask?.value
        let freshTemperatures = await temperatureTask?.value
        // One instant for the whole draw: storing each reading against its own
        // clock read would let two values taken in the same pass disagree about
        // how old they are.
        let now = self.now()
        let cpuSnapshot = Self.resolve(
            fresh: freshCPU,
            cache: &cpuCache,
            now: now,
            gap: Self.cpuGap(
                reason: Self.reason(
                    "CPU load",
                    isShown: configuration.showsCPULoad
                )
            )
        )
        let networkSnapshot = Self.resolve(
            fresh: freshNetwork,
            cache: &networkCache,
            now: now,
            gap: Self.networkGap(
                reason: Self.reason(
                    "Network throughput",
                    isShown: configuration.showsNetworkThroughput
                )
            )
        )
        let capacity = Self.resolve(
            fresh: freshCapacity,
            cache: &capacityCache,
            now: now,
            gap: Self.capacityGap(
                reason: Self.reason(
                    "Free space",
                    isShown: configuration.showsFreeSpace
                )
            )
        )
        let temperatures = Self.resolve(
            fresh: freshTemperatures,
            cache: &temperatureCache,
            now: now,
            gap: .notPublished(
                reason: Self.reason(
                    "The hottest sensor",
                    isShown: configuration.showsHottestSensor
                )
            )
        )
        tick &+= 1
        return FathomBarPresentation(
            configuration: configuration,
            capacity: capacity,
            cpu: cpuSnapshot,
            network: networkSnapshot,
            temperatures: temperatures
        )
    }

    /// A fresh read wins, a cached read stands only while the cadence says it
    /// may, and the gap is what is left. Static so that taking the cache
    /// `inout` never overlaps with the actor's own access to itself.
    private static func resolve<Value>(
        fresh: Value?,
        cache: inout FathomBarReadingCache<Value>,
        now: Date,
        gap: @autoclosure () -> Value
    ) -> Value {
        if let fresh {
            cache.store(fresh, at: now)
            return fresh
        }
        if let cached = cache.value(at: now) { return cached }
        return gap()
    }

    private static func reason(_ subject: String, isShown: Bool) -> String {
        isShown
            ? "\(subject) has not been re-read since the widget resumed sampling. The widget stops while the menu bar is hidden or the Mac is asleep, so the last figure describes a machine that may have changed."
            : "\(subject) is not shown in the menu bar."
    }

    private static func cpuGap(reason: String) -> CPULoadSnapshot {
        CPULoadSnapshot(
            cores: .notPublished(reason: reason),
            aggregateBusy: .notPublished(reason: reason),
            aggregateUser: .notPublished(reason: reason),
            aggregateSystem: .notPublished(reason: reason),
            aggregateIdle: .notPublished(reason: reason),
            loadAverages: .notPublished(reason: reason),
            performanceLogicalCPUCount: .notPublished(reason: reason),
            efficiencyLogicalCPUCount: .notPublished(reason: reason)
        )
    }

    private static func networkGap(reason: String) -> NetworkSnapshot {
        NetworkSnapshot(
            interfaces: .notPublished(reason: reason),
            localAddresses: .notPublished(reason: reason),
            configuration: NetworkConfigurationSnapshot(
                primaryInterface: .notPublished(reason: reason),
                router: .notPublished(reason: reason),
                dnsServers: .notPublished(reason: reason)
            )
        )
    }

    private static func capacityGap(
        reason: String
    ) -> VolumeCapacitySnapshot {
        VolumeCapacitySnapshot(
            actuallyFree: .notPublished(reason: reason),
            finderAvailable: .notPublished(reason: reason),
            purgeable: .notPublished(reason: reason)
        )
    }
}
