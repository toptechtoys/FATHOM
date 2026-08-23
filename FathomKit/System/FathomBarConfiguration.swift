import Foundation

public struct FathomBarConfiguration: Sendable, Equatable {
    public static let suiteName = "com.exhibinaut.fathom.shared"
    public static let freeSpaceKey = "bar.freeSpace"
    public static let hottestSensorKey = "bar.hottestSensor"
    public static let networkThroughputKey = "bar.networkThroughput"
    public static let cpuLoadKey = "bar.cpuLoad"

    /// The widget's own measured idle CPU, as a percentage of one core.
    ///
    /// Rule 8 makes idle cost a shipped number, so the widget measures itself
    /// and publishes the figure here rather than the app printing a budget as
    /// though it were an observation. Absent until the widget has run long
    /// enough to have two samples.
    public static let measuredIdleCPUKey = "bar.measuredIdleCPUPercent"

    /// When that measurement was taken, as seconds since the reference date.
    /// A figure with no date cannot be told apart from a stale one.
    public static let measuredIdleAtKey = "bar.measuredIdleAt"

    /// How many items were shown when it was measured. The budget is stated
    /// for four items, and a cost measured with one is not comparable.
    public static let measuredIdleItemCountKey = "bar.measuredIdleItemCount"

    public let showsFreeSpace: Bool
    public let showsHottestSensor: Bool
    public let showsNetworkThroughput: Bool
    public let showsCPULoad: Bool

    public init(
        showsFreeSpace: Bool = true,
        showsHottestSensor: Bool = true,
        showsNetworkThroughput: Bool = true,
        showsCPULoad: Bool = true
    ) {
        self.showsFreeSpace = showsFreeSpace
        self.showsHottestSensor = showsHottestSensor
        self.showsNetworkThroughput = showsNetworkThroughput
        self.showsCPULoad = showsCPULoad
    }

    /// How many items this configuration puts in the menu bar.
    ///
    /// The idle-cost budget is stated for four items, so a measurement has to
    /// carry the count it was taken with or it cannot be compared to it.
    public var enabledItemCount: Int {
        [showsFreeSpace, showsHottestSensor, showsNetworkThroughput, showsCPULoad]
            .count { $0 }
    }

    public static func load(
        defaults: UserDefaults = UserDefaults(suiteName: suiteName) ?? .standard
    ) -> FathomBarConfiguration {
        func value(_ key: String) -> Bool {
            defaults.object(forKey: key) == nil
                ? true
                : defaults.bool(forKey: key)
        }
        return FathomBarConfiguration(
            showsFreeSpace: value(freeSpaceKey),
            showsHottestSensor: value(hottestSensorKey),
            showsNetworkThroughput: value(networkThroughputKey),
            showsCPULoad: value(cpuLoadKey)
        )
    }
}

public struct FathomBarSamplingPlan: Sendable, Equatable {
    public let readsCPU: Bool
    public let readsNetwork: Bool
    public let readsCapacity: Bool
    public let readsTemperatureInventory: Bool

    public init(
        tick: UInt64,
        configuration: FathomBarConfiguration
    ) {
        readsCPU = configuration.showsCPULoad
        readsNetwork = configuration.showsNetworkThroughput
        readsCapacity = configuration.showsFreeSpace && tick.isMultiple(of: 2)
        readsTemperatureInventory = configuration.showsHottestSensor &&
            tick.isMultiple(of: 3)
    }

    public var estimatedReadOperations: Int {
        [readsCPU, readsNetwork, readsCapacity, readsTemperatureInventory]
            .filter { $0 }
            .count
    }
}

/// What the widget measured about itself, read back by the app.
///
/// Rule 8 makes idle cost a shipped number. The widget publishes what it
/// measured and this reads it back, so the app never prints the 0.2% budget as
/// though it were an observation.
public struct MeasuredIdleCost: Sendable, Equatable {
    public let cpuPercent: Double
    public let measuredAt: Date
    public let itemCount: Int

    public init(cpuPercent: Double, measuredAt: Date, itemCount: Int) {
        self.cpuPercent = cpuPercent
        self.measuredAt = measuredAt
        self.itemCount = itemCount
    }

    /// A measurement older than this is reported as stale rather than current.
    /// The widget publishes every five seconds while visible, so anything this
    /// old means it stopped — which is a different fact from a low cost.
    public static let freshnessWindow: TimeInterval = 60

    public func isFresh(now: Date = Date()) -> Bool {
        now.timeIntervalSince(measuredAt) <= Self.freshnessWindow
    }

    public static func load(
        defaults: UserDefaults = UserDefaults(
            suiteName: FathomBarConfiguration.suiteName
        ) ?? .standard,
        now: Date = Date()
    ) -> Measurement<MeasuredIdleCost> {
        guard
            defaults.object(
                forKey: FathomBarConfiguration.measuredIdleCPUKey
            ) != nil,
            defaults.object(
                forKey: FathomBarConfiguration.measuredIdleAtKey
            ) != nil
        else {
            return .notPublished(
                reason: "The menu bar widget has not measured itself yet. It publishes a figure once it has been running long enough to have two samples."
            )
        }
        let percent = defaults.double(
            forKey: FathomBarConfiguration.measuredIdleCPUKey
        )
        let at = Date(
            timeIntervalSinceReferenceDate: defaults.double(
                forKey: FathomBarConfiguration.measuredIdleAtKey
            )
        )
        let items = defaults.integer(
            forKey: FathomBarConfiguration.measuredIdleItemCountKey
        )
        let cost = MeasuredIdleCost(
            cpuPercent: percent,
            measuredAt: at,
            itemCount: items
        )
        guard cost.isFresh(now: now) else {
            let age = Int(now.timeIntervalSince(at))
            return .notPublished(
                reason: "The last measurement is \(age) seconds old. The widget stops sampling when the menu bar is hidden, so this is what it cost when it last ran, not what it costs now."
            )
        }
        return .known(cost, source: .procPidRusage)
    }
}
