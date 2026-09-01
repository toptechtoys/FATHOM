import Dispatch
import Foundation
import Testing
@testable import FathomKit

// The menu bar widget publishes a number about FATHOM itself, which makes it
// the one place where the product's own claim and the product's own honesty
// are the same object. Until this file existed nothing tested any of it: both
// schemes in `project.yml` declare `testTargets: []`, so the widget's
// controller and sampler were checked by the compiler alone.
//
// Nothing here asserts a plausible CPU percentage. Every figure below is
// arithmetic on a constructed input — 3 ms of CPU across 1 s of wall time is
// 0.3% of one core because that is what division says, not because 0.3 looks
// like a menu bar widget.

// MARK: - Fixtures

private func capacity(free: UInt64) -> VolumeCapacitySnapshot {
    VolumeCapacitySnapshot(
        actuallyFree: .known(
            free,
            source: .volumeAvailableCapacityForImportantUsage
        ),
        finderAvailable: .known(free, source: .statfsAvailableCapacity),
        purgeable: .notPublished(reason: "not part of this test")
    )
}

private func capacityGap() -> VolumeCapacitySnapshot {
    VolumeCapacitySnapshot(
        actuallyFree: .notPublished(reason: "statfs failed"),
        finderAvailable: .notPublished(reason: "statfs failed"),
        purgeable: .notPublished(reason: "statfs failed")
    )
}

private func cpu(busy: Double) -> CPULoadSnapshot {
    CPULoadSnapshot(
        cores: .notPublished(reason: "not part of this test"),
        aggregateBusy: .known(busy, source: .hostProcessorLoadInfo),
        aggregateUser: .known(busy, source: .hostProcessorLoadInfo),
        aggregateSystem: .known(0, source: .hostProcessorLoadInfo),
        aggregateIdle: .known(1 - busy, source: .hostProcessorLoadInfo),
        loadAverages: .notPublished(reason: "not part of this test"),
        performanceLogicalCPUCount: .notPublished(
            reason: "not part of this test"
        ),
        efficiencyLogicalCPUCount: .notPublished(
            reason: "not part of this test"
        )
    )
}

