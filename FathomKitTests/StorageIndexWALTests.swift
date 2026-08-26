import Darwin
import Foundation
@testable import FathomKit
import Testing

// Every byte these tests read is written by the test. Nothing here replays a
// recorded index, and nothing here touches the index the app keeps in
// Application Support.

@Test func closingTheIndexTruncatesTheWriteAheadLog() async throws {
    let fixture = try WALIndexFixture()
    defer { fixture.remove() }
    try fixture.makeScanFiles(count: 200)

    let index = try StorageIndex(url: fixture.databaseURL)
    let staged = try await index.stageTraversal(
        at: fixture.scanRoot,
        scope: .subtree
    )

    // The traversal now truncates its own log on the way out, which is the
    // first half of the fix: a completed scan no longer leaves a log at all.
    #expect(walBytes(fixture) == 0)

    // So the log has to be grown again to test close(). Four hundred
    // single-statement transactions leave the log carrying four hundred
    // superseded page images and no checkpoint — the same shape, in
    // miniature, as the 3.84 GB the owner's machine was holding.
    for probe in 0..<400 {
        try await index.setDiagnosticValue(
            "\(probe)",
            forKey: "wal_growth_probe"
        )
    }
    #expect(walBytes(fixture) > 0)

    await index.close()
    #expect(walBytes(fixture) == 0)

    // Truncating is only correct if it kept the data. A -wal holds committed
    // frames the database file does not have yet, so a "reclaim" that lost
    // them would pass the assertion above and destroy the index.
    let reopened = try StorageIndex(url: fixture.databaseURL)
    #expect(try await reopened.integrityCheck() == "ok")
    #expect(
        try await reopened.stagedEntryCount(scanID: staged.scanID) ==
            Int64(staged.entryCount)
    )
    await reopened.close()
}

@Test func anIndexLeftByAnInterruptedScanIsReclaimedOnTheNextOpen()
    async throws
{
    let fixture = try WALIndexFixture()
    defer { fixture.remove() }
    try fixture.makeScanFiles(count: 120)

    let index = try StorageIndex(url: fixture.databaseURL)
    let staged = try await index.stageTraversal(
        at: fixture.scanRoot,
        scope: .subtree
    )
    for probe in 0..<400 {
        try await index.setDiagnosticValue(
            "\(probe)",
            forKey: "wal_growth_probe"
        )
    }

    // Copying the database and its -wal while the connection is still open
    // reproduces exactly what a SIGKILL leaves behind: committed frames that
    // never made it back into the database file. The -shm is deliberately not
    // copied — omitting it forces SQLite to run full log recovery, which is
    // deterministic, and a stale -shm is discarded anyway.
    let killedURL = fixture.root.appending(path: "killed/storage.sqlite")
    try FileManager.default.createDirectory(
        at: killedURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try FileManager.default.copyItem(at: fixture.databaseURL, to: killedURL)
    try FileManager.default.copyItem(
        atPath: fixture.databaseURL.path + "-wal",
        toPath: killedURL.path + "-wal"
    )
    await index.close()

    // The log larger than the database it belongs to is the defect in one
    // assertion.
    let killedDatabaseBytes = fileBytes(killedURL.path) ?? 0
    let killedWALBytes = fileBytes(killedURL.path + "-wal") ?? 0
    #expect(killedWALBytes > 0)
    #expect(killedDatabaseBytes < killedWALBytes)

    let reclamation = try StorageIndexReclaim.reclaim(indexURL: killedURL)
    #expect(reclamation.reclaimedBytes > 0)
    #expect(fileBytes(killedURL.path + "-wal") ?? 0 == 0)

    // The assertion that matters. Anything can make a file smaller; only a
    // checkpoint makes it smaller without losing the frames it held.
    let reclaimed = try StorageIndex(url: killedURL)
    #expect(try await reclaimed.integrityCheck() == "ok")
    #expect(
        try await reclaimed.stagedEntryCount(scanID: staged.scanID) ==
            Int64(staged.entryCount)
    )
    await reclaimed.close()
}

@Test func theWriteAheadLogStaysBoundedWhileAWalkRuns() async throws {
    let fixture = try WALIndexFixture()
    defer { fixture.remove() }
    try fixture.makeScanFiles(count: 12_000)

    // The control is the old behaviour rather than a remembered number: a
    // batch size larger than the corpus is one BEGIN IMMEDIATE from the first
    // entry to the last, which is what the whole walk used to be. Both runs
    // share a 1 MB autocheckpoint budget, so the only difference between them
    // is whether the log is ever given the chance to spend it.
    let unbatchedPeak = try await peakWriteAheadLogBytes(
        indexURL: fixture.root.appending(path: "unbatched/storage.sqlite"),
        scanRoot: fixture.scanRoot,
        traversalBatchSize: 10_000_000
    )
    let batchedPeak = try await peakWriteAheadLogBytes(
        indexURL: fixture.root.appending(path: "batched/storage.sqlite"),
        scanRoot: fixture.scanRoot,
        traversalBatchSize: 1_000
    )

    #expect(batchedPeak > 0)
    #expect(unbatchedPeak > 0)
    #expect(batchedPeak * 2 < unbatchedPeak)
}

