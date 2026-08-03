import Darwin
import Foundation
import FathomKit
import Testing

/// Public, deterministic accounting fixtures.
///
/// The device offsets are fixture inputs, not observations presented by the
/// product. Their exact expected unions make regressions in shared-extent
/// accounting visible without depending on whatever APFS allocation policy the
/// test runner happens to use.
@Test func internalCloneFamilyGoldenFixture() throws {
    let files = [
        goldenFile(path: "/tree/a", inode: 1, start: 4_096, length: 8_192),
        goldenFile(path: "/tree/b", inode: 2, start: 4_096, length: 8_192)
    ]
    let families = try goldenKnown(
        CloneFamilyAnalyzer().analyze(files, scope: .wholeVolume)
    )
    let family = try #require(families.first)

    #expect(families.count == 1)
    #expect(try goldenKnown(family.sizeOnDisk) == 8_192)
    #expect(try goldenKnown(family.hasMemberOutsideScan) == false)

    let accountant = DeletionAccountant()
    let one = accountant.estimate(
        deletingPaths: ["/tree/a"],
        from: files,
        context: goldenExactContext()
    )
    let both = accountant.estimate(
        deletingPaths: ["/tree/a", "/tree/b"],
        from: files,
        context: goldenExactContext()
    )
    #expect(try goldenKnown(one.sizeOnDisk) == 8_192)
    #expect(try goldenKnown(one.freedIfDeleted) == 0)
    #expect(try goldenKnown(both.sizeOnDisk) == 8_192)
    #expect(try goldenKnown(both.freedIfDeleted) == 8_192)
}

@Test func cloneFamilyWithExternalMemberGoldenFixture() throws {
    let observed = goldenFile(
        path: "/tree/inside",
        inode: 3,
        start: 16_384,
        length: 4_096,
        cloneID: 77,
        cloneReferenceCount: 2
    )
    let families = try goldenKnown(
        CloneFamilyAnalyzer().analyze([observed], scope: .subtree)
    )
    let family = try #require(families.first)

    #expect(families.count == 1)
    #expect(try goldenKnown(family.sizeOnDisk) == 4_096)
    #expect(try goldenKnown(family.hasMemberOutsideScan))
    #expect(try goldenKnown(family.freedIfDeletingTogether) == 0)
}

@Test func sparseFileGoldenFixtureKeepsLogicalAndPhysicalSeparate() throws {
    let entry = goldenEntry(
        path: "/tree/sparse",
        inode: 4,
        logicalSize: 65_536,
        allocatedSize: 8_192
    )
    let file = InspectedFile(
        entry: entry,
        extents: FileExtentMap(
            dataExtents: .known(
                [
                    LogicalFileExtent(offset: 0, length: 4_096),
                    LogicalFileExtent(offset: 61_440, length: 4_096)
                ],
                source: .seekDataAndHole
            ),
            physicalExtents: .known(
                [
                    PhysicalFileExtent(
                        logicalOffset: 0,
                        deviceOffset: 32_768,
                        length: 4_096
                    ),
                    PhysicalFileExtent(
                        logicalOffset: 61_440,
                        deviceOffset: 40_960,
                        length: 4_096
                    )
                ],
                source: .fcntlPhysicalExtents
            ),
            cloneMetadata: .known(
                CloneMetadata(identifier: 0, referenceCount: 1),
                source: .getattrlistCloneIdentity
            ),
            allocationBlockSize: .known(
                4_096,
                source: .statfsAllocationBlockSize
            )
        )
    )

    #expect(try goldenKnown(entry.logicalSize) == 65_536)
    #expect(try goldenKnown(entry.sizeOnDisk) == 8_192)
    let estimate = DeletionAccountant().estimate(
        deletingPaths: [entry.path],
        from: [file],
        context: goldenExactContext()
    )
    #expect(try goldenKnown(estimate.freedIfDeleted) == 8_192)
}

