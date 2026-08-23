import Testing
@testable import FathomKit

private let gb: UInt64 = 1_000_000_000

private func entry(
    _ name: String,
    onDisk: UInt64,
    freed: UInt64
) -> FindingInput.Entry {
    FindingInput.Entry(
        name: name,
        path: "/tmp/\(name)",
        sizeOnDisk: .known(onDisk, source: .fts),
        freedIfDeleted: .known(freed, source: .cloneFamilyAccounting)
    )
}

private func input(
    entries: [FindingInput.Entry] = [],
    actuallyFree: UInt64 = 100 * gb,
    finderAvailable: UInt64 = 100 * gb,
    purgeable: UInt64 = 0,
    snapshots: Int = 0,
    uninspected: Int = 0
) -> FindingInput {
    FindingInput(
        entries: entries,
        actuallyFree: .known(actuallyFree, source: .volumeAvailableCapacityForImportantUsage),
        finderAvailable: .known(finderAvailable, source: .statfsAvailableCapacity),
        purgeable: .known(purgeable, source: .derivedPurgeableCapacity),
        snapshotCount: .known(snapshots, source: .fts),
        uninspectedCount: uninspected
    )
}

@Test func aHealthyMacProducesNoFindings() {
    // Rule 6: Home is allowed to say nothing is wrong. Empty is the expected
    // result here, not a failure to find something.
    #expect(FindingEngine.findings(for: input()).isEmpty)
}

@Test func smallItemsAreNotWorthInterruptingAnyoneAbout() {
    let result = FindingEngine.findings(
        for: input(entries: [entry("Caches", onDisk: 2 * gb, freed: 2 * gb)])
    )
    #expect(result.isEmpty)
}

@Test func aLargeFreeableDirectoryIsAFinding() {
    let result = FindingEngine.findings(
        for: input(entries: [entry("DerivedData", onDisk: 48 * gb, freed: 48 * gb)])
    )
    #expect(result.count == 1)
    #expect(result[0].kind == .freeable)
    #expect(result[0].title.contains("DerivedData"))
    #expect(result[0].subject == .reclaim)
}

@Test func somethingLargeThatFreesNothingIsTheSignatureFinding() {
    let result = FindingEngine.findings(
        for: input(entries: [entry("Docker", onDisk: 62 * gb, freed: 0)])
    )
    #expect(result.count == 1)
    #expect(result[0].kind == .freesNothing)
    // The zero is stated, and the sentence says why, because a bare zero reads
    // as a bug rather than as the answer.
    #expect(result[0].value == "0 bytes")
    #expect(result[0].detail.lowercased().contains("sparse"))
}

@Test func anItemThatIsLargeAndFullyFreeableIsNotAlsoReportedAsFreeingNothing() {
    let result = FindingEngine.findings(
        for: input(entries: [entry("DerivedData", onDisk: 48 * gb, freed: 48 * gb)])
    )
    #expect(result.count == 1)
    #expect(!result.contains { $0.kind == .freesNothing })
}

@Test func finderOverReportingIsAFindingOnlyWhenItIsWorthSaying() {
    let noisy = FindingEngine.findings(
        for: input(actuallyFree: 74 * gb, finderAvailable: 75 * gb)
    )
    #expect(noisy.isEmpty)

    let real = FindingEngine.findings(
        for: input(actuallyFree: 74 * gb, finderAvailable: 118 * gb)
    )
    #expect(real.count == 1)
    #expect(real[0].kind == .conditional)
    #expect(real[0].title.contains("Finder"))
}

@Test func finderReportingLessThanAvailableIsNotAFinding() {
    // The gap only matters in one direction: Finder claiming more than a write
    // would get. The reverse is not a problem anyone needs warning about.
    let result = FindingEngine.findings(
        for: input(actuallyFree: 118 * gb, finderAvailable: 74 * gb)
    )
    #expect(result.isEmpty)
}

@Test func snapshotsAreReportedWithWhatTheyHoldWhenThatIsPublished() {
    let result = FindingEngine.findings(
        for: input(purgeable: 42 * gb, snapshots: 37)
    )
    #expect(result.count == 1)
    #expect(result[0].title.contains("37 local snapshots"))
    #expect(result[0].value == "37")
}

