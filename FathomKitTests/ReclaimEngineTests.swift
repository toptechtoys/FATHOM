import Foundation
@testable import FathomKit
import Testing

@Test
func reclaimDryRunRecordsIdentityAndBothNumbers() throws {
    let root = FileManager.default.temporaryDirectory.appending(
        path: "fathom-reclaim-\(UUID().uuidString)",
        directoryHint: .isDirectory
    )
    try FileManager.default.createDirectory(
        at: root,
        withIntermediateDirectories: true
    )
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appending(path: "cache.bin")
    try Data(repeating: 0x8A, count: 4_096).write(to: file)
    var scanned: StorageEntry?
    try StorageScanner().walk(at: file) { scanned = $0 }
    let source = try #require(scanned)
    let candidate = StorageEntry(
        path: source.path,
        kind: source.kind,
        identity: source.identity,
        hardLinkCount: source.hardLinkCount,
        isDataless: source.isDataless,
        logicalSize: source.logicalSize,
        sizeOnDisk: source.sizeOnDisk,
        modificationTime: source.modificationTime,
        freedIfDeleted: source.sizeOnDisk,
        traversalLocation: source.traversalLocation
    )
    let recipe = try ReclaimRecipe(
        identifier: "test.cache",
        version: 1,
        regenerationCost: "One fixture rebuild, under a second"
    )
    let result = ReclaimEngine().dryRun(
        entries: [candidate],
        recipe: recipe
    )
    #expect(result.refusals.isEmpty)
    let item = try #require(result.manifest.items.first)
    #expect(item.metadata.identity == candidate.identity)
    #expect(item.sizeOnDisk == candidate.sizeOnDisk)
    #expect(item.freedIfDeleted == candidate.freedIfDeleted)
    guard case .known = result.manifest.freeableBytes else {
        Issue.record("a manifest of known items did not publish its total")
        return
    }
}

@Test
func reclaimDryRunHardRefusesApplicationInternals() throws {
    let entry = StorageEntry(
        path: "/Applications/Example.app/Contents/Resources/data",
        kind: .regularFile,
        identity: .init(device: 1, inode: 2),
        hardLinkCount: 1,
        isDataless: false,
        logicalSize: .known(10, source: .statLogicalSize),
        sizeOnDisk: .known(10, source: .statAllocatedBlocks),
        modificationTime: .known(
            .init(secondsSinceEpoch: 0, nanoseconds: 0),
            source: .statModificationTime
        ),
        freedIfDeleted: .known(10, source: .physicalReferenceAccounting)
    )
    let recipe = try ReclaimRecipe(
        identifier: "test.invalid",
        version: 1,
        regenerationCost: "Would require reinstalling the app"
    )
    let result = ReclaimEngine().dryRun(
        entries: [entry],
        recipe: recipe
    )
    #expect(result.manifest.items.isEmpty)
    #expect(result.refusals.count == 1)
}

@Test
func reclaimManifestRoundTripsAllMeasurementStates() throws {
    let recipe = try ReclaimRecipe(
        identifier: "test.states",
        version: 3,
        regenerationCost: "One rebuild"
    )
    let item = ReclaimManifestItem(
        path: "/tmp/example",
        metadata: .init(
            device: 1,
            inode: 2,
            logicalBytes: 30,
            modificationSeconds: 4,
            modificationNanoseconds: 5
        ),
        sizeOnDisk: .notPublished(reason: "not measured"),
        freedIfDeleted: .notAttributable(measured: 30, explained: 20)
    )
    let manifest = ReclaimManifest(
        createdAt: Date(timeIntervalSince1970: 10),
        recipe: recipe,
        items: [item]
    )
    let data = try JSONEncoder().encode(manifest)
    let decoded = try JSONDecoder().decode(ReclaimManifest.self, from: data)
    #expect(decoded == manifest)
}

@Test
func bundledRecipesValidateAndStateTheirCost() throws {
    let catalog = try ReclaimRecipeCatalog.bundled()
    #expect(ReclaimRecipeCatalog.bundledSignatureIsValid())
    #expect(!catalog.recipes.isEmpty)
    #expect(catalog.recipes.allSatisfy { $0.maximumMatches > 0 })
    #expect(catalog.recipes.allSatisfy { !$0.regenerationCost.isEmpty })
}

