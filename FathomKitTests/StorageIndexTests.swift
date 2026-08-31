import Darwin
import Foundation
import FathomKit
import Testing

@Test func indexPersistsACompleteCloneAwareScanTransactionally() async throws {
    let fixture = try IndexFixture()
    defer { fixture.remove() }

    let sourceURL = fixture.scanRoot.appending(path: "source")
    let cloneURL = fixture.scanRoot.appending(path: "clone")
    try Data(repeating: 0x34, count: 1_048_576).write(to: sourceURL)
    guard clonefile(sourceURL.path, cloneURL.path, 0) == 0 else {
        throw CocoaError(.fileWriteUnknown)
    }

    let result = try await StorageEngine().scan(
        at: fixture.scanRoot,
        scope: .subtree
    )
    let accounting = try indexKnownValue(
        StorageAccountingBuilder().build(from: result)
    )
    let index = try StorageIndex(url: fixture.databaseURL)

    #expect(try await index.latestScanSummary() == nil)
    let outcome = try await index.store(
        result: result,
        accounting: accounting,
        startedAt: Date(timeIntervalSince1970: 1_700_000_000)
    )
    guard case let .persisted(scanID) = outcome else {
        Issue.record("The fixture unexpectedly fell back to memory-only")
        return
    }

    let summary = try #require(
        try await index.latestScanSummary()
    )
    #expect(summary.scanID == scanID)
    #expect(summary.rootPath == fixture.scanRoot.path)
    #expect(summary.isComplete)
    #expect(summary.nodeCount == result.entries.count)
    #expect(summary.familyCount == accounting.cloneFamilies.count)
    let expectedSnapshotCount: Int
    if case let .known(snapshots, _) = result.snapshotInventory {
        expectedSnapshotCount = snapshots.count
    } else {
        expectedSnapshotCount = 0
    }
    #expect(summary.snapshotCount == expectedSnapshotCount)
    #expect(summary.schemaVersion == StorageIndex.schemaVersion)
    #expect(try await index.integrityCheck() == "ok")

    await index.close()

    let reopened = try StorageIndex(url: fixture.databaseURL)
    #expect(try await reopened.latestScanSummary() == summary)
    #expect(try await reopened.integrityCheck() == "ok")
    await reopened.close()
}

@Test func traversalStreamsDirectlyIntoTheBoundedSQLiteStage() async throws {
    let fixture = try IndexFixture()
    defer { fixture.remove() }

    let nested = fixture.scanRoot.appending(path: "a/b/c")
    try FileManager.default.createDirectory(
        at: nested,
        withIntermediateDirectories: true
    )
    for index in 0..<128 {
        try Data("entry-\(index)".utf8).write(
            to: nested.appending(path: "file-\(index)")
        )
    }
    try FileManager.default.createSymbolicLink(
        at: fixture.scanRoot.appending(path: "cycle"),
        withDestinationURL: fixture.scanRoot
    )

    let index = try StorageIndex(url: fixture.databaseURL)
    let staged = try await index.stageTraversal(
        at: fixture.scanRoot,
        scope: .subtree,
        startedAt: Date(timeIntervalSince1970: 1_700_000_000)
    )

    #expect(staged.isComplete)
    #expect(staged.entryCount == 133)
    #expect(staged.regularFileCount == 128)
    #expect(
        try await index.stagedEntryCount(scanID: staged.scanID) ==
            Int64(staged.entryCount)
    )
    let extentSummary = try await index.inspectStagedExtents(
        scanID: staged.scanID,
        maximumConcurrentReads: 3
    )
    #expect(extentSummary.inspectedFileCount == 128)
    #expect(extentSummary.failedFileCount == 0)
    #expect(
        try await index.stagedPhysicalExtentCount(scanID: staged.scanID) > 0
    )
    let stagedAccounting = try await index.reduceStagedAccounting(
        scanID: staged.scanID
    )
    let inMemoryResult = try await StorageEngine().scan(
        at: fixture.scanRoot,
        scope: .subtree
    )
    let inMemoryAccounting = try indexKnownValue(
        StorageAccountingBuilder().build(from: inMemoryResult)
    )
    let inMemoryRoot = inMemoryAccounting.nodes[
        Int(inMemoryAccounting.rootID.rawValue)
    ]
    #expect(
        try indexKnownValue(stagedAccounting.sizeOnDisk) ==
            indexKnownValue(inMemoryRoot.subtreeSizeOnDisk)
    )
    #expect(stagedAccounting.physicalSegmentCount > 0)
    let stagedChildren = try await index.stagedChildren(
        scanID: staged.scanID,
        parentID: 0
    )
    #expect(stagedChildren.map(\.name) == ["a", "cycle"])
    #expect(
        stagedChildren.allSatisfy {
            if case .known = $0.sizeOnDisk {
                return true
            }
            return false
        }
    )
    #expect(
        stagedChildren.allSatisfy {
            if case .notPublished = $0.freedIfDeleted {
                return true
            }
            return false
        }
    )
    let subtreeFreeable = try await index.reduceStagedFreeableAccounting(
        scanID: staged.scanID,
        snapshotInventory: .known([], source: .fsSnapshotList),
        snapshotManifests: .known(
            [],
            source: .snapshotManifestDiff
        ),
        openFileIdentities: .known(
            [],
            source: .procOpenFileDescriptors
        )
    )
    #expect(
        subtreeFreeable.freedIfDeleted == .notPublished(
            reason: "A subtree scan cannot prove all physical references"
        )
    )
    #expect(try await index.latestScanSummary() == nil)
    #expect(try await index.integrityCheck() == "ok")
    await index.close()
}