@Test func anInterruptedTraversalIsNeverChosenAsThePrecedingScan()
    async throws
{
    let fixture = try WALIndexFixture()
    defer { fixture.remove() }
    try fixture.makeScanFiles(count: 800)

    let first = try StorageIndex(url: fixture.databaseURL)
    let firstScan = try await fixture.completeScan(with: first)
    await first.close()

    // Something the third scan can report as growth.
    try Data(repeating: 0x41, count: 512_000).write(
        to: fixture.scanRoot.appending(path: "grown")
    )

    // A traversal that commits a batch and is then cancelled: committed rows,
    // no derived totals, and a NULL completed_at. Before the marker existed
    // this generation was indistinguishable from a finished one.
    let interrupted = try StorageIndex(
        url: fixture.databaseURL,
        traversalBatchSize: 1,
        maximumAdditionalPagesForTesting: nil
    )
    let interruptedScan = Task {
        try await interrupted.stageTraversal(
            at: fixture.scanRoot,
            scope: .subtree
        )
    }
    interruptedScan.cancel()
    let interruptedResult = await interruptedScan.result
    #expect(throws: CancellationError.self) {
        _ = try interruptedResult.get()
    }
    await interrupted.close()

    let third = try StorageIndex(url: fixture.databaseURL)
    let thirdScan = try await fixture.completeScan(with: third)

    // The partial generation is still there. It is the filter that protects
    // these two reads, not a deletion.
    #expect(try await third.stagedScanCount() == 3)

    let growth = try await third.directoryGrowthFindings(
        scanID: thirdScan.scanID,
        minimumGrowthBytes: 1
    )
    guard case let .known(findings, _) = growth else {
        Issue.record("Directory growth did not publish: \(growth)")
        await third.close()
        return
    }
    // Choosing the interrupted scan as `previous` joins staged_node_totals it
    // does not have, so this comes back empty and the product says "nothing
    // changed" where it should say "not published".
    #expect(!findings.isEmpty)

    let changed = try await third.searchStagedEntries(
        scanID: thirdScan.scanID,
        query: .changedThisWeek
    )
    guard case let .known(entries, _) = changed else {
        Issue.record("Changed-this-week did not publish: \(changed)")
        await third.close()
        return
    }
    #expect(!entries.isEmpty)
    #expect(firstScan.entryCount < thirdScan.entryCount)
    await third.close()
}

@Test func theIndexKeepsOnlyTheTwoScansTheProductNeeds() async throws {
    let fixture = try WALIndexFixture()
    defer { fixture.remove() }
    try fixture.makeScanFiles(count: 300)

    let index = try StorageIndex(url: fixture.databaseURL)
    let first = try await fixture.completeScan(with: index)
    try Data(repeating: 0x42, count: 256_000).write(
        to: fixture.scanRoot.appending(path: "second-generation")
    )
    let second = try await fixture.completeScan(with: index)
    try Data(repeating: 0x43, count: 512_000).write(
        to: fixture.scanRoot.appending(path: "third-generation")
    )
    let third = try await fixture.completeScan(with: index)

    // Nothing pruned these before, so every completed whole-volume scan added
    // a full index generation permanently.
    #expect(try await index.stagedScanCount() == 2)
    #expect(try await index.stagedEntryCount(scanID: first.scanID) == 0)
    #expect(
        try await index.stagedEntryCount(scanID: second.scanID) ==
            Int64(second.entryCount)
    )
    #expect(
        try await index.stagedEntryCount(scanID: third.scanID) ==
            Int64(third.entryCount)
    )
    #expect(try await index.integrityCheck() == "ok")

    // Retention keeps two rather than one precisely so it cannot break the
    // feature it exists to serve.
    let growth = try await index.directoryGrowthFindings(
        scanID: third.scanID,
        minimumGrowthBytes: 1
    )
    guard case let .known(findings, _) = growth else {
        Issue.record("Directory growth did not publish after pruning: \(growth)")
        await index.close()
        return
    }
    #expect(!findings.isEmpty)
    await index.close()
}