@Test
func everyBundledRecipeStaysInsideItsSyntheticRoot() throws {
    let home = FileManager.default.temporaryDirectory.appending(
        path: "fathom-all-recipes-\(UUID().uuidString)",
        directoryHint: .isDirectory
    )
    let outside = FileManager.default.temporaryDirectory.appending(
        path: "fathom-recipe-outside-\(UUID().uuidString)",
        directoryHint: .isDirectory
    )
    defer {
        try? FileManager.default.removeItem(at: home)
        try? FileManager.default.removeItem(at: outside)
    }
    try FileManager.default.createDirectory(
        at: outside,
        withIntermediateDirectories: true
    )
    try Data("must never match".utf8).write(
        to: outside.appending(path: "outside")
    )

    let catalog = try ReclaimRecipeCatalog.bundled()
    for recipe in catalog.recipes {
        let root = recipe.root.url(home: home)
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        try Data("fixture".utf8).write(
            to: root.appending(path: "fixture")
        )
        try FileManager.default.createSymbolicLink(
            at: root.appending(path: "escape"),
            withDestinationURL: outside
        )
        do {
            let match = try catalog.match(recipe, home: home)
            let resolvedRoot = root.resolvingSymlinksInPath().path + "/"
            #expect(match.paths.allSatisfy {
                $0.resolvingSymlinksInPath().path.hasPrefix(resolvedRoot)
            })
            #expect(UInt64(match.paths.count) <= recipe.maximumMatches)
        } catch let error as ReclaimRecipeCatalogError {
            #expect(error == .escapedRoot(path: outside.path))
        }
    }
}

@Test
func activeReclaimRecipesRejectUnknownFields() throws {
    let payload = Data("""
    [{
      "identifier": "future-active",
      "version": 1,
      "root": "npmCache",
      "glob": "*",
      "maximumMatches": 10,
      "regenerationCost": "one package download",
      "safetyClass": "safe",
      "futurePredicate": true
    }]
    """.utf8)

    #expect(throws: ReclaimRecipeCatalogError.invalidRecipe("future-active")) {
        _ = try ReclaimRecipeCatalog.decode(
            payload,
            currentAppVersion: "1.0.0"
        )
    }
}

@Test
func newerReclaimRecipesAreSkippedWhole() throws {
    let payload = Data("""
    [{
      "identifier": "future-only",
      "version": 1,
      "root": "npmCache",
      "glob": "*",
      "maximumMatches": 10,
      "regenerationCost": "one package download",
      "safetyClass": "safe",
      "minimumAppVersion": "2.0.0",
      "futurePredicate": {"meaning": "unknown to this build"}
    }]
    """.utf8)

    let catalog = try ReclaimRecipeCatalog.decode(
        payload,
        currentAppVersion: "1.9.9"
    )
    #expect(catalog.recipes.isEmpty)
}

@Test
func eligibleVersionedReclaimRecipesDecodeStrictly() throws {
    let payload = Data("""
    [{
      "identifier": "known-recipe",
      "version": 3,
      "root": "npmCache",
      "glob": "*",
      "maximumMatches": 10,
      "regenerationCost": "one package download",
      "safetyClass": "safe",
      "minimumAppVersion": "1.2.0"
    }]
    """.utf8)

    let catalog = try ReclaimRecipeCatalog.decode(
        payload,
        currentAppVersion: "1.2.0"
    )
    #expect(catalog.recipes.map(\.identifier) == ["known-recipe"])
}

@Test
func recipeDecoderRejectsParentTraversal() {
    let payload = Data(
        """
        {
          "identifier":"escape",
          "version":1,
          "root":"userLogs",
          "glob":"../*",
          "maximumMatches":1,
          "regenerationCost":"None",
          "safetyClass":"safe"
        }
        """.utf8
    )
    #expect(throws: (any Error).self) {
        _ = try JSONDecoder().decode(
            ReclaimDetectionRecipe.self,
            from: payload
        )
    }
}

@Test
func recipeMatchCapRefusesTheWholeRecipe() throws {
    let home = FileManager.default.temporaryDirectory.appending(
        path: "fathom-recipe-\(UUID().uuidString)",
        directoryHint: .isDirectory
    )
    let logs = home.appending(path: "Library/Logs")
    try FileManager.default.createDirectory(
        at: logs,
        withIntermediateDirectories: true
    )
    defer { try? FileManager.default.removeItem(at: home) }
    try Data().write(to: logs.appending(path: "one"))
    try Data().write(to: logs.appending(path: "two"))
    let recipe = try ReclaimDetectionRecipe(
        identifier: "test.cap",
        version: 1,
        root: .userLogs,
        glob: "*",
        maximumMatches: 1,
        regenerationCost: "No rebuild",
        safetyClass: .safe
    )
    let catalog = try ReclaimRecipeCatalog(recipes: [recipe])
    #expect(
        throws: ReclaimRecipeCatalogError.maximumMatchesExceeded(
            identifier: "test.cap",
            maximum: 1
        )
    ) {
        _ = try catalog.match(recipe, home: home)
    }
}

