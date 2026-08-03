import Foundation

public struct FathomBarConfiguration: Sendable, Equatable {
    public static let suiteName = "com.exhibinaut.fathom.shared"
    public static let freeSpaceKey = "bar.freeSpace"
    public static let hottestSensorKey = "bar.hottestSensor"
    public static let networkThroughputKey = "bar.networkThroughput"
    public static let cpuLoadKey = "bar.cpuLoad"

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