private func cpuGap() -> CPULoadSnapshot {
    let reason = "host_processor_info failed"
    return CPULoadSnapshot(
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

private func network(
    receiving rates: [Double?]
) -> NetworkSnapshot {
    let interfaces = rates.enumerated().map { index, rate in
        NetworkInterfaceMetrics(
            name: "en\(index)",
            receivedBytes: 0,
            sentBytes: 0,
            receivedBytesPerSecond: rate.map {
                FathomKit.Measurement.known(
                    $0,
                    source: .sysctlNetworkInterfaceList
                )
            } ?? .notPublished(reason: "no delta yet"),
            sentBytesPerSecond: .notPublished(reason: "not part of this test")
        )
    }
    return NetworkSnapshot(
        interfaces: .known(interfaces, source: .sysctlNetworkInterfaceList),
        localAddresses: .notPublished(reason: "not part of this test"),
        configuration: NetworkConfigurationSnapshot(
            primaryInterface: .notPublished(reason: "not part of this test"),
            router: .notPublished(reason: "not part of this test"),
            dnsServers: .notPublished(reason: "not part of this test")
        )
    )
}

private func networkGap() -> NetworkSnapshot {
    NetworkSnapshot(
        interfaces: .notPublished(reason: "interface counters unavailable"),
        localAddresses: .notPublished(reason: "interface counters unavailable"),
        configuration: NetworkConfigurationSnapshot(
            primaryInterface: .notPublished(reason: "unavailable"),
            router: .notPublished(reason: "unavailable"),
            dnsServers: .notPublished(reason: "unavailable")
        )
    )
}

private func temperatures(
    _ values: [Double?]
) -> FathomKit.Measurement<[TemperatureSensorReading]> {
    .known(
        values.enumerated().map { index, value in
            TemperatureSensorReading(
                name: "sensor\(index)",
                celsius: value.map {
                    FathomKit.Measurement.known(
                        $0,
                        source: .ioHIDTemperatureEvent
                    )
                } ?? .notPublished(reason: "sensor did not report")
            )
        },
        source: .ioHIDTemperatureEvent
    )
}

private func presentation(
    configuration: FathomBarConfiguration = FathomBarConfiguration(),
    capacity capacitySnapshot: VolumeCapacitySnapshot = capacityGap(),
    cpu cpuSnapshot: CPULoadSnapshot = cpuGap(),
    network networkSnapshot: NetworkSnapshot = networkGap(),
    temperatures temperatureMeasurement: FathomKit.Measurement<
        [TemperatureSensorReading]
    > = .notPublished(reason: "sensors unavailable")
) -> FathomBarPresentation {
    FathomBarPresentation(
        configuration: configuration,
        capacity: capacitySnapshot,
        cpu: cpuSnapshot,
        network: networkSnapshot,
        temperatures: temperatureMeasurement
    )
}

/// A clock the test moves by hand, so staleness is decided by arithmetic
/// rather than by how long the test suite happened to take.
private final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var instant: Date

    init(_ start: Date) { instant = start }

    var date: Date {
        lock.lock()
        defer { lock.unlock() }
        return instant
    }

    func advance(_ seconds: TimeInterval) {
        lock.lock()
        instant = instant.addingTimeInterval(seconds)
        lock.unlock()
    }
}

private actor ReadCounter {
    private var count = 0
    func next() -> Int {
        count += 1
        return count
    }
}

private func store(_ name: String) -> UserDefaults {
    let defaults = UserDefaults(suiteName: name)!
    defaults.removePersistentDomain(forName: name)
    return defaults
}

// MARK: - What a failed read renders as

@Test func everyFailedReadRendersAsAGapRatherThanAsANumber() {
    let drawn = presentation()
    #expect(drawn.title == "— GB  —°  —/s  —%")
    #expect(drawn.title.rangeOfCharacter(from: .decimalDigits) == nil)
    for phrase in [
        "free space not published",
        "hottest sensor not published",
        "network throughput not published",
        "CPU load not published"
    ] {
        #expect(drawn.accessibilityLabel.contains(phrase))
    }
}

@Test func beforeTheFirstSampleTheWidgetSaysSoRatherThanShowingAZero() {
    let waiting = FathomBarPresentation.notYetSampled
    #expect(waiting.title.rangeOfCharacter(from: .decimalDigits) == nil)
    #expect(waiting.accessibilityLabel.contains("not yet published"))
}

@Test func anUnattributableReadingIsAGapAndNotZero() {
    // The three states are not two. A capacity the volume could not attribute
    // must not fall through to a number, and must say which of the two gaps it
    // is rather than being merged into "not published".
    let drawn = presentation(
        capacity: VolumeCapacitySnapshot(
            actuallyFree: .notAttributable(measured: 900, explained: 400),
            finderAvailable: .notPublished(reason: "not part of this test"),
            purgeable: .notPublished(reason: "not part of this test")
        )
    )
    #expect(drawn.title.hasPrefix("— GB"))
    #expect(drawn.accessibilityLabel.contains("free space not attributable"))
}

@Test func aSensorInventoryWithNoReadingsIsNotAZeroDegreeMachine() {
    // `max()` of an empty array is nil, and the fix a hurried reader reaches
    // for is `?? 0`. A machine reporting no temperature is not a machine at
    // zero degrees.
    let drawn = presentation(temperatures: temperatures([nil, nil]))
    #expect(drawn.title.contains("—°"))
    #expect(drawn.accessibilityLabel.contains("hottest sensor not published"))
}

@Test func theHottestSensorIsTheHottestOfTheOnesThatPublished() {
    let drawn = presentation(temperatures: temperatures([41, nil, 57, 39]))
    #expect(drawn.title.contains("57°"))
    #expect(drawn.accessibilityLabel.contains("hottest sensor 57 degrees"))
}

@Test func networkThroughputIsTheSumOfTheInterfacesThatPublished() {
    // 1,000 + 2,000 B/s, with an interface that has no delta yet contributing
    // nothing rather than a zero that would drag an average down.
    let drawn = presentation(network: network(receiving: [1_000, nil, 2_000]))
    #expect(drawn.title.contains("↓\(ByteString.file(rounding: 3_000))/s"))
}

@Test func cpuLoadIsRenderedAsAWholePercentOfTheFraction() {
    #expect(presentation(cpu: cpu(busy: 0.25)).title.contains("25%"))
}

@Test func anItemThatIsSwitchedOffIsNotDrawnAndIsNotCounted() {
    let drawn = presentation(
        configuration: FathomBarConfiguration(
            showsFreeSpace: true,
            showsHottestSensor: false,
            showsNetworkThroughput: false,
            showsCPULoad: true
        ),
        capacity: capacity(free: 8_000_000_000),
        cpu: cpu(busy: 0.5)
    )
    #expect(drawn.title == "\(ByteString.file(8_000_000_000))  50%")
    #expect(drawn.itemCount == 2)
    #expect(!drawn.title.contains("°"))
}

@Test func theDrawnItemCountIsWhatTheConfigurationEnabled() {
    for configuration in [
        FathomBarConfiguration(),
        FathomBarConfiguration(
            showsFreeSpace: false,
            showsHottestSensor: true,
            showsNetworkThroughput: false,
            showsCPULoad: false
        ),
        FathomBarConfiguration(
            showsFreeSpace: false,
            showsHottestSensor: false,
            showsNetworkThroughput: false,
            showsCPULoad: false
        )
    ] {
        #expect(
            presentation(configuration: configuration).itemCount
                == configuration.enabledItemCount
        )
    }
}

