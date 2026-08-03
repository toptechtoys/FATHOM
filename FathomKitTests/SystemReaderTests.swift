@testable import FathomKit
import Testing

@Test
func networkRateRequiresTwoSamplesAndRejectsCounterReset() {
    #expect(
        NetworkSampler.rate(
            previous: nil,
            current: 100,
            elapsed: 1
        ) == .notPublished(reason: "A second counter sample is required")
    )
    #expect(
        NetworkSampler.rate(
            previous: 200,
            current: 100,
            elapsed: 1
        ) == .notPublished(reason: "The interface counter reset")
    )
    #expect(
        NetworkSampler.rate(
            previous: 100,
            current: 700,
            elapsed: 2
        ) == .known(
            300,
            source: .sysctlNetworkInterfaceList
        )
    )
}

@Test
func localNetworkAddressesUseGetifaddrsWithoutGuessing() {
    let measurement = NetworkSampler.readAddresses()
    switch measurement {
    case let .known(addresses, source):
        #expect(source == .getifaddrsNetworkAddresses)
        #expect(addresses.allSatisfy {
            !$0.interfaceName.isEmpty &&
                !$0.address.isEmpty &&
                ($0.family == 4 || $0.family == 6)
        })
    case let .notPublished(reason):
        #expect(reason.contains("getifaddrs"))
    case .notAttributable:
        Issue.record("Local socket addresses unexpectedly lost attribution")
    }
}

@Test
func displayCallbackRateRequiresAMonotonicCounter() {
    #expect(
        DisplayRefreshSampler.rate(
            previous: 100,
            current: 220,
            elapsed: 2
        ) == .known(60, source: .cvDisplayLinkCallbackDelta)
    )
    guard case .notPublished = DisplayRefreshSampler.rate(
        previous: 220,
        current: 100,
        elapsed: 1
    ) else {
        Issue.record("A reset display-link counter was presented as a rate")
        return
    }
}

@Test
func dynamicNetworkStateKeepsEachMissingFieldExplicit() {
    let snapshot = NetworkSampler.readConfiguration()
    for measurement in [snapshot.primaryInterface, snapshot.router] {
        switch measurement {
        case let .known(value, source):
            #expect(!value.isEmpty)
            #expect(source == .scDynamicStoreNetworkState)
        case let .notPublished(reason):
            #expect(reason.contains("SCDynamicStore"))
        case .notAttributable:
            Issue.record("Direct dynamic-store state lost attribution")
        }
    }
    switch snapshot.dnsServers {
    case let .known(values, source):
        #expect(!values.isEmpty)
        #expect(source == .scDynamicStoreNetworkState)
    case let .notPublished(reason):
        #expect(reason.contains("SCDynamicStore"))
    case .notAttributable:
        Issue.record("Direct DNS state lost attribution")
    }
}

@Test
func gpuReaderPublishesOnlyExactRuntimeKeys() {
    let snapshot = GPUReader().read()
    for measurement in [
        snapshot.deviceUtilizationPercent,
        snapshot.rendererUtilizationPercent,
        snapshot.tilerUtilizationPercent
    ] {
        switch measurement {
        case let .known(value, source):
            #expect((0...100).contains(value))
            #expect(source == .ioAcceleratorPerformanceStatistics)
        case let .notPublished(reason):
            #expect(!reason.isEmpty)
        case .notAttributable:
            Issue.record("A direct IOAccelerator value cannot be unattributable")
        }
    }
}

@MainActor
@Test
func bluetoothEnumerationIsKnownOrNamesTheRuntimeGap() {
    switch BluetoothReader().read().devices {
    case let .known(devices, source):
        #expect(source == .ioBluetoothPairedDevices)
        for device in devices {
            #expect(!device.address.isEmpty)
        }
    case let .notPublished(reason):
        #expect(!reason.isEmpty)
    case .notAttributable:
        Issue.record("Paired-device enumeration cannot be unattributable")
    }
}

@MainActor
@Test
func bluetoothReadRefusesToAskWithoutTheDeclaredUsageDescription() {
    // TCC terminates any process that requests paired devices without
    // NSBluetoothAlwaysUsageDescription. This bundle deliberately omits it, so
    // the reader must name the gap instead of issuing the request.
    #expect(!BluetoothReader.hostDeclaresBluetoothUsage)
    guard case let .notPublished(reason) = BluetoothReader().read().devices else {
        Issue.record(
            "A host without \(BluetoothReader.usageDescriptionKey) cannot publish paired devices"
        )
        return
    }
    #expect(reason.contains(BluetoothReader.usageDescriptionKey))
}

@Test
func fathomBarConfigurationDefaultsToTheFourShippedItems() {
    let configuration = FathomBarConfiguration()
    #expect(configuration.showsFreeSpace)
    #expect(configuration.showsHottestSensor)
    #expect(configuration.showsNetworkThroughput)
    #expect(configuration.showsCPULoad)
}

@Test
func menuBarDefaultPlanStaysWithinTheDeterministicReadBudget() {
    let configuration = FathomBarConfiguration()
    let plans = (0..<12).map {
        FathomBarSamplingPlan(
            tick: UInt64($0),
            configuration: configuration
        )
    }
    #expect(plans.filter(\.readsCPU).count == 12)
    #expect(plans.filter(\.readsNetwork).count == 12)
    #expect(plans.filter(\.readsCapacity).count == 6)
    #expect(plans.filter(\.readsTemperatureInventory).count == 4)
    #expect(plans.map(\.estimatedReadOperations).reduce(0, +) <= 34)
}

@Test
func fseventRecorderRefusesAnEmptyWatchSet() {
    #expect(throws: FSEventRecorderError.noPaths) {
        try FSEventRecorder().start(paths: [])
    }
}
