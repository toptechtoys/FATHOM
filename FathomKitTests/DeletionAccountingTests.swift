import FathomKit
import Testing

@Test func sharedRangeFreesOnlyWhenEveryReferenceIsDeleted() throws {
    let files = [
        deletionFile(path: "/a", inode: 1, start: 0, length: 100),
        deletionFile(path: "/b", inode: 2, start: 50, length: 100)
    ]
    let context = exactDeletionContext()
    let accountant = DeletionAccountant()

    let deleteA = accountant.estimate(
        deletingPaths: ["/a"],
        from: files,
        context: context
    )
    let deleteBoth = accountant.estimate(
        deletingPaths: ["/a", "/b"],
        from: files,
        context: context
    )

    #expect(try deletionKnownValue(deleteA.sizeOnDisk) == 100)
    #expect(try deletionKnownValue(deleteA.freedIfDeleted) == 50)
    #expect(try deletionKnownValue(deleteBoth.sizeOnDisk) == 150)
    #expect(try deletionKnownValue(deleteBoth.freedIfDeleted) == 150)
}

@Test func openDescriptorReferencePreventsImmediateReclamation() throws {
    let file = deletionFile(
        path: "/held-open",
        inode: 42,
        start: 0,
        length: 4_096
    )
    let context = DeletionAccountingContext(
        scanScope: .wholeVolume,
        snapshotInventory: .known([], source: .fsSnapshotList),
        openFileIdentities: .known(
            [file.entry.identity],
            source: .physicalReferenceAccounting
        )
    )

    let estimate = DeletionAccountant().estimate(
        deletingPaths: [file.entry.path],
        from: [file],
        context: context
    )

    #expect(try deletionKnownValue(estimate.sizeOnDisk) == 4_096)
    #expect(try deletionKnownValue(estimate.freedIfDeleted) == 0)
}

@Test func snapshotsSuppressRatherThanSoftenTheFreeableClaim() {
    let file = deletionFile(
        path: "/snapshotted",
        inode: 1,
        start: 0,
        length: 4_096
    )
    let context = DeletionAccountingContext(
        scanScope: .wholeVolume,
        snapshotInventory: .known(
            [LocalSnapshot(name: "snapshot")],
            source: .fsSnapshotList
        ),
        openFileIdentities: .known(
            [],
            source: .physicalReferenceAccounting
        )
    )

    let estimate = DeletionAccountant().estimate(
        deletingPaths: [file.entry.path],
        from: [file],
        context: context
    )

    #expect(
        estimate.freedIfDeleted == .notPublished(
            reason: "Snapshot manifests have not been diffed"
        )
    )
}

@Test func snapshotManifestSubtractsOnlyTheRangesItStillReferences() throws {
    let file = deletionFile(
        path: "/partly-snapshotted",
        inode: 7,
        start: 0,
        length: 8_192
    )
    let context = DeletionAccountingContext(
        scanScope: .wholeVolume,
        snapshotInventory: .known(
            [LocalSnapshot(name: "snapshot-a")],
            source: .fsSnapshotList
        ),
        snapshotManifests: .known(
            [
                SnapshotExtentManifest(
                    snapshotName: "snapshot-a",
                    physicalExtents: [
                        SnapshotPhysicalExtent(
                            device: 1,
                            deviceOffset: 0,
                            length: 4_096
                        )
                    ]
                )
            ],
            source: .snapshotManifestDiff
        ),
        openFileIdentities: .known(
            [],
            source: .procOpenFileDescriptors
        )
    )

    let estimate = DeletionAccountant().estimate(
        deletingPaths: [file.entry.path],
        from: [file],
        context: context
    )

    #expect(try deletionKnownValue(estimate.sizeOnDisk) == 8_192)
    #expect(try deletionKnownValue(estimate.freedIfDeleted) == 4_096)
}

