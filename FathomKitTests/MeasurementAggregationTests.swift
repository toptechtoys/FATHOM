import Foundation
import Testing
@testable import FathomKit

@Test func sumOfKnownValuesIsKnownWithTheStatedSource() {
    let total = FathomKit.Measurement<UInt64>.sum(
        [
            .known(100, source: .fts),
            .known(0, source: .fts),
            .known(23, source: .fts)
        ],
        source: .fts
    )
    #expect(total == .known(123, source: .fts))
}

@Test func sumOfNothingIsAKnownZero() {
    // An empty list has a total, and it is zero — that is arithmetic, not a
    // gap. The gap states are for parts that exist and did not publish.
    #expect(
        FathomKit.Measurement<UInt64>.sum([], source: .fts) == .known(0, source: .fts)
    )
}

@Test func sumWithAnUnpublishedPartIsUnpublishedAndCountsTheMissing() {
    let total = FathomKit.Measurement<UInt64>.sum(
        [
            .known(100, source: .fts),
            .notPublished(reason: "first"),
            .notPublished(reason: "second")
        ],
        source: .fts
    ) { missing, count in
        "\(missing) of \(count) rules did not publish a size."
    }
    #expect(
        total == .notPublished(reason: "2 of 3 rules did not publish a size.")
    )
}

@Test func sumWithAGapKeepsTheGapsTrueMagnitude() {
    // The defect this exists to prevent: three views used to return
    // `.notAttributable(measured: sum, explained: sum)`, asserting the gap
    // was exactly zero. A known part contributes itself to both halves, so
    // the difference of the halves is the real unattributed remainder.
    let total = FathomKit.Measurement<UInt64>.sum(
        [
            .known(50, source: .fts),
            .notAttributable(measured: 100, explained: 60)
        ],
        source: .fts
    )
    #expect(total == .notAttributable(measured: 150, explained: 110))
}

@Test func sumPrefersUnpublishedOverTheGapState() {
    // Weakest state wins, same as `combined`: a total with a missing part is
    // not a total, however well the other parts are attributed.
    let total = FathomKit.Measurement<UInt64>.sum(
        [
            .notAttributable(measured: 100, explained: 60),
            .notPublished(reason: "missing")
        ],
        source: .fts
    )
    guard case .notPublished = total else {
        Issue.record("a missing part did not make the total unpublished")
        return
    }
}

@Test func sumThatOverflowsIsNotAByteCount() {
    let total = FathomKit.Measurement<UInt64>.sum(
        [
            .known(UInt64.max, source: .fts),
            .known(1, source: .fts)
        ],
        source: .fts
    )
    guard case let .notPublished(reason) = total else {
        Issue.record("an overflowed sum came back as a figure")
        return
    }
    #expect(reason.contains("larger than"))
}

@Test func describedSaysTheFigureForAKnownValue() {
    let value = FathomKit.Measurement<UInt64>.known(2_048, source: .fts)
    #expect(value.described { "\($0) B" } == "2048 B")
}

@Test func describedSaysNotPublishedWithoutBorrowingAFigure() {
    let value = FathomKit.Measurement<UInt64>.notPublished(reason: "no pass yet")
    #expect(value.described { "\($0) B" } == "not published")
}

@Test func describedStatesBothHalvesOfAGap() {
    // `notAttributable` is neither a figure nor *not published*; five call
    // sites used to render it as one or the other of those two.
    let value = FathomKit.Measurement<UInt64>.notAttributable(measured: 100, explained: 60)
    #expect(value.described { "\($0) B" } == "100 B measured · 60 B explained")
}

@Test func cloudPlanTotalReportsWhichStateItsItemsAreIn() {
    func item(_ path: String, freeable: FathomKit.Measurement<UInt64>) -> CloudItemRecord {
        CloudItemRecord(
            url: URL(fileURLWithPath: path),
            downloadingStatus: .known(
                "current",
                source: .ubiquitousDownloadingStatus
            ),
            isPinned: .known(false, source: .ubiquitousExcludedFromSync),
            sizeOnDisk: freeable,
            freedIfEvicted: freeable
        )
    }
    let known = CloudEvictionPlan(items: [
        item("/tmp/a", freeable: .known(10, source: .ubiquitousAllocatedSize)),
        item("/tmp/b", freeable: .known(5, source: .ubiquitousAllocatedSize))
    ])
    #expect(
        known.freeableBytes == .known(15, source: .ubiquitousAllocatedSize)
    )

    let missing = CloudEvictionPlan(items: [
        item("/tmp/a", freeable: .known(10, source: .ubiquitousAllocatedSize)),
        item("/tmp/b", freeable: .notPublished(reason: "pin missing"))
    ])
    guard case let .notPublished(reason) = missing.freeableBytes else {
        Issue.record("a plan with an unpublished item published a total")
        return
    }
    #expect(reason.contains("1 of 2"))
}
