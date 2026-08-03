import Testing
@testable import FathomKit

@Test func diskRateRequiresTwoMonotonicSamples() {
    guard case .notPublished = DiskThroughputSampler.rate(
        previous: nil,
        current: 10,
        elapsed: 1
    ) else {
        Issue.record("A first disk counter was presented as a rate")
        return
    }
    guard case let .known(rate, source) = DiskThroughputSampler.rate(
        previous: 100,
        current: 350,
        elapsed: 0.5
    ) else {
        Issue.record("A valid disk counter delta was not published")
        return
    }
    #expect(rate == 500)
    #expect(source == .ioBlockStorageDriverStatistics)
    guard case .notPublished = DiskThroughputSampler.rate(
        previous: 350,
        current: 100,
        elapsed: 1
    ) else {
        Issue.record("A reset disk counter was presented as throughput")
        return
    }
}

@Test func diskReaderEitherPublishesExactRegistryCountersOrNamesTheGap() async {
    let measurement = await DiskThroughputSampler().sample()
    switch measurement {
    case let .known(snapshot, source):
        #expect(source == .ioBlockStorageDriverStatistics)
        #expect(snapshot.driverCount > 0)
    case let .notPublished(reason):
        #expect(reason.contains("IOBlockStorageDriver"))
    case .notAttributable:
        Issue.record("Raw block-driver totals unexpectedly lost attribution")
    }
}