@Test func snapshotsSayWhenTheirHeldSpaceIsNotPublished() {
    let result = FindingEngine.findings(
        for: FindingInput(
            entries: [],
            actuallyFree: .known(100 * gb, source: .statfsAvailableCapacity),
            finderAvailable: .known(100 * gb, source: .statfsAvailableCapacity),
            purgeable: .notPublished(reason: "no purgeable figure"),
            snapshotCount: .known(4, source: .fts),
            uninspectedCount: 0
        )
    )
    #expect(result.count == 1)
    // It does not invent a size for them.
    #expect(result[0].title.contains("does not publish"))
}

@Test func oneSnapshotIsSingular() {
    let result = FindingEngine.findings(for: input(snapshots: 1))
    #expect(result[0].title.contains("1 local snapshot holding"))
    #expect(!result[0].title.contains("snapshots"))
}

@Test func aPartialScanOutranksEverythingElse() {
    let result = FindingEngine.findings(
        for: input(
            entries: [
                entry("A", onDisk: 90 * gb, freed: 90 * gb),
                entry("B", onDisk: 80 * gb, freed: 80 * gb),
            ],
            uninspected: 12
        )
    )
    // Knowing the totals are incomplete changes how every other number reads,
    // so it goes first.
    #expect(result[0].id == "partialscan")
    #expect(result[0].kind == .informational)
}

@Test func atMostFourFindingsAreReturned() {
    let entries = (1...10).map {
        entry("Dir\($0)", onDisk: UInt64($0) * 10 * gb, freed: UInt64($0) * 10 * gb)
    }
    let result = FindingEngine.findings(
        for: input(entries: entries, purgeable: 20 * gb, snapshots: 5, uninspected: 3)
    )
    #expect(result.count == FindingEngine.maximumFindings)
}

@Test func findingsAreOrderedHeaviestFirst() {
    let result = FindingEngine.findings(
        for: input(entries: [
            entry("Small", onDisk: 6 * gb, freed: 6 * gb),
            entry("Huge", onDisk: 90 * gb, freed: 90 * gb),
            entry("Middle", onDisk: 30 * gb, freed: 30 * gb),
        ])
    )
    #expect(result.map(\.weight) == [90 * gb, 30 * gb, 6 * gb])
}

@Test func theOrderDoesNotWobbleBetweenRunsOnEqualWeights() {
    let entries = [
        entry("Beta", onDisk: 10 * gb, freed: 10 * gb),
        entry("Alpha", onDisk: 10 * gb, freed: 10 * gb),
    ]
    let first = FindingEngine.findings(for: input(entries: entries)).map(\.id)
    let second = FindingEngine.findings(for: input(entries: entries)).map(\.id)
    // A list that reshuffles between renders reads as new news.
    #expect(first == second)
}

@Test func anUnpublishedMeasurementProducesNoFindingRatherThanAZeroOne() {
    let result = FindingEngine.findings(
        for: FindingInput(
            entries: [
                FindingInput.Entry(
                    name: "Unknown",
                    path: "/tmp/unknown",
                    sizeOnDisk: .notPublished(reason: "not walked"),
                    freedIfDeleted: .notPublished(reason: "not walked")
                ),
            ],
            actuallyFree: .notPublished(reason: "no capacity"),
            finderAvailable: .notPublished(reason: "no capacity"),
            purgeable: .notPublished(reason: "no purgeable"),
            snapshotCount: .notPublished(reason: "no inventory"),
            uninspectedCount: 0
        )
    )
    // Nothing was measured, so there is nothing to say. Not "0 GB freeable".
    #expect(result.isEmpty)
}

@Test func everyFindingCarriesAValueThatCameFromTheInput() {
    let result = FindingEngine.findings(
        for: input(
            entries: [entry("DerivedData", onDisk: 48 * gb, freed: 48 * gb)],
            purgeable: 42 * gb,
            snapshots: 37
        )
    )
    #expect(!result.isEmpty)
    for finding in result {
        #expect(!finding.value.isEmpty)
        #expect(!finding.detail.isEmpty)
        // Every finding says why it is worth a look, not merely what it is.
        #expect(finding.detail.count > 40)
    }
}