@Test func commandPaletteUsesFTSAndBoundSizeQueries() async throws {
    let fixture = try IndexFixture()
    defer { fixture.remove() }
    let nodeModules = fixture.scanRoot.appending(path: "project/node_modules")
    try FileManager.default.createDirectory(
        at: nodeModules,
        withIntermediateDirectories: true
    )
    try Data(repeating: 0x41, count: 64 * 1_024).write(
        to: nodeModules.appending(path: "package.bin")
    )

    let index = try StorageIndex(url: fixture.databaseURL)
    let staged = try await index.stageTraversal(
        at: fixture.scanRoot,
        scope: .subtree
    )
    _ = try await index.inspectStagedExtents(scanID: staged.scanID)
    _ = try await index.reduceStagedAccounting(scanID: staged.scanID)

    let text = try await index.searchStagedEntries(
        scanID: staged.scanID,
        query: .text("node_modules")
    )
    guard case let .known(textRows, source) = text else {
        Issue.record("Expected FTS results")
        return
    }
    #expect(source == .storageIndexFTS5)
    #expect(textRows.contains { $0.name == "node_modules" })
    #expect(textRows.allSatisfy { row in
        if case .known = row.sizeOnDisk { return true }
        return false
    })

    let large = try await index.searchStagedEntries(
        scanID: staged.scanID,
        query: .minimumAllocatedBytes(1_024)
    )
    guard case let .known(largeRows, _) = large else {
        Issue.record("Expected allocated-size results")
        return
    }
    #expect(largeRows.contains { $0.name == "package.bin" })
    await index.close()
}