// MARK: - Staleness inside the widget

@Test func aReadingMayBeReusedForItsCadenceAndNoLonger() {
    let taken = Date(timeIntervalSinceReferenceDate: 0)
    var cache = FathomBarReadingCache<Int>(maximumAge: 11)
    cache.store(7, at: taken)
    #expect(cache.value(at: taken.addingTimeInterval(11)) == 7)
    #expect(cache.value(at: taken.addingTimeInterval(11.001)) == nil)
    // A clock that went backwards is a reading we cannot place in time.
    #expect(cache.value(at: taken.addingTimeInterval(-1)) == nil)
}

@Test func theReuseWindowCoversTheCadenceThatProducedTheReading() {
    // Capacity is read every other tick, so the value drawn on the tick in
    // between is one interval old and must still be allowed. If the window
    // were ever tightened below the cadence the widget would render a gap on
    // every second tick.
    #expect(
        FathomBarSamplingPlan.reuseWindow(
            everyTicks: FathomBarSamplingPlan.capacityEveryTicks
        ) >= Double(FathomBarSamplingPlan.capacityEveryTicks)
            * FathomBarSamplingPlan.intervalSeconds
    )
    #expect(
        FathomBarSamplingPlan.reuseWindow(
            everyTicks: FathomBarSamplingPlan.temperatureEveryTicks
        ) >= Double(FathomBarSamplingPlan.temperatureEveryTicks)
            * FathomBarSamplingPlan.intervalSeconds
    )
}

@Test func aFigureFromBeforeTheWidgetStoppedIsNotRedrawnAsCurrent() async {
    // The sampling loop is cancelled whenever the menu bar is hidden or the
    // Mac sleeps, and the tick counter survives it. Without an age limit the
    // first tick after a resume falls on a skipped capacity read and redraws
    // whatever was measured before the gap — an hour-old free-space figure
    // presented in the same type as a current one.
    let clock = TestClock(Date(timeIntervalSinceReferenceDate: 0))
    let reads = ReadCounter()
    let sampler = FathomBarSampler(
        readers: FathomBarReaders(
            cpu: { cpuGap() },
            network: { networkGap() },
            capacity: {
                await reads.next() == 1
                    ? capacity(free: 100_000_000_000)
                    : capacity(free: 200_000_000_000)
            },
            temperatures: { .notPublished(reason: "not part of this test") }
        ),
        configuration: { FathomBarConfiguration() },
        now: { clock.date }
    )
    let first = await sampler.sample()
    #expect(first.title.contains(ByteString.file(100_000_000_000)))

    // Tick 1 skips the capacity read by design; five seconds later the cached
    // figure is still the honest answer.
    clock.advance(FathomBarSamplingPlan.intervalSeconds)
    let reused = await sampler.sample()
    #expect(reused.title.contains(ByteString.file(100_000_000_000)))

    // Tick 2 reads again.
    clock.advance(FathomBarSamplingPlan.intervalSeconds)
    let reread = await sampler.sample()
    #expect(reread.title.contains(ByteString.file(200_000_000_000)))

    // Hidden for an hour. Tick 3 skips the read, and the cached figure has
    // outlived its cadence.
    clock.advance(3_600)
    let afterTheGap = await sampler.sample()
    #expect(afterTheGap.title.hasPrefix("— GB"))
    #expect(
        afterTheGap.accessibilityLabel.contains("free space not published")
    )
}

