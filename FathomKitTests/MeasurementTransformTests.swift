import Testing
@testable import FathomKit

@Test func mapKeepsTheKnownStateAndItsSource() {
    let bytes = Measurement<UInt64>.known(2_048, source: .statfsAvailableCapacity)
    let kilobytes = bytes.map { Double($0) / 1_024 }
    guard case let .known(value, source) = kilobytes else {
        Issue.record("map lost the known state")
        return
    }
    #expect(value == 2)
    #expect(source == .statfsAvailableCapacity)
}

@Test func mapNeverInventsAValueForAnUnpublishedReading() {
    let missing = Measurement<UInt64>.notPublished(reason: "no SMART log")
    let mapped = missing.map { Double($0) * 100 }
    guard case let .notPublished(reason) = mapped else {
        Issue.record("map turned an unpublished reading into a value")
        return
    }
    #expect(reason == "no SMART log")
}

@Test func mapTransformsBothHalvesOfAnUnattributedReading() {
    let written = Measurement<UInt64>.notAttributable(
        measured: 10_000, explained: 9_640
    )
    let gigabytes = written.map { Double($0) / 1_000 }
    guard case let .notAttributable(measured, explained) = gigabytes else {
        Issue.record("map collapsed the unattributed state")
        return
    }
    // Losing the explained half here is how a 3.6% gap silently disappears.
    #expect(measured == 10)
    #expect(explained == 9.64)
}

@Test func combiningTwoKnownReadingsIsKnown() {
    let total = Measurement<UInt64>.known(16, source: .hostProcessorLoadInfo)
    let free = Measurement<UInt64>.known(4, source: .hostProcessorLoadInfo)
    let used = total.combined(with: free) { Double($0 - $1) / Double($0) }
    guard case let .known(value, _) = used else {
        Issue.record("expected a known result")
        return
    }
    #expect(abs(value - 0.75) < 0.0001)
}

@Test func aRatioWithAnUnpublishedDenominatorIsNotPublished() {
    let total = Measurement<UInt64>.notPublished(reason: "total unavailable")
    let free = Measurement<UInt64>.known(4, source: .hostProcessorLoadInfo)
    let used = total.combined(with: free) { Double($0 - $1) / Double($0) }
    guard case let .notPublished(reason) = used else {
        Issue.record("a fraction of an unknown total was reported as known")
        return
    }
    #expect(reason == "total unavailable")
}

@Test func anUnpublishedNumeratorAlsoPropagatesItsReason() {
    let total = Measurement<UInt64>.known(16, source: .hostProcessorLoadInfo)
    let free = Measurement<UInt64>.notPublished(reason: "free pages unavailable")
    let used = total.combined(with: free) { Double($0 - $1) / Double($0) }
    guard case let .notPublished(reason) = used else {
        Issue.record("expected the missing side to win")
        return
    }
    #expect(reason == "free pages unavailable")
}

@Test func combiningInheritsAnUnattributedGap() {
    let written = Measurement<UInt64>.notAttributable(measured: 100, explained: 96)
    let hours = Measurement<UInt64>.known(10, source: .getLoadAverage)
    let perHour = written.combined(with: hours) { Double($0) / Double($1) }
    guard case let .notAttributable(measured, explained) = perHour else {
        Issue.record("a total built on an unattributed part lost the gap")
        return
    }
    #expect(measured == 10)
    #expect(abs(explained - 9.6) < 0.0001)
}

@Test func usedFractionIsNotPublishedWhenTheTotalIsNot() {
    let snapshot = MemorySnapshot(
        totalBytes: .notPublished(reason: "host_statistics64 unavailable"),
        freeBytes: .known(4_000, source: .hostProcessorLoadInfo),
        activeBytes: .known(0, source: .hostProcessorLoadInfo),
        inactiveBytes: .known(0, source: .hostProcessorLoadInfo),
        speculativeBytes: .known(0, source: .hostProcessorLoadInfo),
        wiredBytes: .known(0, source: .hostProcessorLoadInfo),
        compressedBytes: .known(0, source: .hostProcessorLoadInfo),
        purgeableBytes: .known(0, source: .hostProcessorLoadInfo),
        swapUsedBytes: .known(0, source: .hostProcessorLoadInfo),
        swapTotalBytes: .known(0, source: .hostProcessorLoadInfo)
    )
    guard case .notPublished = snapshot.usedFraction else {
        Issue.record("reported a fraction of an unknown total")
        return
    }
}