@Test func incrementalRefreshRewalksOnlyChangedSubtreeAndRereduces() async throws {
    let fixture = try IndexFixture()
    defer { fixture.remove() }
    let changed = fixture.scanRoot.appending(path: "changed")
    let stable = fixture.scanRoot.appending(path: "stable")
    try FileManager.default.createDirectory(
        at: changed,
        withIntermediateDirectories: true
    )
    try FileManager.default.createDirectory(
        at: stable,
        withIntermediateDirectories: true
    )
    let old = changed.appending(path: "old-payload")
    try Data(repeating: 0x11, count: 4_096).write(to: old)
    try Data(repeating: 0x22, count: 4_096).write(
        to: stable.appending(path: "stable-payload")
    )

    let index = try StorageIndex(url: fixture.databaseURL)
    let staged = try await index.stageTraversal(
        at: fixture.scanRoot,
        scope: .subtree
    )
    _ = try await index.inspectStagedExtents(scanID: staged.scanID)
    _ = try await index.reduceStagedAccounting(scanID: staged.scanID)

    try FileManager.default.removeItem(at: old)
    try Data(repeating: 0x33, count: 8_192).write(
        to: changed.appending(path: "new-payload")
    )
    let issues = try await index.refreshStagedSubtrees(
        scanID: staged.scanID,
        roots: [changed]
    )
    #expect(issues.isEmpty)
    let inspected = try await index.inspectStagedExtents(
        scanID: staged.scanID
    )
    #expect(inspected.inspectedFileCount == 1)
    _ = try await index.reduceStagedAccounting(scanID: staged.scanID)

    let rootChildren = try await index.stagedChildren(
        scanID: staged.scanID,
        parentID: 0
    )
    #expect(Set(rootChildren.map(\.name)) == ["changed", "stable"])
    let changedRow = try #require(
        rootChildren.first { $0.name == "changed" }
    )
    let changedChildren = try await index.stagedChildren(
        scanID: staged.scanID,
        parentID: changedRow.id
    )
    #expect(changedChildren.map(\.name) == ["new-payload"])
    guard case let .known(oldMatches, _) = try await index.searchStagedEntries(
        scanID: staged.scanID,
        query: .text("old-payload")
    ) else {
        Issue.record("FTS did not publish incremental results")
        await index.close()
        return
    }
    #expect(oldMatches.isEmpty)
    #expect(try await index.integrityCheck() == "ok")
    await index.close()
}

@Test func paletteParserRecognizesOnlyExplicitStructuredQueries() {
    #expect(StoragePaletteQuery.parse("clones") == .clones)
    #expect(StoragePaletteQuery.parse("changed this week") == .changedThisWeek)
    #expect(StoragePaletteQuery.parse("over 1.5 GB") == .minimumAllocatedBytes(1_500_000_000))
    #expect(StoragePaletteQuery.parse("node_modules") == .text("node_modules"))
    #expect(StoragePaletteQuery.parse("over nope GB") == .text("over nope GB"))
}

@Test func diagnosticsInspectTheIndexWithoutOpeningAWriter() async throws {
    let fixture = try IndexFixture()
    defer { fixture.remove() }
    let index = try StorageIndex(url: fixture.databaseURL)
    try await index.setDiagnosticValue("12.500000", forKey: "last_scan_duration_seconds")
    await index.close()

    let diagnostics = try StorageIndex.readOnlyDiagnostics(at: fixture.databaseURL)
    #expect(diagnostics.schemaVersion == StorageIndex.schemaVersion)
    #expect(diagnostics.lastScanDurationSeconds == "12.500000")
}

@Test func stagedFreeableSubtractsSnapshotHeldCloneExtents() async throws {
    let fixture = try IndexFixture()
    defer { fixture.remove() }

    let sourceURL = fixture.scanRoot.appending(path: "source")
    let cloneURL = fixture.scanRoot.appending(path: "clone")
    try Data(repeating: 0x5A, count: 1_048_576).write(to: sourceURL)
    guard clonefile(sourceURL.path, cloneURL.path, 0) == 0 else {
        throw CocoaError(.fileWriteUnknown)
    }

    let index = try StorageIndex(url: fixture.databaseURL)
    let staged = try await index.stageTraversal(
        at: fixture.scanRoot,
        scope: .wholeVolume
    )
    let extentSummary = try await index.inspectStagedExtents(
        scanID: staged.scanID
    )
    #expect(extentSummary.failedFileCount == 0)
    let accounting = try await index.reduceStagedAccounting(
        scanID: staged.scanID
    )

    var sourceEntry: StorageEntry?
    try StorageScanner().walk(at: sourceURL) {
        sourceEntry = $0
    }
    let entry = try #require(sourceEntry)
    let sourceMap = try FileExtentReader().inspect(entry)
    guard case let .known(sourceExtents, _) = sourceMap.physicalExtents else {
        Issue.record("The clone fixture has no published physical map")
        return
    }
    let snapshotExtents = sourceExtents.map {
        SnapshotPhysicalExtent(
            device: entry.identity.device,
            deviceOffset: $0.deviceOffset,
            length: $0.length
        )
    }
    let freeable = try await index.reduceStagedFreeableAccounting(
        scanID: staged.scanID,
        snapshotInventory: .known(
            [LocalSnapshot(name: "fixture")],
            source: .fsSnapshotList
        ),
        snapshotManifests: .known(
            [
                SnapshotExtentManifest(
                    snapshotName: "fixture",
                    physicalExtents: snapshotExtents
                )
            ],
            source: .snapshotManifestDiff
        ),
        openFileIdentities: .known(
            [],
            source: .procOpenFileDescriptors
        )
    )

    #expect(try indexKnownValue(accounting.sizeOnDisk) > 0)
    #expect(try indexKnownValue(freeable.freedIfDeleted) == 0)
    let children = try await index.stagedChildren(
        scanID: staged.scanID,
        parentID: 0
    )
    #expect(
        try children.allSatisfy {
            try indexKnownValue($0.freedIfDeleted) == 0
        }
    )
    #expect(try await index.integrityCheck() == "ok")
    await index.close()
}

