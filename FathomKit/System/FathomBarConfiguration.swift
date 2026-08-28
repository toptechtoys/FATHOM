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
    /// The widget samples on this cadence while the menu bar is visible, with
    /// half a second of tolerance so the scheduler can coalesce the wakeup with
    /// something the system was doing anyway. Rule 8 caps what the widget may
    /// cost, and an uncoalesced timer is most of what a menu bar item spends.
    public static let intervalSeconds: TimeInterval = 5
    public static let toleranceSeconds: TimeInterval = 0.5

    /// Free space every other tick, the temperature inventory every third.
    /// Capacity does not move fast enough to be worth a read every five
    /// seconds, and the IOHID sensor walk is the most expensive read here.
    public static let capacityEveryTicks: UInt64 = 2
    public static let temperatureEveryTicks: UInt64 = 3

    /// The cadence in the units a reader thinks in. Anything that displays the
    /// refresh rate should read it from here: the widget has never sampled
    /// faster than every five seconds, so a screen that states a different
    /// figure is stating it from memory.
    public static var refreshHertz: Double { 1 / intervalSeconds }

    /// How long a reading taken on a given cadence may stand in for a fresh
    /// one. A value that has outlived its own cadence means the loop stopped —
    /// the menu bar was hidden, or the Mac slept — which is a different fact
    /// from a value that has not changed.
    public static func reuseWindow(everyTicks: UInt64) -> TimeInterval {
        Double(everyTicks) * (intervalSeconds + toleranceSeconds)
    }

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
        readsCapacity = configuration.showsFreeSpace &&
            tick.isMultiple(of: Self.capacityEveryTicks)
        readsTemperatureInventory = configuration.showsHottestSensor &&
            tick.isMultiple(of: Self.temperatureEveryTicks)
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
        // The three keys are written as three separate defaults, so a process
        // that dies between them leaves a percentage with no count beside it.
        // `integer(forKey:)` answers 0 for a key that was never written, and
        // the app prints that count in its own chrome — "measured with 0
        // items" is a pairing nobody made. Refuse the reading instead.
        guard
            defaults.object(
                forKey: FathomBarConfiguration.measuredIdleItemCountKey
            ) != nil
        else {
            return .notPublished(
                reason: "A cost was published without the item count it was measured with. The 0.2% target is stated for four items, so a figure that cannot name its count cannot be compared to it."
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

    /// Writes one measurement to the shared defaults.
    ///
    /// The date and the item count are not decoration. Without the date a
    /// figure from before the machine slept is indistinguishable from one taken
    /// a moment ago; without the count it cannot be held against a budget that
    /// is stated for four items.
    public func write(
        to defaults: UserDefaults = UserDefaults(
            suiteName: FathomBarConfiguration.suiteName
        ) ?? .standard
    ) {
        defaults.set(
            cpuPercent,
            forKey: FathomBarConfiguration.measuredIdleCPUKey
        )
        defaults.set(
            measuredAt.timeIntervalSinceReferenceDate,
            forKey: FathomBarConfiguration.measuredIdleAtKey
        )
        defaults.set(
            itemCount,
            forKey: FathomBarConfiguration.measuredIdleItemCountKey
        )
    }

    /// Whether a self-measurement may be published, and what it says if not.
    ///
    /// The percentage covers the interval between two `proc_pid_rusage` reads,
    /// and the menu bar the widget was drawing during that interval is what the
    /// cost is a cost *of*. If the user turned an item off part way through,
    /// neither count describes the whole interval, so the figure is withheld
    /// rather than filed under a count it was not taken with. The next interval
    /// is measured entirely under the new configuration and publishes normally.
    public static func publication(
        cost: Measurement<Double>,
        itemCountAtStartOfInterval: Int,
        itemCountNow: Int,
        now: Date
    ) -> IdleCostPublication {
        switch cost {
        case let .known(percent, _):
            guard itemCountAtStartOfInterval == itemCountNow else {
                return .withheld(
                    reason: "The menu bar changed from \(itemCountAtStartOfInterval) items to \(itemCountNow) during the measured interval, so this cost belongs to neither."
                )
            }
            return .published(
                MeasuredIdleCost(
                    cpuPercent: percent,
                    measuredAt: now,
                    itemCount: itemCountNow
                )
            )
        case let .notPublished(reason):
            return .withheld(reason: reason)
        case .notAttributable:
            return .withheld(
                reason: "This process's CPU time is not attributable to the widget alone."
            )
        }
    }

    /// What the widget's own menu says about its cost.
    ///
    /// It used to say "Idle cost: not published" as a literal, set once at
    /// launch and never updated, so the widget went on denying it had a figure
    /// for as long as it ran — while writing one to the shared defaults every
    /// five seconds. Rule 8 says the displayed figure is the measured one and
    /// never the budget, which cuts both ways: not printing 0.2% is only half
    /// of it, printing what was measured is the other half.
    public static func menuTitle(
        for measurement: Measurement<MeasuredIdleCost>
    ) -> String {
        switch measurement {
        case let .known(cost, _):
            let percent = cost.cpuPercent
                .formatted(.number.precision(.fractionLength(2)))
            let items = cost.itemCount == 1 ? "1 item" : "\(cost.itemCount) items"
            return "Idle cost: \(percent)% CPU with \(items)"
        case .notPublished:
            return "Idle cost: not published"
        case .notAttributable:
            return "Idle cost: not attributable"
        }
    }
}

/// The outcome of asking whether a self-measurement may be published.
public enum IdleCostPublication: Sendable, Equatable {
    case published(MeasuredIdleCost)
    /// Nothing is written. The previously published figure keeps its own date,
    /// so it ages into staleness on its own rather than being refreshed by a
    /// measurement that did not happen.
    case withheld(reason: String)
}
