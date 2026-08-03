import Testing
@testable import FathomKit

@Test func cpuTickDeltaSeparatesUserSystemIdleAndNice() throws {
    let previous = CPUTickSnapshot(cores: [
        .init(user: 100, system: 50, idle: 800, nice: 50)
    ])
    let current = CPUTickSnapshot(cores: [
        .init(user: 120, system: 60, idle: 860, nice: 60)
    ])
    let load = try #require(
        CPUSampler.loads(previous: previous, current: current).first
    )
    #expect(abs(load.user - 0.2) < 0.0001)
    #expect(abs(load.system - 0.1) < 0.0001)
    #expect(abs(load.idle - 0.6) < 0.0001)
    #expect(abs(load.nice - 0.1) < 0.0001)
    #expect(abs(load.busy - 0.4) < 0.0001)
}

@Test func cpuSamplerRequiresAnActualDelta() async throws {
    let sampler = CPUSampler()
    let first = await sampler.sample()
    guard case .notPublished = first.cores else {
        Issue.record("The first cumulative tick read was presented as load")
        return
    }
    try await Task.sleep(for: .milliseconds(100))
    let second = await sampler.sample()
    guard case let .known(cores, source) = second.cores else {
        Issue.record("The second CPU sample was not published")
        return
    }
    #expect(source == .hostProcessorLoadInfo)
    #expect(!cores.isEmpty)
    #expect(cores.allSatisfy { 0...1 ~= $0.busy })
}

@Test func loadAveragePublishesAllThreeKernelIntervals() throws {
    let measurement = CPULoadAverageReader.read()
    let values: [Double]
    switch measurement {
    case let .known(published, source):
        #expect(source == .getLoadAverage)
        values = published
    case let .notPublished(reason):
        Issue.record("Load averages were not published: \(reason)")
        return
    case .notAttributable:
        Issue.record("Load averages unexpectedly lost attribution")
        return
    }
    #expect(values.count == 3)
    #expect(values.allSatisfy { $0.isFinite && $0 >= 0 })
}

@Test func aggregateCPULoadWeightsProcessorsByTheirTickDeltas() throws {
    let previous = CPUTickSnapshot(cores: [
        .init(user: 0, system: 0, idle: 0, nice: 0),
        .init(user: 0, system: 0, idle: 0, nice: 0)
    ])
    let current = CPUTickSnapshot(cores: [
        .init(user: 90, system: 0, idle: 10, nice: 0),
        .init(user: 0, system: 0, idle: 900, nice: 0)
    ])
    let aggregate = try #require(
        CPUSampler.aggregate(previous: previous, current: current)
    )
    #expect(abs(aggregate.user - 0.09) < 0.0001)
    #expect(abs(aggregate.idle - 0.91) < 0.0001)
    #expect(abs(aggregate.busy - 0.09) < 0.0001)
}