@Test func mismatchedSnapshotManifestCannotPublishFreeableBytes() {
    let file = deletionFile(
        path: "/snapshotted",
        inode: 8,
        start: 0,
        length: 4_096
    )
    let context = DeletionAccountingContext(
        scanScope: .wholeVolume,
        snapshotInventory: .known(
            [LocalSnapshot(name: "current")],
            source: .fsSnapshotList
        ),
        snapshotManifests: .known(
            [
                SnapshotExtentManifest(
                    snapshotName: "stale",
                    physicalExtents: []
                )
            ],
            source: .snapshotManifestDiff
        ),
        openFileIdentities: .known(
            [],
            source: .procOpenFileDescriptors
        )
    )

    let estimate = DeletionAccountant().estimate(
        deletingPaths: [file.entry.path],
        from: [file],
        context: context
    )
    #expect(
        estimate.freedIfDeleted == .notPublished(
            reason: "Snapshot manifests do not match the current inventory"
        )
    )
}

@Test func partitionPropertyNeverOvercreditsFreeableBytes() throws {
    var generator = LinearCongruentialGenerator(seed: 0xF_A7_40)
    let accountant = DeletionAccountant()
    let context = exactDeletionContext()

    for _ in 0..<250 {
        let fileCount = Int.random(in: 1...8, using: &generator)
        var files: [InspectedFile] = []
        var partitions: [Set<String>] = [[], [], []]
        for index in 0..<fileCount {
            let start = UInt64.random(in: 0...32, using: &generator) * 512
            let length = UInt64.random(in: 1...16, using: &generator) * 512
            let path = "/file-\(index)"
            files.append(
                deletionFile(
                    path: path,
                    inode: UInt64(index + 1),
                    start: start,
                    length: length
                )
            )
            let partition = Int.random(in: 0..<3, using: &generator)
            partitions[partition].insert(path)
        }

        let whole = accountant.estimate(
            deletingPaths: Set(files.map(\.entry.path)),
            from: files,
            context: context
        )
        let wholeFreeable = try deletionKnownValue(
            whole.freedIfDeleted
        )
        let partitionFreeable = try partitions.reduce(UInt64(0)) {
            let estimate = accountant.estimate(
                deletingPaths: $1,
                from: files,
                context: context
            )
            return $0 + (
                try deletionKnownValue(estimate.freedIfDeleted)
            )
        }

        #expect(partitionFreeable <= wholeFreeable)
    }
}

private func exactDeletionContext() -> DeletionAccountingContext {
    DeletionAccountingContext(
        scanScope: .wholeVolume,
        snapshotInventory: .known([], source: .fsSnapshotList),
        openFileIdentities: .known(
            [],
            source: .physicalReferenceAccounting
        )
    )
}

private func deletionFile(
    path: String,
    inode: UInt64,
    start: UInt64,
    length: UInt64
) -> InspectedFile {
    let entry = StorageEntry(
        path: path,
        kind: .regularFile,
        identity: FileIdentity(device: 1, inode: inode),
        hardLinkCount: 1,
        isDataless: false,
        logicalSize: .known(length, source: .statLogicalSize),
        sizeOnDisk: .known(length, source: .statAllocatedBlocks),
        modificationTime: .known(
            FileTimestamp(secondsSinceEpoch: 0, nanoseconds: 0),
            source: .statModificationTime
        ),
        freedIfDeleted: .notPublished(
            reason: "References have not been attributed"
        )
    )
    let extents = FileExtentMap(
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
            CloneMetadata(identifier: 0, referenceCount: 1),
            source: .getattrlistCloneIdentity
        ),
        allocationBlockSize: .known(
            1,
            source: .statfsAllocationBlockSize
        )
    )
    return InspectedFile(entry: entry, extents: extents)
}

private struct ExpectedDeletionKnownValue: Error {}

private func deletionKnownValue<Value: Sendable>(
    _ measurement: FathomKit.Measurement<Value>
) throws -> Value {
    guard case let .known(value, _) = measurement else {
        throw ExpectedDeletionKnownValue()
    }
    return value
}

private struct LinearCongruentialGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state = 6_364_136_223_846_793_005 &* state &+ 1
        return state
    }
}