@Test
func reclaimJournalIntentIsDurableBeforeTrashMoverRuns() throws {
    let root = FileManager.default.temporaryDirectory.appending(
        path: "fathom-journal-order-\(UUID().uuidString)",
        directoryHint: .isDirectory
    )
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appending(path: "candidate")
    try Data("candidate".utf8).write(to: file)
    var scanned: StorageEntry?
    try StorageScanner().walk(at: file) { scanned = $0 }
    let source = try #require(scanned)
    let candidate = StorageEntry(
        path: source.path,
        kind: source.kind,
        identity: source.identity,
        hardLinkCount: source.hardLinkCount,
        isDataless: false,
        logicalSize: source.logicalSize,
        sizeOnDisk: source.sizeOnDisk,
        modificationTime: source.modificationTime,
        freedIfDeleted: source.sizeOnDisk
    )
    let recipe = try ReclaimRecipe(
        identifier: "test.order",
        version: 1,
        regenerationCost: "Rewrite one fixture"
    )
    let journal = root.appending(path: "journal.jsonl")
    let mover = JournalObservingMover(journalURL: journal)
    let dryRun = ReclaimEngine(mover: mover).dryRun(
        entries: [candidate],
        recipe: recipe
    )
    let report = try ReclaimEngine(mover: mover).execute(
        dryRun.manifest,
        journalURL: journal,
        knownOpenFileIdentities: []
    )
    #expect(mover.observedIntentBeforeMove)
    #expect(report.items.first?.outcome == .movedToTrash)
}

@Test
func applicationCatalogUsesExactBundleIdentifierPathsOnly() throws {
    let root = FileManager.default.temporaryDirectory.appending(
        path: "fathom-app-catalog-\(UUID().uuidString)",
        directoryHint: .isDirectory
    )
    defer { try? FileManager.default.removeItem(at: root) }
    let applications = root.appending(path: "Applications")
    let app = applications.appending(path: "Example.app")
    let contents = app.appending(path: "Contents")
    try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
    let plist: [String: Any] = [
        "CFBundleIdentifier": "com.example.Example",
        "CFBundleName": "Example",
        "CFBundleShortVersionString": "1.2.3"
    ]
    try PropertyListSerialization.data(
        fromPropertyList: plist,
        format: .binary,
        options: 0
    ).write(to: contents.appending(path: "Info.plist"))
    let caches = root.appending(path: "Library/Caches")
    try FileManager.default.createDirectory(
        at: caches.appending(path: "com.example.Example"),
        withIntermediateDirectories: true
    )
    try FileManager.default.createDirectory(
        at: caches.appending(path: "com.example.Example.beta"),
        withIntermediateDirectories: true
    )
    let measurement = ApplicationCatalogReader(
        applicationRoots: [applications],
        home: root
    ).read()
    guard case let .known(records, _) = measurement else {
        Issue.record("Application fixture was not published")
        return
    }
    let record = try #require(records.first)
    #expect(record.bundleIdentifier == .known("com.example.Example", source: .applicationInfoPlist))
    #expect(
        record.exactLeftoverURLs == .known(
            [caches.appending(path: "com.example.Example")],
            source: .exactBundleIDLeftoverMatch
        )
    )
}

@Test
func riskyRecipesRequireAConfirmationForEachExactPath() throws {
    let fixture = try ReclaimSafetyFixture()
    defer { fixture.remove() }
    let recipe = try ReclaimRecipe(
        identifier: "test.risky",
        version: 1,
        regenerationCost: "Recreate one fixture",
        safetyClass: .requiresPerItemConfirmation,
        allowedRootPath: fixture.root.path
    )
    let dryRun = ReclaimEngine().dryRun(
        entries: [fixture.entry],
        recipe: recipe
    )
    let journal = fixture.root.appending(path: "journal.jsonl")
    let mover = JournalObservingMover(journalURL: journal)
    let refused = try ReclaimEngine(mover: mover).execute(
        dryRun.manifest,
        journalURL: journal,
        knownOpenFileIdentities: []
    )
    #expect(refused.items.first?.outcome == .refused)
    #expect(!mover.observedIntentBeforeMove)

    let confirmed = dryRun.confirming(itemPaths: [fixture.entry.path])
    let moved = try ReclaimEngine(mover: mover).execute(
        confirmed.manifest,
        journalURL: journal,
        knownOpenFileIdentities: []
    )
    #expect(moved.items.first?.outcome == .movedToTrash)
    #expect(mover.observedIntentBeforeMove)
}

