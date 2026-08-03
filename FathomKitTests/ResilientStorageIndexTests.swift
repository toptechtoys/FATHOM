import Darwin
import Foundation
@testable import FathomKit
import Testing

@Test func indexBudgetIsPhysicallyReservedThenReleasedForSQLite() async throws {
    let fixture = try ResilientIndexFixture(fileCount: 8)
    defer { fixture.remove() }

    let configuration = StorageIndexPersistenceConfiguration(
        primaryURL: fixture.primaryURL,
        initialReservationBytes: 65_536
    )
    let resilient = ResilientStorageIndex(configuration: configuration)
    let reservation = resilient.reserveInitialBudget()
    let reservationURL: URL
    switch reservation {
    case let .reserved(url, bytes):
        reservationURL = url
        #expect(bytes == 65_536)
    case let .notReserved(reason):
        throw ResilientIndexFixtureError.reservation(reason)
    }

    var metadata = stat()
    #expect(lstat(reservationURL.path, &metadata) == 0)
    #expect(UInt64(metadata.st_blocks) * 512 >= 65_536)

    let (result, accounting) = try await fixture.scan()
    let outcome = await resilient.store(
        result: result,
        accounting: accounting
    )
    guard case let .persisted(_, indexURL) = outcome else {
        Issue.record("The reserved primary index was not persisted")
        return
    }
    #expect(indexURL == fixture.primaryURL)

    #expect(lstat(reservationURL.path, &metadata) == 0)
    #expect(metadata.st_size == 0)
}

@Test func sqliteFullRetriesAtTheConfiguredAlternateLocation() async throws {
    let fixture = try ResilientIndexFixture(fileCount: 1_024)
    defer { fixture.remove() }

    let configuration = StorageIndexPersistenceConfiguration(
        primaryURL: fixture.primaryURL,
        alternateURL: fixture.alternateURL,
        initialReservationBytes: 0
    )
    let resilient = ResilientStorageIndex(
        configuration: configuration,
        primaryAdditionalPagesForTesting: 0
    )
    let (result, accounting) = try await fixture.scan()
    let outcome = await resilient.store(
        result: result,
        accounting: accounting,
        startedAt: Date(timeIntervalSince1970: 1_700_000_000)
    )

    guard case let .persisted(scanID, indexURL) = outcome else {
        Issue.record("SQLITE_FULL did not fall back to the alternate index")
        return
    }
    #expect(indexURL == fixture.alternateURL)

    let alternate = try StorageIndex(url: fixture.alternateURL)
    let summary = try #require(
        try await alternate.latestScanSummary()
    )
    #expect(summary.scanID == scanID)
    #expect(summary.nodeCount == result.entries.count)
    #expect(try await alternate.integrityCheck() == "ok")
    await alternate.close()
}

@Test func corruptIndexIsQuarantinedWithoutTouchingTheJournal() async throws {
    let root = FileManager.default.temporaryDirectory.appending(
        path: "FathomCorruptIndex-\(UUID().uuidString)"
    )
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(
        at: root,
        withIntermediateDirectories: true
    )
    let indexURL = root.appending(path: "storage.sqlite")
    let journalURL = root.appending(path: "reclaim-journal.jsonl")
    let corruptBytes = Data("not a sqlite database".utf8)
    try corruptBytes.write(to: indexURL)
    try Data("journal must survive".utf8).write(to: journalURL)

    let openError: Error
    do {
        _ = try StorageIndex(url: indexURL)
        Issue.record("A corrupt fixture unexpectedly opened")
        return
    } catch {
        openError = error
    }
    #expect(StorageIndexRecovery.isCorruption(openError))
    let result = try StorageIndexRecovery.quarantine(indexURL: indexURL)
    let preserved = try #require(result.preservedURLs.first)
    #expect(try Data(contentsOf: preserved) == corruptBytes)
    #expect(!FileManager.default.fileExists(atPath: indexURL.path))
    #expect(try String(contentsOf: journalURL) == "journal must survive")

    let rebuilt = try StorageIndex(url: indexURL)
    #expect(try await rebuilt.integrityCheck() == "ok")
    await rebuilt.close()
}

private struct ResilientIndexFixture {
    let root: URL
    let scanRoot: URL
    let primaryURL: URL
    let alternateURL: URL

    init(fileCount: Int) throws {
        root = FileManager.default.temporaryDirectory
            .appending(path: "FathomResilientIndex-\(UUID().uuidString)")
        scanRoot = root.appending(path: "scan")
        primaryURL = root.appending(path: "primary/index.sqlite")
        alternateURL = root.appending(path: "alternate/index.sqlite")
        try FileManager.default.createDirectory(
            at: scanRoot,
            withIntermediateDirectories: true
        )
        for index in 0..<fileCount {
            try Data("fixture-\(index)".utf8).write(
                to: scanRoot.appending(path: "file-\(index)")
            )
        }
    }

    func scan() async throws
        -> (StorageEngineResult, StorageAccountingSnapshot)
    {
        let result = try await StorageEngine().scan(
            at: scanRoot,
            scope: .subtree
        )
        guard
            case let .known(accounting, _) =
                StorageAccountingBuilder().build(from: result)
        else {
            throw ResilientIndexFixtureError.accountingNotPublished
        }
        return (result, accounting)
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}

private enum ResilientIndexFixtureError: Error {
    case accountingNotPublished
    case reservation(String)
}