@Test func hardlinkPairGoldenFixtureFreesOnlyAfterBothNames() throws {
    let identity = FileIdentity(device: 1, inode: 5)
    let files = [
        goldenFile(
            path: "/tree/first",
            identity: identity,
            hardLinkCount: 2,
            start: 49_152,
            length: 4_096
        ),
        goldenFile(
            path: "/tree/second",
            identity: identity,
            hardLinkCount: 2,
            start: 49_152,
            length: 4_096
        )
    ]
    let accountant = DeletionAccountant()
    let first = accountant.estimate(
        deletingPaths: ["/tree/first"],
        from: files,
        context: goldenExactContext()
    )
    let both = accountant.estimate(
        deletingPaths: ["/tree/first", "/tree/second"],
        from: files,
        context: goldenExactContext()
    )

    #expect(try goldenKnown(first.sizeOnDisk) == 4_096)
    #expect(try goldenKnown(first.freedIfDeleted) == 0)
    #expect(try goldenKnown(both.freedIfDeleted) == 4_096)
}

@Test func datalessGoldenFixturePublishesZeroFreeableBytes() throws {
    let entry = StorageEntry(
        path: "/tree/evicted",
        kind: .regularFile,
        identity: FileIdentity(device: 1, inode: 6),
        hardLinkCount: 1,
        isDataless: true,
        logicalSize: .known(1_048_576, source: .statLogicalSize),
        sizeOnDisk: .known(0, source: .statAllocatedBlocks),
        modificationTime: .known(
            FileTimestamp(secondsSinceEpoch: 0, nanoseconds: 0),
            source: .statModificationTime
        ),
        freedIfDeleted: .known(0, source: .statDatalessFlag)
    )

    #expect(entry.isDataless)
    #expect(try goldenKnown(entry.logicalSize) == 1_048_576)
    #expect(try goldenKnown(entry.sizeOnDisk) == 0)
    #expect(try goldenKnown(entry.freedIfDeleted) == 0)
}

@Test func physicalTraversalDoesNotFollowASymlinkCycle() throws {
    let fixture = try GoldenFilesystemFixture()
    defer { fixture.remove() }

    let child = fixture.root.appending(path: "child")
    try FileManager.default.createDirectory(
        at: child,
        withIntermediateDirectories: false
    )
    let loop = child.appending(path: "loop")
    try FileManager.default.createSymbolicLink(
        at: loop,
        withDestinationURL: fixture.root
    )

    var entries: [StorageEntry] = []
    let summary = try StorageScanner().walk(at: fixture.root) {
        entries.append($0)
    }

    #expect(summary.issues.isEmpty)
    #expect(entries.count == 3)
    #expect(entries.filter { $0.kind == .symbolicLink }.map(\.path) == [
        loop.path
    ])
}

@Test func traversalAcceptsAPathAtThePortablePathLimitBoundary() throws {
    let fixture = try GoldenFilesystemFixture()
    defer { fixture.remove() }

    var deepest = fixture.root
    var componentIndex = 0
    let publishedNameLimit = pathconf(
        fixture.root.path,
        _PC_NAME_MAX
    )
    let nameLimit = publishedNameLimit > 0
        ? Int(publishedNameLimit)
        : 255
    while true {
        let room = Int(PATH_MAX) - 1 - deepest.path.utf8.count - 1
        guard room > 0 else {
            break
        }
        let componentLength = min(nameLimit, room)
        guard componentLength >= 8 else {
            break
        }
        let prefix = "d\(componentIndex)-"
        let component = prefix + String(
            repeating: "x",
            count: componentLength - prefix.utf8.count
        )
        let candidate = deepest.appending(path: component)
        try FileManager.default.createDirectory(
            at: candidate,
            withIntermediateDirectories: false
        )
        deepest = candidate
        componentIndex += 1
    }

    #expect(deepest.path.utf8.count <= Int(PATH_MAX) - 1)
    #expect(deepest.path.utf8.count >= Int(PATH_MAX) - Int(NAME_MAX) - 1)

    var visitedDeepest = false
    let summary = try StorageScanner().walk(at: fixture.root) {
        visitedDeepest = visitedDeepest || $0.path == deepest.path
    }
    #expect(summary.issues.isEmpty)
    #expect(visitedDeepest)
}