@Test
func runtimeRecipeContainmentIsCheckedAgainAfterTheDryRun() throws {
    let fixture = try ReclaimSafetyFixture()
    defer { fixture.remove() }
    let recipe = try ReclaimRecipe(
        identifier: "test.containment",
        version: 1,
        regenerationCost: "Recreate one fixture",
        allowedRootPath: fixture.root.appending(path: "different-root").path
    )
    let dryRun = ReclaimEngine().dryRun(
        entries: [fixture.entry],
        recipe: recipe
    )
    let journal = fixture.root.appending(path: "journal.jsonl")
    let mover = JournalObservingMover(journalURL: journal)
    let report = try ReclaimEngine(mover: mover).execute(
        dryRun.manifest,
        journalURL: journal,
        knownOpenFileIdentities: []
    )
    #expect(report.items.first?.outcome == .refused)
    #expect(report.items.first?.detail.contains("escaped") == true)
    #expect(!mover.observedIntentBeforeMove)
}

@Test
func reportOnlyRecipesCannotReachATrashMover() throws {
    let fixture = try ReclaimSafetyFixture()
    defer { fixture.remove() }
    let recipe = try ReclaimRecipe(
        identifier: "test.report-only",
        version: 1,
        regenerationCost: "No action",
        safetyClass: .reportOnly,
        allowedRootPath: fixture.root.path
    )
    let dryRun = ReclaimEngine().dryRun(
        entries: [fixture.entry],
        recipe: recipe
    )
    let journal = fixture.root.appending(path: "journal.jsonl")
    let mover = JournalObservingMover(journalURL: journal)
    #expect(
        throws: ReclaimError.reportOnlyRecipe("test.report-only")
    ) {
        _ = try ReclaimEngine(mover: mover).execute(
            dryRun.manifest,
            journalURL: journal,
            knownOpenFileIdentities: []
        )
    }
    #expect(!mover.observedIntentBeforeMove)
}

@Test
func reclaimJournalReplayPublishesOnlyUnmatchedIntents() throws {
    let root = FileManager.default.temporaryDirectory.appending(
        path: "fathom-journal-replay-\(UUID().uuidString)"
    )
    try FileManager.default.createDirectory(
        at: root,
        withIntermediateDirectories: true
    )
    defer { try? FileManager.default.removeItem(at: root) }
    let journal = root.appending(path: "journal.jsonl")
    let rows = [
        "{\"timestamp\":1000,\"phase\":\"intent\",\"recipe\":{\"identifier\":\"one\",\"version\":1},\"path\":\"/tmp/completed\"}",
        "{\"timestamp\":1001,\"phase\":\"outcome\",\"recipe\":{\"identifier\":\"one\",\"version\":1},\"path\":\"/tmp/completed\"}",
        "{\"timestamp\":1002,\"phase\":\"intent\",\"recipe\":{\"identifier\":\"two\",\"version\":3},\"path\":\"/tmp/pending\"}"
    ]
    try Data((rows.joined(separator: "\n") + "\n").utf8).write(
        to: journal
    )
    let result = ReclaimJournalRecoveryReader.read(at: journal)
    guard case let .known(intents, source) = result else {
        Issue.record("Expected a replayable journal")
        return
    }
    #expect(source == .reclaimJournalReplay)
    #expect(intents.map(\.path) == ["/tmp/pending"])
    #expect(intents.first?.recipeIdentifier == "two")
    #expect(intents.first?.recipeVersion == 3)
}

@Test
func malformedReclaimJournalDoesNotPretendRecoveryIsComplete() throws {
    let journal = FileManager.default.temporaryDirectory.appending(
        path: "fathom-malformed-journal-\(UUID().uuidString).jsonl"
    )
    try Data("{bad json}\n".utf8).write(to: journal)
    defer { try? FileManager.default.removeItem(at: journal) }
    guard case .notPublished = ReclaimJournalRecoveryReader.read(at: journal)
    else {
        Issue.record("A malformed journal must remain visibly unresolved")
        return
    }
}

