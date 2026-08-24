import FathomKit
import Foundation

actor FathomBarSampler {
    private let cpu = CPUSampler()
    private let network = NetworkSampler()
    private var primed = false
    private var tick: UInt64 = 0
    private var cachedCPU: CPULoadSnapshot?
    private var cachedNetwork: NetworkSnapshot?
    private var cachedCapacity: VolumeCapacitySnapshot?
    private var cachedTemperatures:
        FathomKit.Measurement<[TemperatureSensorReading]>?

    func sample() async -> FathomBarPresentation {
        let configuration = FathomBarConfiguration.load()
        let plan = FathomBarSamplingPlan(
            tick: tick,
            configuration: configuration
        )
        if !primed {
            primed = true
            _ = await cpu.sample()
            _ = await network.sample()
            try? await Task.sleep(for: .milliseconds(250))
        }
        let cpuTask = plan.readsCPU
            ? Task { await cpu.sample() }
            : nil
        let networkTask = plan.readsNetwork
            ? Task { await network.sample() }
            : nil
        let capacityTask = plan.readsCapacity
            ? Task.detached(priority: .utility) {
                VolumeCapacityReader().read(
                    volumeURL: URL(fileURLWithPath: "/")
                )
            }
            : nil
        let temperatureTask = plan.readsTemperatureInventory
            ? Task.detached(priority: .utility) {
                TemperatureSensorReader().read()
            }
            : nil
        let cpuSnapshot = await cpuTask?.value ?? cachedCPU ?? Self.cpuGap
        let networkSnapshot = await networkTask?.value ??
            cachedNetwork ?? Self.networkGap
        let capacity = await capacityTask?.value ??
            cachedCapacity ?? Self.capacityGap
        let temperatures = await temperatureTask?.value ??
            cachedTemperatures ?? .notPublished(
                reason: "Temperature sampling is disabled"
            )
        cachedCPU = cpuSnapshot
        cachedNetwork = networkSnapshot
        cachedCapacity = capacity
        cachedTemperatures = temperatures
        tick &+= 1
        return FathomBarPresentation(
            configuration: configuration,
            capacity: capacity,
            cpu: cpuSnapshot,
            network: networkSnapshot,
            temperatures: temperatures
        )
    }

    private static let cpuGap = CPULoadSnapshot(
        cores: .notPublished(reason: "CPU sampling is disabled"),
        aggregateBusy: .notPublished(reason: "CPU sampling is disabled"),
        aggregateUser: .notPublished(reason: "CPU sampling is disabled"),
        aggregateSystem: .notPublished(reason: "CPU sampling is disabled"),
        aggregateIdle: .notPublished(reason: "CPU sampling is disabled"),
        loadAverages: .notPublished(reason: "CPU sampling is disabled"),
        performanceLogicalCPUCount: .notPublished(
            reason: "CPU sampling is disabled"
        ),
        efficiencyLogicalCPUCount: .notPublished(
            reason: "CPU sampling is disabled"
        )
    )

    private static let networkGap = NetworkSnapshot(
        interfaces: .notPublished(reason: "Network sampling is disabled"),
        localAddresses: .notPublished(reason: "Network sampling is disabled"),
        configuration: NetworkConfigurationSnapshot(
            primaryInterface: .notPublished(
                reason: "Network sampling is disabled"
            ),
            router: .notPublished(reason: "Network sampling is disabled"),
            dnsServers: .notPublished(reason: "Network sampling is disabled")
        )
    )

    private static let capacityGap = VolumeCapacitySnapshot(
        actuallyFree: .notPublished(reason: "Capacity sampling is disabled"),
        finderAvailable: .notPublished(reason: "Capacity sampling is disabled"),
        purgeable: .notPublished(reason: "Capacity sampling is disabled")
    )
}

struct FathomBarPresentation: Sendable {
    let title: String
    let accessibilityLabel: String

    init(
        configuration: FathomBarConfiguration,
        capacity: VolumeCapacitySnapshot,
        cpu: CPULoadSnapshot,
        network: NetworkSnapshot,
        temperatures: FathomKit.Measurement<[TemperatureSensorReading]>
    ) {
        let free = Self.freeText(capacity)
        let heat = Self.temperatureText(temperatures)
        let down = Self.networkText(network)
        let load = Self.cpuText(cpu)
        var items: [(short: String, long: String)] = []
        if configuration.showsFreeSpace { items.append(free) }
        if configuration.showsHottestSensor { items.append(heat) }
        if configuration.showsNetworkThroughput { items.append(down) }
        if configuration.showsCPULoad { items.append(load) }
        title = items.isEmpty ? "FATHOM" : items.map(\.short)
            .joined(separator: "  ")
        accessibilityLabel = items.isEmpty
            ? "FATHOM menu bar"
            : items.map(\.long)
            .joined(separator: ", ")
    }

    private static func freeText(
        _ snapshot: VolumeCapacitySnapshot
    ) -> (short: String, long: String) {
        switch snapshot.actuallyFree {
        case let .known(value, _):
            let text = ByteString.file(value)
            return (text, "\(text) actually free")
        case .notPublished:
            return ("— GB", "free space not published")
        case .notAttributable:
            return ("— GB", "free space not attributable")
        }
    }

    private static func temperatureText(
        _ measurement: FathomKit.Measurement<[TemperatureSensorReading]>
    ) -> (short: String, long: String) {
        guard case let .known(readings, _) = measurement else {
            return ("—°", "hottest sensor not published")
        }
        let values = readings.compactMap { reading -> Double? in
            guard case let .known(value, _) = reading.celsius else { return nil }
            return value
        }
        guard let hottest = values.max() else {
            return ("—°", "hottest sensor not published")
        }
        let text = hottest.formatted(.number.precision(.fractionLength(0)))
        return ("\(text)°", "hottest sensor \(text) degrees Celsius")
    }

    private static func networkText(
        _ snapshot: NetworkSnapshot
    ) -> (short: String, long: String) {
        guard case let .known(interfaces, _) = snapshot.interfaces else {
            return ("—/s", "network throughput not published")
        }
        let known = interfaces.compactMap { interface -> Double? in
            guard case let .known(value, _) = interface.receivedBytesPerSecond else {
                return nil
            }
            return value
        }
        guard !known.isEmpty else {
            return ("—/s", "network throughput not published")
        }
        let total = known.reduce(0, +)
        let text = ByteString.file(rounding: total)
        return ("↓\(text)/s", "download \(text) per second")
    }

    private static func cpuText(
        _ snapshot: CPULoadSnapshot
    ) -> (short: String, long: String) {
        guard case let .known(value, _) = snapshot.aggregateBusy else {
            return ("—%", "CPU load not published")
        }
        let text = (value * 100).formatted(
            .number.precision(.fractionLength(0))
        )
        return ("\(text)%", "CPU load \(text) percent")
    }
}