private func goldenExactContext() -> DeletionAccountingContext {
    DeletionAccountingContext(
        scanScope: .wholeVolume,
        snapshotInventory: .known([], source: .fsSnapshotList),
        openFileIdentities: .known(
            [],
            source: .procOpenFileDescriptors
        )
    )
}

private func goldenEntry(
    path: String,
    inode: UInt64,
    logicalSize: UInt64,
    allocatedSize: UInt64
) -> StorageEntry {
    StorageEntry(
        path: path,
        kind: .regularFile,
        identity: FileIdentity(device: 1, inode: inode),
        hardLinkCount: 1,
        isDataless: false,
        logicalSize: .known(logicalSize, source: .statLogicalSize),
        sizeOnDisk: .known(allocatedSize, source: .statAllocatedBlocks),
        modificationTime: .known(
            FileTimestamp(secondsSinceEpoch: 0, nanoseconds: 0),
            source: .statModificationTime
        ),
        freedIfDeleted: .notPublished(
            reason: "Fixture references have not been attributed"
        )
    )
}

private func goldenFile(
    path: String,
    inode: UInt64,
    start: UInt64,
    length: UInt64,
    cloneID: UInt64 = 0,
    cloneReferenceCount: UInt32 = 1
) -> InspectedFile {
    goldenFile(
        path: path,
        identity: FileIdentity(device: 1, inode: inode),
        hardLinkCount: 1,
        start: start,
        length: length,
        cloneID: cloneID,
        cloneReferenceCount: cloneReferenceCount
    )
}

private func goldenFile(
    path: String,
    identity: FileIdentity,
    hardLinkCount: UInt64,
    start: UInt64,
    length: UInt64,
    cloneID: UInt64 = 0,
    cloneReferenceCount: UInt32 = 1
) -> InspectedFile {
    let entry = StorageEntry(
        path: path,
        kind: .regularFile,
        identity: identity,
        hardLinkCount: hardLinkCount,
        isDataless: false,
        logicalSize: .known(length, source: .statLogicalSize),
        sizeOnDisk: .known(length, source: .statAllocatedBlocks),
        modificationTime: .known(
            FileTimestamp(secondsSinceEpoch: 0, nanoseconds: 0),
            source: .statModificationTime
        ),
        freedIfDeleted: .notPublished(
            reason: "Fixture references have not been attributed"
        )
    )
    return InspectedFile(
        entry: entry,
        extents: FileExtentMap(
            dataExtents: .known(
                [LogicalFileExtent(offset: 0, length: length)],
                source: .seekDataAndHole
            ),
            physicalExtents: .known(
                [
                    PhysicalFileExtent(
                        logicalOffset: 0,
                        deviceOffset: start,
                        length: length
                    )
                ],
                source: .fcntlPhysicalExtents
            ),
            cloneMetadata: .known(
                CloneMetadata(
                    identifier: cloneID,
                    referenceCount: cloneReferenceCount
                ),
                source: .getattrlistCloneIdentity
            ),
            allocationBlockSize: .known(
                4_096,
                source: .statfsAllocationBlockSize
            )
        )
    )
}

private struct ExpectedGoldenKnownValue: Error {}

private func goldenKnown<Value: Sendable>(
    _ measurement: FathomKit.Measurement<Value>
) throws -> Value {
    guard case let .known(value, _) = measurement else {
        throw ExpectedGoldenKnownValue()
    }
    return value
}

private struct GoldenFilesystemFixture {
    let root: URL

    init() throws {
        let temporaryPath = FileManager.default.temporaryDirectory.path
        let physicalTemporaryPath = temporaryPath.hasPrefix("/var/")
            ? "/private\(temporaryPath)"
            : temporaryPath
        root = URL(fileURLWithPath: physicalTemporaryPath)
            .appending(path: "FathomGolden-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: false
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}