@Test
func cloudDryRunIncludesOnlyKnownPositiveEvictableBytes() {
    func item(
        _ path: String,
        freeable: FathomKit.Measurement<UInt64>
    ) -> CloudItemRecord {
        CloudItemRecord(
            url: URL(fileURLWithPath: path),
            downloadingStatus: .known("current", source: .ubiquitousDownloadingStatus),
            isPinned: .known(false, source: .ubiquitousExcludedFromSync),
            sizeOnDisk: .known(10, source: .ubiquitousAllocatedSize),
            freedIfEvicted: freeable
        )
    }
    let plan = CloudEvictionEngine().dryRun([
        item("/tmp/positive", freeable: .known(10, source: .ubiquitousAllocatedSize)),
        item("/tmp/zero", freeable: .known(0, source: .ubiquitousAllocatedSize)),
        item("/tmp/missing", freeable: .notPublished(reason: "pin missing"))
    ])
    #expect(plan.items.map(\.url.path) == ["/tmp/positive"])
    #expect(
        plan.freeableBytes == .known(10, source: .ubiquitousAllocatedSize)
    )
}

@Test
func reclaimExecuteRefusesProtectedPathsInManifestsThatSkippedTheDryRun() throws {
    // A manifest is Codable and `execute` is public, so the protected-path
    // refusals cannot live only in `dryRun`. No shipped recipe sets an
    // allowedRootPath, so nothing else would stop this item.
    let root = FileManager.default.temporaryDirectory.appending(
        path: "fathom-reclaim-bypass-\(UUID().uuidString)",
        directoryHint: .isDirectory
    )
    let bundled = root.appending(path: "Example.app/Contents/Resources")
    try FileManager.default.createDirectory(
        at: bundled,
        withIntermediateDirectories: true
    )
    defer { try? FileManager.default.removeItem(at: root) }
    let file = bundled.appending(path: "data")
    try Data("protected".utf8).write(to: file)

    let manifest = ReclaimManifest(
        createdAt: Date(),
        recipe: try ReclaimRecipe(
            identifier: "test.bypass",
            version: 1,
            regenerationCost: "None; this must never run"
        ),
        items: [
            ReclaimManifestItem(
                path: file.path,
                metadata: ReclaimFileMetadata(
                    device: 0,
                    inode: 0,
                    logicalBytes: 9,
                    modificationSeconds: 0,
                    modificationNanoseconds: 0
                ),
                sizeOnDisk: .known(4_096, source: .statAllocatedBlocks),
                freedIfDeleted: .known(4_096, source: .statAllocatedBlocks)
            )
        ]
    )
    let mover = RefusalRecordingMover()
    let journalURL = root.appending(path: "journal.jsonl")
    let report = try ReclaimEngine(mover: mover).execute(
        manifest,
        journalURL: journalURL,
        knownOpenFileIdentities: []
    )

    let item = try #require(report.items.first)
    #expect(item.outcome == .refused)
    #expect(item.detail == "Application bundle internals are never modified")
    #expect(!mover.wasAsked)
    #expect(FileManager.default.fileExists(atPath: file.path))
}

private final class RefusalRecordingMover: @unchecked Sendable, TrashMoving {
    private(set) var wasAsked = false

    func moveToTrash(_ url: URL) throws -> URL? {
        wasAsked = true
        return URL(fileURLWithPath: "/Trash/\(url.lastPathComponent)")
    }
}

private final class JournalObservingMover: @unchecked Sendable, TrashMoving {
    let journalURL: URL
    private(set) var observedIntentBeforeMove = false

    init(journalURL: URL) {
        self.journalURL = journalURL
    }

    func moveToTrash(_ url: URL) throws -> URL? {
        let text = (try? String(contentsOf: journalURL, encoding: .utf8)) ?? ""
        observedIntentBeforeMove = text.contains("\"phase\":\"intent\"")
        return URL(fileURLWithPath: "/Trash/\(url.lastPathComponent)")
    }
}

private struct ReclaimSafetyFixture {
    let root: URL
    let entry: StorageEntry

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(
            path: "fathom-reclaim-safety-\(UUID().uuidString)"
        )
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        let file = root.appending(path: "candidate")
        try Data("candidate".utf8).write(to: file)
        var scanned: StorageEntry?
        try StorageScanner().walk(at: file) { scanned = $0 }
        let source = try #require(scanned)
        entry = StorageEntry(
            path: source.path,
            kind: source.kind,
            identity: source.identity,
            hardLinkCount: source.hardLinkCount,
            isDataless: source.isDataless,
            logicalSize: source.logicalSize,
            sizeOnDisk: source.sizeOnDisk,
            modificationTime: source.modificationTime,
            freedIfDeleted: source.sizeOnDisk
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}