@Test func theIndexFootprintCountsEverySidecarThatExists() async throws {
    let fixture = try WALIndexFixture()
    defer { fixture.remove() }
    try fixture.makeScanFiles(count: 60)

    let index = try StorageIndex(url: fixture.databaseURL)
    _ = try await index.stageTraversal(
        at: fixture.scanRoot,
        scope: .subtree
    )
    await index.close()

    let expected = [
        fixture.databaseURL.path,
        fixture.databaseURL.path + "-wal",
        fixture.databaseURL.path + "-shm",
        fixture.databaseURL.appendingPathExtension("reserve").path
    ].reduce(into: UInt64(0)) { $0 &+= allocatedBytes($1) ?? 0 }

    #expect(expected > 0)
    #expect(
        StorageIndexReclaim.footprintBytes(indexURL: fixture.databaseURL) ==
            .known(expected, source: .statAllocatedBlocks)
    )

    // A Mac that has never scanned has no footprint to report. Not a zero —
    // a zero would claim the index costs nothing.
    let absent = StorageIndexReclaim.footprintBytes(
        indexURL: fixture.root.appending(path: "never/storage.sqlite")
    )
    guard case let .notPublished(reason) = absent else {
        Issue.record("An absent index reported a figure: \(absent)")
        return
    }
    #expect(!reason.isEmpty)
}

// MARK: - Fixture

private struct WALIndexFixture {
    let root: URL
    let scanRoot: URL
    let databaseURL: URL

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appending(path: "FathomWALTests-\(UUID().uuidString)")
        scanRoot = root.appending(path: "scan")
        databaseURL = root.appending(path: "index/storage.sqlite")
        try FileManager.default.createDirectory(
            at: scanRoot,
            withIntermediateDirectories: true
        )
    }

    func makeScanFiles(count: Int) throws {
        for index in 0..<count {
            let directory = scanRoot.appending(path: "d\(index / 200)")
            if index % 200 == 0 {
                try FileManager.default.createDirectory(
                    at: directory,
                    withIntermediateDirectories: true
                )
            }
            FileManager.default.createFile(
                atPath: directory
                    .appending(path: "entry-\(index).bin").path,
                contents: Data("\(index)".utf8)
            )
        }
    }

    /// A traversal plus the two reductions that give it the derived totals
    /// `directoryGrowthFindings` and `changed this week` both join against.
    /// A scan without them is exactly what an interrupted scan looks like.
    func completeScan(with index: StorageIndex) async throws
        -> StagedTraversalScan
    {
        let staged = try await index.stageTraversal(
            at: scanRoot,
            scope: .subtree
        )
        _ = try await index.inspectStagedExtents(
            scanID: staged.scanID,
            maximumConcurrentReads: 4
        )
        _ = try await index.reduceStagedAccounting(scanID: staged.scanID)
        return staged
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}

// MARK: - Measurement helpers

private actor PeakRecorder {
    private(set) var peak: UInt64 = 0

    func record(_ value: UInt64) {
        peak = max(peak, value)
    }
}

/// Walks the corpus with the given batch size and reports the largest the
/// `-wal` ever got while it ran.
private func peakWriteAheadLogBytes(
    indexURL: URL,
    scanRoot: URL,
    traversalBatchSize: Int64
) async throws -> UInt64 {
    let index = try StorageIndex(
        url: indexURL,
        walAutocheckpointPages: 256,
        traversalBatchSize: traversalBatchSize,
        maximumAdditionalPagesForTesting: nil
    )
    let recorder = PeakRecorder()
    let walPath = indexURL.path + "-wal"
    let sampler = Task {
        while !Task.isCancelled {
            await recorder.record(fileBytes(walPath) ?? 0)
            try? await Task.sleep(for: .milliseconds(2))
        }
    }
    _ = try await index.stageTraversal(at: scanRoot, scope: .subtree)
    sampler.cancel()
    let peak = await recorder.peak
    await index.close()
    return peak
}

private func walBytes(_ fixture: WALIndexFixture) -> UInt64 {
    fileBytes(fixture.databaseURL.path + "-wal") ?? 0
}

/// `st_size`, not `st_blocks`: a TRUNCATE checkpoint shortens the file, and
/// the length is what says it happened.
private func fileBytes(_ path: String) -> UInt64? {
    var status = stat()
    guard lstat(path, &status) == 0 else { return nil }
    return UInt64(bitPattern: Int64(status.st_size))
}

/// Allocated blocks, matching what the footprint reports.
private func allocatedBytes(_ path: String) -> UInt64? {
    var status = stat()
    guard lstat(path, &status) == 0 else { return nil }
    return UInt64(bitPattern: Int64(status.st_blocks)) &* 512
}
