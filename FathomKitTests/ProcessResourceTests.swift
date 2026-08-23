import Foundation
import Testing
@testable import FathomKit

private func sample(cpu: UInt64, at ticks: UInt64) -> ProcessResourceSample {
    ProcessResourceSample(cpuNanoseconds: cpu, timestamp: ticks)
}

@Test func oneSecondOfWallTimeUsingTenMillisecondsOfCPUIsOnePercent() {
    let result = ProcessCPUSampler.percentage(
        from: sample(cpu: 0, at: 0),
        to: sample(cpu: 10_000_000, at: 1_000_000_000),
        nanosecondsPerTick: 1
    )
    guard case let .known(percent, source) = result else {
        Issue.record("expected a percentage")
        return
    }
    #expect(abs(percent - 1.0) < 0.0001)
    #expect(source == .procPidRusage)
}

@Test func theBudgetItselfMeasuresAsTheBudget() {
    // 0.2% of one core over one second is 2 ms of CPU.
    let result = ProcessCPUSampler.percentage(
        from: sample(cpu: 0, at: 0),
        to: sample(cpu: 2_000_000, at: 1_000_000_000),
        nanosecondsPerTick: 1
    )
    guard case let .known(percent, _) = result else {
        Issue.record("expected a percentage")
        return
    }
    #expect(abs(percent - IdleCostBudget.targetCPUPercent) < 0.0001)
    #expect(IdleCostBudget.verdict(forCPUPercent: percent) == .withinTarget)
}

@Test func aTimebaseThatIsNotNanosecondsIsHonoured() {
    // Apple silicon does not report 1:1; a sampler that assumed it would
    // misreport the denominator and therefore the percentage.
    let result = ProcessCPUSampler.percentage(
        from: sample(cpu: 0, at: 0),
        to: sample(cpu: 10_000_000, at: 41_666_666),
        nanosecondsPerTick: 125.0 / 3.0
    )
    guard case let .known(percent, _) = result else {
        Issue.record("expected a percentage")
        return
    }
    // 41,666,666 ticks x 125/3 ns is about 1.736 s of wall time.
    #expect(abs(percent - 0.576) < 0.01)
}

@Test func noElapsedTimeIsNotPublishedRatherThanInfinite() {
    let result = ProcessCPUSampler.percentage(
        from: sample(cpu: 0, at: 500),
        to: sample(cpu: 1_000, at: 500),
        nanosecondsPerTick: 1
    )
    guard case .notPublished = result else {
        Issue.record("divided by a zero interval")
        return
    }
}

@Test func aCounterThatWentBackwardsIsNotPublished() {
    let result = ProcessCPUSampler.percentage(
        from: sample(cpu: 5_000, at: 0),
        to: sample(cpu: 1_000, at: 1_000_000_000),
        nanosecondsPerTick: 1
    )
    guard case .notPublished = result else {
        Issue.record("reported a negative percentage")
        return
    }
}

@Test func theFirstSampleEstablishesABaselineAndPublishesNothing() async {
    let sampler = ProcessCPUSampler()
    guard case let .notPublished(reason) = await sampler.sample() else {
        Issue.record("the first sample reported a rate it could not know")
        return
    }
    #expect(reason.contains("two samples"))
}

@Test func aSecondSampleProducesAPlausibleFigureForThisProcess() async {
    let sampler = ProcessCPUSampler()
    _ = await sampler.sample()
    try? await Task.sleep(for: .milliseconds(120))
    guard case let .known(percent, _) = await sampler.sample() else {
        Issue.record("proc_pid_rusage published nothing on this host")
        return
    }
    // A percentage of one core: never negative, and a test process cannot
    // plausibly exceed the whole machine.
    #expect(percent >= 0)
    #expect(percent < 100 * Double(ProcessInfo.processInfo.activeProcessorCount))
}

