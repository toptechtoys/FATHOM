import Testing
@testable import FathomKit

@Test func historyKeepsOnlyTheMostRecentWindow() {
    var history = SampleHistory<Double>(capacity: 3)
    for value in 1...5 { history.record(Double(value)) }
    #expect(history.samples.compactMap { $0 } == [3, 4, 5])
    #expect(history.latest == 5)
}

@Test func anUnpublishedSampleIsStoredAsAGapNotDropped() {
    var history = SampleHistory<Double>(capacity: 5)
    history.record(.known(1, source: .hostProcessorLoadInfo))
    history.record(.notPublished(reason: "no reading"))
    history.record(.known(3, source: .hostProcessorLoadInfo))

    // Three intervals elapsed, so three entries exist. Dropping the gap would
    // leave two and silently redate the sample either side of it.
    #expect(history.samples.count == 3)
    #expect(history.samples[1] == nil)
    #expect(history.gapCount == 1)
}

@Test func aGapIsNeverFilledWithTheLastKnownValue() {
    var history = SampleHistory<Double>(capacity: 4)
    history.record(42)
    history.recordGap()
    // Carrying 42 forward would draw a flat line that reads as a measurement.
    #expect(history.samples[1] == nil)
    #expect(history.latest == 42)
}

@Test func notAttributableRecordsTheMeasuredFigure() {
    var history = SampleHistory<Double>(capacity: 4)
    history.record(.notAttributable(measured: 9.8, explained: 9.45))
    // The total was genuinely measured; what is unattributed is its breakdown.
    #expect(history.samples == [9.8])
    #expect(history.gapCount == 0)
}

@Test func runsSplitTheWindowAtEveryGap() {
    var history = SampleHistory<Double>(capacity: 8)
    history.record(1)
    history.record(2)
    history.recordGap()
    history.record(4)
    history.recordGap()
    history.recordGap()
    history.record(7)

    let runs = history.runs
    #expect(runs.count == 3)
    #expect(runs[0].start == 0 && runs[0].values == [1, 2])
    #expect(runs[1].start == 3 && runs[1].values == [4])
    #expect(runs[2].start == 6 && runs[2].values == [7])
}

@Test func runsAreEmptyWhenNothingWasEverPublished() {
    var history = SampleHistory<Double>(capacity: 3)
    history.recordGap()
    history.recordGap()
    #expect(history.runs.isEmpty)
    #expect(history.isEntirelyGaps)
    #expect(history.latest == nil)
    #expect(history.peak == nil)
}

@Test func anEmptyHistoryIsNotAWindowOfGaps() {
    let history = SampleHistory<Double>(capacity: 3)
    // Nothing has been sampled yet, which is different from having sampled and
    // found nothing. The first says "wait", the second says "cannot know".
    #expect(history.isEmpty)
    #expect(!history.isEntirelyGaps)
}

@Test func peakScalesAChartWithNoNaturalCeiling() {
    var history = SampleHistory<Double>(capacity: 5)
    history.record(1200)
    history.recordGap()
    history.record(4800)
    history.record(300)
    #expect(history.peak == 4800)
}

@Test func gapsSurviveEvictionInOrder() {
    var history = SampleHistory<Double>(capacity: 3)
    history.record(1)
    history.recordGap()
    history.record(3)
    history.record(4)
    // The oldest entry falls off; the gap keeps its position relative to the
    // samples around it.
    #expect(history.samples.count == 3)
    #expect(history.samples[0] == nil)
    #expect(history.samples[1] == 3)
    #expect(history.samples[2] == 4)
}