@Test func stagedSnapshotCoveragePublishesOnlyAfterExactInventoryMatch()
    async throws
{
    let fixture = try IndexFixture()
    defer { fixture.remove() }
    try Data(repeating: 0x31, count: 65_536).write(
        to: fixture.scanRoot.appending(path: "file")
    )

    let index = try StorageIndex(url: fixture.databaseURL)
    let staged = try await index.stageTraversal(
        at: fixture.scanRoot,
        scope: .wholeVolume
    )
    _ = try await index.inspectStagedExtents(scanID: staged.scanID)
    _ = try await index.reduceStagedAccounting(scanID: staged.scanID)
    let coverage = try await index.stageSnapshotReferences(
        scanID: staged.scanID,
        volumeURL: fixture.scanRoot,
        snapshots: [],
        mountPointURL: fixture.root.appending(path: "snapshot-mount")
    )
    let freeable = try await index.reduceStagedFreeableAccounting(
        scanID: staged.scanID,
        snapshotInventory: .known([], source: .fsSnapshotList),
        snapshotCoverage: coverage,
        openFileIdentities: .known(
            [],
            source: .procOpenFileDescriptors
        )
    )

    #expect(try indexKnownValue(freeable.freedIfDeleted) > 0)
    #expect(try await index.integrityCheck() == "ok")
    await index.close()
}

@Test func historyRetentionKeepsRecentRowsAndDailyOldRows() async throws {
    let fixture = try IndexFixture()
    defer { fixture.remove() }
    let index = try StorageIndex(url: fixture.databaseURL)
    let now = Date(timeIntervalSince1970: 2_000_000_000)

    func sample(_ timestamp: TimeInterval, ticks: UInt64) -> StorageHistorySample {
        StorageHistorySample(
            wallTimestamp: Date(timeIntervalSince1970: timestamp),
            monotonicTicks: ticks,
            volumePath: "/",
            actuallyFree: .known(ticks, source: .statfsAvailableCapacity),
            sizeOnDisk: .known(ticks, source: .storageTreeAccounting),
            freedIfDeleted: .known(
                ticks,
                source: .physicalReferenceAccounting
            ),
            purgeable: .known(ticks, source: .derivedPurgeableCapacity)
        )
    }

    let oldDay = now.timeIntervalSince1970 - (120 * 86_400)
    try await index.recordHistory(sample(oldDay, ticks: 1), now: now)
    try await index.recordHistory(sample(oldDay + 60, ticks: 2), now: now)
    try await index.recordHistory(
        sample(now.timeIntervalSince1970 - 60, ticks: 3),
        now: now
    )
    try await index.recordHistory(
        sample(now.timeIntervalSince1970 - 30, ticks: 4),
        now: now
    )

    let rows = try await index.historySamples(volumePath: "/")
    #expect(rows.map(\.monotonicTicks) == [2, 3, 4])
    await index.close()
}