@Test func aReadThatFailsRendersAsAGapRatherThanAsTheLastGoodValue() async {
    let clock = TestClock(Date(timeIntervalSinceReferenceDate: 0))
    let reads = ReadCounter()
    let sampler = FathomBarSampler(
        readers: FathomBarReaders(
            cpu: {
                await reads.next() == 1 ? cpu(busy: 0.4) : cpuGap()
            },
            network: { networkGap() },
            capacity: { capacityGap() },
            temperatures: { .notPublished(reason: "not part of this test") }
        ),
        configuration: { FathomBarConfiguration() },
        now: { clock.date }
    )
    #expect(await sampler.sample().title.contains("40%"))
    clock.advance(FathomBarSamplingPlan.intervalSeconds)
    // The reader answered, and what it answered was a gap. A cache that
    // preferred the last number to the current answer would keep drawing 40%.
    let second = await sampler.sample()
    #expect(second.title.contains("—%"))
    #expect(!second.title.contains("40%"))
}

// MARK: - What the widget publishes about itself

@Test func aFailedSelfMeasurementPublishesNothingAtAll() {
    let defaults = store("test.bar.failedSample")
    let outcome = MeasuredIdleCost.publication(
        cost: .notPublished(reason: "A percentage needs two samples."),
        itemCountAtStartOfInterval: 4,
        itemCountNow: 4,
        now: Date()
    )
    guard case let .withheld(reason) = outcome else {
        Issue.record("published a cost from a sample that failed")
        return
    }
    #expect(reason.contains("two samples"))
    // Nothing was written, so the app still reports the gap rather than a zero.
    guard case .notPublished = MeasuredIdleCost.load(defaults: defaults) else {
        Issue.record("a failed sample left a figure behind")
        return
    }
}

@Test func withholdingLetsTheOldFigureAgeRatherThanRefreshingIt() {
    // The dangerous version of "publish nothing" is publishing the old
    // percentage with a new date, which makes a stopped widget look busy.
    let defaults = store("test.bar.withheldAges")
    let measured = Date(timeIntervalSinceReferenceDate: 1_000)
    MeasuredIdleCost(cpuPercent: 0.3, measuredAt: measured, itemCount: 4)
        .write(to: defaults)

    let outcome = MeasuredIdleCost.publication(
        cost: .notPublished(reason: "The CPU counter moved backwards."),
        itemCountAtStartOfInterval: 4,
        itemCountNow: 4,
        now: measured.addingTimeInterval(5)
    )
    guard case .withheld = outcome else {
        Issue.record("published a cost from a counter that went backwards")
        return
    }
    let stale = measured.addingTimeInterval(
        MeasuredIdleCost.freshnessWindow + 1
    )
    guard case let .notPublished(reason) = MeasuredIdleCost.load(
        defaults: defaults,
        now: stale
    ) else {
        Issue.record("a figure older than the freshness window read as current")
        return
    }
    #expect(reason.contains("seconds old"))
}

@Test func aCostMeasuredAcrossAConfigurationChangeBelongsToNeitherCount() {
    let outcome = MeasuredIdleCost.publication(
        cost: .known(0.3, source: .procPidRusage),
        itemCountAtStartOfInterval: 4,
        itemCountNow: 2,
        now: Date()
    )
    guard case let .withheld(reason) = outcome else {
        Issue.record("filed a cost under a count it was not measured with")
        return
    }
    #expect(reason.contains("4"))
    #expect(reason.contains("2"))
}