@Test func theBudgetThresholdsMatchTheRule() {
    #expect(IdleCostBudget.targetCPUPercent == 0.2)
    #expect(IdleCostBudget.blockingCPUPercent == 0.5)
    #expect(IdleCostBudget.verdict(forCPUPercent: 0.19) == .withinTarget)
    #expect(IdleCostBudget.verdict(forCPUPercent: 0.2) == .withinTarget)
    #expect(
        IdleCostBudget.verdict(forCPUPercent: 0.35) == .overTargetWithinBlocking
    )
    #expect(IdleCostBudget.verdict(forCPUPercent: 0.5) == .blocking)
    #expect(IdleCostBudget.verdict(forCPUPercent: 4.0) == .blocking)
}

@Test func theReaderPublishesAMonotonicCounterOnThisHost() {
    let reader = ProcessResourceReader()
    guard case let .known(first, _) = reader.read() else {
        Issue.record("proc_pid_rusage published nothing")
        return
    }
    var total = 0.0
    for value in 0..<200_000 { total += Double(value).squareRoot() }
    #expect(total > 0)
    guard case let .known(second, _) = reader.read() else {
        Issue.record("proc_pid_rusage stopped publishing")
        return
    }
    #expect(second.cpuNanoseconds >= first.cpuNanoseconds)
    #expect(second.timestamp > first.timestamp)
}

// MARK: - Measured idle cost

private func defaults(_ name: String) -> UserDefaults {
    let store = UserDefaults(suiteName: name)!
    store.removePersistentDomain(forName: name)
    return store
}

@Test func nothingMeasuredYetIsNotPublishedRatherThanZero() {
    let store = defaults("test.idle.empty")
    guard case let .notPublished(reason) = MeasuredIdleCost.load(defaults: store)
    else {
        Issue.record("reported a cost nobody measured")
        return
    }
    #expect(reason.contains("has not measured itself"))
}

@Test func aFreshMeasurementIsPublishedWithItsItemCount() {
    let store = defaults("test.idle.fresh")
    let now = Date()
    store.set(0.17, forKey: FathomBarConfiguration.measuredIdleCPUKey)
    store.set(
        now.timeIntervalSinceReferenceDate,
        forKey: FathomBarConfiguration.measuredIdleAtKey
    )
    store.set(4, forKey: FathomBarConfiguration.measuredIdleItemCountKey)

    guard case let .known(cost, source) = MeasuredIdleCost.load(
        defaults: store,
        now: now
    ) else {
        Issue.record("a fresh measurement was not published")
        return
    }
    #expect(abs(cost.cpuPercent - 0.17) < 0.0001)
    #expect(cost.itemCount == 4)
    #expect(source == .procPidRusage)
    #expect(IdleCostBudget.verdict(forCPUPercent: cost.cpuPercent) == .withinTarget)
}

@Test func aStaleMeasurementSaysSoRatherThanPassingAsCurrent() {
    let store = defaults("test.idle.stale")
    let now = Date()
    store.set(0.05, forKey: FathomBarConfiguration.measuredIdleCPUKey)
    store.set(
        now.addingTimeInterval(-600).timeIntervalSinceReferenceDate,
        forKey: FathomBarConfiguration.measuredIdleAtKey
    )
    store.set(4, forKey: FathomBarConfiguration.measuredIdleItemCountKey)

    // A low figure from ten minutes ago is not evidence of a low cost now.
    guard case let .notPublished(reason) = MeasuredIdleCost.load(
        defaults: store,
        now: now
    ) else {
        Issue.record("a ten-minute-old figure passed as current")
        return
    }
    #expect(reason.contains("seconds old"))
}

@Test func theItemCountTracksWhatIsActuallyShown() {
    #expect(FathomBarConfiguration().enabledItemCount == 4)
    #expect(
        FathomBarConfiguration(
            showsFreeSpace: true,
            showsHottestSensor: false,
            showsNetworkThroughput: false,
            showsCPULoad: false
        ).enabledItemCount == 1
    )
}