@Test func incrementalHistoryCoalescesWithinOneHour() async throws {
    let fixture = try IndexFixture()
    defer { fixture.remove() }
    let index = try StorageIndex(url: fixture.databaseURL)
    func sample(_ time: TimeInterval, free: UInt64) -> StorageHistorySample {
        StorageHistorySample(
            wallTimestamp: Date(timeIntervalSince1970: time),
            monotonicTicks: free,
            volumePath: "/",
            actuallyFree: .known(free, source: .statfsAvailableCapacity),
            sizeOnDisk: .known(1, source: .storageTreeAccounting),
            freedIfDeleted: .known(1, source: .physicalReferenceAccounting),
            purgeable: .known(1, source: .derivedPurgeableCapacity)
        )
    }
    try await index.recordHistory(
        sample(1_000, free: 10),
        now: Date(timeIntervalSince1970: 1_000),
        coalescingWithin: 3_600
    )
    try await index.recordHistory(
        sample(1_060, free: 20),
        now: Date(timeIntervalSince1970: 1_060),
        coalescingWithin: 3_600
    )
    let rows = try await index.historySamples(volumePath: "/")
    #expect(rows.count == 1)
    #expect(rows.first?.actuallyFree == .known(20, source: .statfsAvailableCapacity))
    await index.close()
}

@Test func directoryGrowthRequiresTwoCompleteScansWithinOneDay() async throws {
    let fixture = try IndexFixture()
    defer { fixture.remove() }
    let growingDirectory = fixture.scanRoot.appending(path: "growing")
    try FileManager.default.createDirectory(
        at: growingDirectory,
        withIntermediateDirectories: false
    )
    let file = growingDirectory.appending(path: "payload")
    try Data(repeating: 0x41, count: 4_096).write(to: file)

    let index = try StorageIndex(url: fixture.databaseURL)
    let firstDate = Date(timeIntervalSince1970: 2_100_000_000)
    let first = try await index.stageTraversal(
        at: fixture.scanRoot,
        scope: .subtree,
        startedAt: firstDate
    )
    _ = try await index.inspectStagedExtents(scanID: first.scanID)
    _ = try await index.reduceStagedAccounting(scanID: first.scanID)

    try Data(repeating: 0x42, count: 32_768).write(to: file)
    let secondDate = firstDate.addingTimeInterval(60 * 60)
    let second = try await index.stageTraversal(
        at: fixture.scanRoot,
        scope: .subtree,
        startedAt: secondDate
    )
    _ = try await index.inspectStagedExtents(scanID: second.scanID)
    _ = try await index.reduceStagedAccounting(scanID: second.scanID)

    let result = try await index.directoryGrowthFindings(
        scanID: second.scanID,
        minimumGrowthBytes: 1,
        now: secondDate
    )
    guard case let .known(findings, source) = result else {
        Issue.record("Expected attributable directory growth")
        await index.close()
        return
    }
    #expect(source == .persistedDirectoryGrowthDelta)
    #expect(findings.contains { $0.path == growingDirectory.path })
    #expect(findings.allSatisfy { $0.growthBytes > 0 })

    let noPrior = try await index.directoryGrowthFindings(
        scanID: first.scanID,
        minimumGrowthBytes: 1,
        now: firstDate
    )
    guard case .notPublished = noPrior else {
        Issue.record("A single scan must not publish growth")
        await index.close()
        return
    }
    await index.close()
}

private struct ExpectedIndexKnownValue: Error {}

@Test
func storageHistoryMarksBackwardsMonotonicClockAsAGap() {
    let earlier = StorageHistorySample(
        wallTimestamp: Date(timeIntervalSince1970: 100),
        monotonicTicks: 10,
        volumePath: "/",
        actuallyFree: .notPublished(reason: "fixture"),
        sizeOnDisk: .notPublished(reason: "fixture"),
        freedIfDeleted: .notPublished(reason: "fixture"),
        purgeable: .notPublished(reason: "fixture")
    )
    let later = StorageHistorySample(
        wallTimestamp: Date(timeIntervalSince1970: 3_700),
        monotonicTicks: 5,
        volumePath: "/",
        actuallyFree: .notPublished(reason: "fixture"),
        sizeOnDisk: .notPublished(reason: "fixture"),
        freedIfDeleted: .notPublished(reason: "fixture"),
        purgeable: .notPublished(reason: "fixture")
    )
    #expect(StorageHistoryClock.gap(from: earlier, to: later)?.duration == 3_600)
}