@Test func aPublishedCostAlwaysCarriesTheCountItWasMeasuredWith() {
    let defaults = store("test.bar.pairing")
    let drawn = presentation(
        configuration: FathomBarConfiguration(
            showsFreeSpace: true,
            showsHottestSensor: false,
            showsNetworkThroughput: true,
            showsCPULoad: false
        )
    )
    let now = Date()
    let outcome = MeasuredIdleCost.publication(
        cost: .known(0.12, source: .procPidRusage),
        itemCountAtStartOfInterval: drawn.itemCount,
        itemCountNow: drawn.itemCount,
        now: now
    )
    guard case let .published(cost) = outcome else {
        Issue.record("withheld a cost that was measured under one count")
        return
    }
    #expect(cost.itemCount == 2)
    cost.write(to: defaults)
    guard case let .known(readBack, source) = MeasuredIdleCost.load(
        defaults: defaults,
        now: now
    ) else {
        Issue.record("what was written did not read back")
        return
    }
    #expect(readBack.itemCount == drawn.itemCount)
    #expect(readBack == cost)
    #expect(source == .procPidRusage)
    #expect(
        MeasuredIdleCost.menuTitle(for: .known(readBack, source: source))
            .contains("2 items")
    )
}

@Test func aFigureWithNoItemCountBesideItIsRefused() {
    // The three keys are three separate writes. A process that dies between
    // them leaves a percentage with no count, `integer(forKey:)` answers 0,
    // and the app's own chrome prints "measured with 0 items".
    let defaults = store("test.bar.tornWrite")
    defaults.set(0.31, forKey: FathomBarConfiguration.measuredIdleCPUKey)
    defaults.set(
        Date().timeIntervalSinceReferenceDate,
        forKey: FathomBarConfiguration.measuredIdleAtKey
    )
    guard case let .notPublished(reason) = MeasuredIdleCost.load(
        defaults: defaults
    ) else {
        Issue.record("published a cost paired with a count nobody measured")
        return
    }
    #expect(reason.contains("item count"))
}

@Test func theFigureTheAppDisplaysIsTheMeasuredOneAndNeverTheBudget() {
    // 3 ms of CPU across 1 s of wall time is 0.3% of one core. That is the
    // whole fixture: the number is division, not a plausible-looking constant.
    // It is deliberately over the 0.2% target, because a pipeline that quietly
    // substituted the budget would still look right if the measurement agreed
    // with it.
    let defaults = store("test.bar.measuredNotBudget")
    let measured = ProcessCPUSampler.percentage(
        from: ProcessResourceSample(cpuNanoseconds: 0, timestamp: 0),
        to: ProcessResourceSample(
            cpuNanoseconds: 3_000_000,
            timestamp: 1_000_000_000
        ),
        nanosecondsPerTick: 1
    )
    guard case let .known(percent, _) = measured else {
        Issue.record("the arithmetic did not produce a percentage")
        return
    }
    #expect(abs(percent - 0.3) < 0.000_1)
    #expect(percent != IdleCostBudget.targetCPUPercent)

    let now = Date()
    guard case let .published(cost) = MeasuredIdleCost.publication(
        cost: measured,
        itemCountAtStartOfInterval: 4,
        itemCountNow: 4,
        now: now
    ) else {
        Issue.record("withheld a measurement it should have published")
        return
    }
    cost.write(to: defaults)
    guard case let .known(readBack, _) = MeasuredIdleCost.load(
        defaults: defaults,
        now: now
    ) else {
        Issue.record("what was written did not read back")
        return
    }
    #expect(abs(readBack.cpuPercent - percent) < 0.000_1)
    #expect(
        IdleCostBudget.verdict(forCPUPercent: readBack.cpuPercent)
            == .overTargetWithinBlocking
    )
    let title = MeasuredIdleCost.menuTitle(
        for: .known(readBack, source: .procPidRusage)
    )
    // The measured figure, never the budget. Written as "0.3" rather than
    // "0.30" since the title moved to significant digits, so that a cost of
    // 0.00671% can state itself instead of rounding to a shared "0.01%".
    #expect(title.contains("0.3"))
    #expect(!title.contains("0.2"))
}