@Test
func historyComparisonHandlesAppearedAndDisappearedTopLevelRows() throws {
    func sample(
        free: UInt64,
        nodes: [StorageHistoryNode]
    ) -> StorageHistorySample {
        StorageHistorySample(
            volumePath: "/",
            actuallyFree: .known(free, source: .statfsAvailableCapacity),
            sizeOnDisk: .known(100, source: .storageTreeAccounting),
            freedIfDeleted: .known(50, source: .physicalReferenceAccounting),
            purgeable: .known(5, source: .derivedPurgeableCapacity),
            topLevel: nodes
        )
    }
    let old = StorageHistoryNode(
        path: "/old",
        name: "old",
        sizeOnDisk: .known(20, source: .storageTreeAccounting),
        freedIfDeleted: .known(10, source: .physicalReferenceAccounting)
    )
    let new = StorageHistoryNode(
        path: "/new",
        name: "new",
        sizeOnDisk: .known(30, source: .storageTreeAccounting),
        freedIfDeleted: .known(25, source: .physicalReferenceAccounting)
    )
    let comparison = StorageHistoryComparison.compare(
        from: sample(free: 40, nodes: [old]),
        to: sample(free: 25, nodes: [new])
    )
    #expect(
        comparison.actuallyFree == .known(
            -15,
            source: .persistedStorageHistoryDelta
        )
    )
    let rows = try indexKnownValue(comparison.topLevel)
    #expect(
        rows.first { $0.path == "/old" }?.sizeOnDisk == .known(
            -20,
            source: .persistedStorageHistoryDelta
        )
    )
    #expect(
        rows.first { $0.path == "/new" }?.freedIfDeleted == .known(
            25,
            source: .persistedStorageHistoryDelta
        )
    )
}

private func indexKnownValue<Value: Sendable>(
    _ measurement: FathomKit.Measurement<Value>
) throws -> Value {
    guard case let .known(value, _) = measurement else {
        throw ExpectedIndexKnownValue()
    }
    return value
}

private struct IndexFixture {
    let root: URL
    let scanRoot: URL
    let databaseURL: URL

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appending(path: "FathomIndexTests-\(UUID().uuidString)")
        scanRoot = root.appending(path: "scan")
        databaseURL = root.appending(path: "index/fathom.sqlite")
        try FileManager.default.createDirectory(
            at: scanRoot,
            withIntermediateDirectories: true
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}

// A file replaced between the walk and the extent read is the machine moving
// under the scan, not a failure of the scan. A whole-volume pass takes about
// 160 seconds and a Mac in use writes throughout: two consecutive runs of the
// same commit recorded 64 of these and then 2,035, with no code between them.
// Counting that against a zero-issue gate asks the volume to hold still.

@Test func aFileReplacedMidScanIsCountedAsChurnNotFailure() async throws {
    let fixture = try IndexFixture()
    defer { fixture.remove() }

    let steady = fixture.scanRoot.appending(path: "steady.bin")
    let replaced = fixture.scanRoot.appending(path: "replaced.bin")
    try Data(repeating: 0x41, count: 8_192).write(to: steady)
    try Data(repeating: 0x42, count: 8_192).write(to: replaced)

    let index = try StorageIndex(url: fixture.databaseURL)
    let staged = try await index.stageTraversal(
        at: fixture.scanRoot,
        scope: .subtree
    )
    #expect(staged.regularFileCount == 2)

    // Replaced, not edited: a new inode at the same path is what the identity
    // check catches, and it is what an atomic save does.
    try FileManager.default.removeItem(at: replaced)
    try Data(repeating: 0x43, count: 4_096).write(to: replaced)

    let summary = try await index.inspectStagedExtents(scanID: staged.scanID)

    #expect(summary.inspectedFileCount == 1)
    #expect(
        summary.changedDuringScanCount == 1,
        "a replaced file was not recognised as changing under the scan"
    )
    #expect(
        summary.failedFileCount == 0,
        "a replaced file was counted as an inspection failure"
    )
    await index.close()
}