// The widget's own cost is a shipped number — non-negotiable 8 — and two
// decimal places could not show it. Every reading taken on the reference Mac —
// 0.00919, 0.00671, 0.00761, 0.00590, 0.01060, 0.00810 — rendered as the same
// "0.01%", and anything under 0.005 rendered as "0.00% CPU": a claim of no cost
// from a product whose first rule is never to render a number it cannot
// justify.

@Test func theIdleCostShowsTheFigureItActuallyMeasured() {
    let measured = [0.00919, 0.00671, 0.00761, 0.00590, 0.01060, 0.00810]
    let titles = Set(
        measured.map { value in
            MeasuredIdleCost.menuTitle(
                for: .known(
                    MeasuredIdleCost(
                        cpuPercent: value,
                        measuredAt: Date(timeIntervalSinceReferenceDate: 0),
                        itemCount: 4
                    ),
                    source: .procPidRusage
                )
            )
        }
    )
    #expect(
        titles.count == measured.count,
        "\(measured.count) different costs collapsed to \(titles.count) titles"
    )
}

@Test func aCostBelowAHundredthIsNotShownAsZero() {
    let title = MeasuredIdleCost.menuTitle(
        for: .known(
            MeasuredIdleCost(
                cpuPercent: 0.0049,
                measuredAt: Date(timeIntervalSinceReferenceDate: 0),
                itemCount: 4
            ),
            source: .procPidRusage
        )
    )
    // "0.00% CPU" would say the widget is free. It is not.
    #expect(
        !title.contains("0.00%"),
        "a real cost was rendered as zero: \(title)"
    )
    #expect(title.contains("0.0049"))
}

@Test func theWidgetMenuStopsSayingNotPublishedOnceItHasAFigure() {
    // It used to say "Idle cost: not published" as a literal set at launch and
    // never updated, while writing a figure to the shared defaults every five
    // seconds.
    #expect(
        MeasuredIdleCost.menuTitle(for: .notPublished(reason: "no samples yet"))
            == "Idle cost: not published"
    )
    let cost = MeasuredIdleCost(
        cpuPercent: 0.15,
        measuredAt: Date(),
        itemCount: 1
    )
    let title = MeasuredIdleCost.menuTitle(
        for: .known(cost, source: .procPidRusage)
    )
    #expect(title.contains("0.15"))
    #expect(title.contains("1 item"))
    #expect(!title.contains("1 items"))
}

@Test func theFreshnessWindowOutlastsSeveralSamplingIntervals() {
    // Freshness and cadence are two constants in two types that only mean
    // anything together: a window shorter than the interval would report every
    // figure the widget ever published as stale.
    #expect(
        MeasuredIdleCost.freshnessWindow
            >= 3 * FathomBarSamplingPlan.intervalSeconds
    )
    // A rate and its interval are the same fact stated twice; anything that
    // prints one must be able to derive it from the other.
    #expect(
        abs(
            FathomBarSamplingPlan.refreshHertz
                * FathomBarSamplingPlan.intervalSeconds - 1
        ) < 0.000_1
    )
}

// MARK: - Memory pressure

@Test func criticalPressureOutranksWarningInTheSameEvent() {
    // The event is an option set and one delivery can carry both bits.
    #expect(
        FathomBarMemoryPressure.from(events: [.warning, .critical])
            == .critical
    )
    #expect(FathomBarMemoryPressure.from(events: [.warning]) == .warning)
    #expect(FathomBarMemoryPressure.from(events: [.critical]) == .critical)
    // Rule 7: a machine under no pressure gets no badge.
    #expect(FathomBarMemoryPressure.from(events: [.normal]) == nil)
}

@Test func pressureIsSpokenAfterTheReadingRatherThanInsteadOfIt() {
    let drawn = presentation(cpu: cpu(busy: 0.1))
    let quiet = drawn.buttonContent(pressure: nil)
    #expect(quiet.pressureLine == nil)
    #expect(quiet.accessibilityLabel == drawn.accessibilityLabel)

    let loud = drawn.buttonContent(pressure: .critical)
    #expect(loud.title == drawn.title)
    #expect(loud.pressureLine == "MEMORY CRITICAL")
    #expect(loud.accessibilityLabel.hasPrefix(drawn.accessibilityLabel))
    #expect(loud.accessibilityLabel.hasSuffix("memory critical"))
}
