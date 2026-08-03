import Darwin
import Foundation
import FathomKit
import Testing

@Test func cloneFamilyIsCreditedOnceAtItsLowestCommonAncestor() throws {
    let fixture = try FamilyFixture()
    defer { fixture.remove() }

    let leftDirectory = fixture.root.appending(path: "left")
    let rightDirectory = fixture.root.appending(path: "right")
    try FileManager.default.createDirectory(
        at: leftDirectory,
        withIntermediateDirectories: false
    )
    try FileManager.default.createDirectory(
        at: rightDirectory,
        withIntermediateDirectories: false
    )

    let sourceURL = leftDirectory.appending(path: "source")
    let cloneURL = rightDirectory.appending(path: "clone")
    try Data(repeating: 0x71, count: 1_048_576).write(to: sourceURL)
    guard clonefile(sourceURL.path, cloneURL.path, 0) == 0 else {
        throw CocoaError(.fileWriteUnknown)
    }

    let source = try inspectFamilyFile(at: sourceURL)
    let clone = try inspectFamilyFile(at: cloneURL)
    let result = CloneFamilyAnalyzer().analyze(
        [source, clone],
        scope: .wholeVolume
    )
    let families = try familyKnownValue(result)
    let family = try #require(families.first)

    #expect(families.count == 1)
    #expect(family.memberPaths == [sourceURL.path, cloneURL.path].sorted())
    #expect(family.creditedAtPath == fixture.root.path)
    #expect(
        family.hasMemberOutsideScan ==
            .known(false, source: .cloneFamilyAccounting)
    )
    #expect(
        family.freedIfDeletingTogether == .notPublished(
            reason: "Snapshot references have not been attributed"
        )
    )

    let familyBytes = try familyKnownValue(family.sizeOnDisk)
    let sourceExtents = try familyKnownValue(
        source.extents.physicalExtents
    )
    let sourceBytes = sourceExtents.reduce(UInt64(0)) {
        $0 + $1.length
    }
    #expect(familyBytes == sourceBytes)
}

@Test func cloneOutsideTheScanMakesTheFamilyZeroFreeable() throws {
    let fixture = try FamilyFixture()
    defer { fixture.remove() }

    let scanRoot = fixture.root.appending(path: "scan")
    try FileManager.default.createDirectory(
        at: scanRoot,
        withIntermediateDirectories: false
    )

    let sourceURL = scanRoot.appending(path: "source")
    let insideCloneURL = scanRoot.appending(path: "inside-clone")
    let outsideCloneURL = fixture.root.appending(path: "outside-clone")
    try Data(repeating: 0x82, count: 1_048_576).write(to: sourceURL)
    guard clonefile(sourceURL.path, insideCloneURL.path, 0) == 0 else {
        throw CocoaError(.fileWriteUnknown)
    }
    guard clonefile(sourceURL.path, outsideCloneURL.path, 0) == 0 else {
        throw CocoaError(.fileWriteUnknown)
    }

    let result = CloneFamilyAnalyzer().analyze(
        [
            try inspectFamilyFile(at: sourceURL),
            try inspectFamilyFile(at: insideCloneURL)
        ],
        scope: .subtree
    )
    let families = try familyKnownValue(result)
    let family = try #require(families.first)

    #expect(families.count == 1)
    #expect(
        family.hasMemberOutsideScan ==
            .known(true, source: .cloneFamilyAccounting)
    )
    #expect(
        family.freedIfDeletingTogether ==
            .known(0, source: .cloneFamilyAccounting)
    )
}

@Test func hardlinkOutsideTheScanMakesItsEntryZeroFreeable() throws {
    let fixture = try FamilyFixture()
    defer { fixture.remove() }

    let insideURL = fixture.root.appending(path: "inside")
    let outsideURL = fixture.root.appending(path: "outside")
    try Data("one inode".utf8).write(to: insideURL)
    try FileManager.default.linkItem(at: insideURL, to: outsideURL)

    let result = CloneFamilyAnalyzer().analyze(
        [try inspectFamilyFile(at: insideURL)],
        scope: .subtree
    )
    let families = try familyKnownValue(result)
    let family = try #require(families.first)

    #expect(families.count == 1)
    #expect(family.memberPaths == [insideURL.path])
    #expect(
        family.hasMemberOutsideScan ==
            .known(true, source: .cloneFamilyAccounting)
    )
    #expect(
        family.freedIfDeletingTogether ==
            .known(0, source: .cloneFamilyAccounting)
    )
}

@Test func partiallyOverlappingExtentsFormOneTransitiveFamily() throws {
    let files = [
        syntheticFile(path: "/scan/a", inode: 1, start: 100, length: 100),
        syntheticFile(path: "/scan/b", inode: 2, start: 150, length: 100),
        syntheticFile(path: "/scan/c", inode: 3, start: 240, length: 60),
        syntheticFile(path: "/scan/unrelated", inode: 4, start: 400, length: 50)
    ]

    let result = CloneFamilyAnalyzer().analyze(
        files,
        scope: .wholeVolume
    )
    let families = try familyKnownValue(result)
    let family = try #require(families.first)
    let familyBytes = try familyKnownValue(family.sizeOnDisk)

    #expect(families.count == 1)
    #expect(family.memberPaths == ["/scan/a", "/scan/b", "/scan/c"])
    #expect(family.creditedAtPath == "/scan")
    #expect(familyBytes == 200)
}

private func syntheticFile(
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
            reason: "Snapshot references have not been attributed"
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

private func inspectFamilyFile(at url: URL) throws -> InspectedFile {
    var entry: StorageEntry?
    try StorageScanner().walk(at: url) {
        entry = $0
    }
    let scannedEntry = try #require(entry)
    return InspectedFile(
        entry: scannedEntry,
        extents: try FileExtentReader().inspect(scannedEntry)
    )
}

private struct ExpectedFamilyKnownValue: Error {}

private func familyKnownValue<Value: Sendable>(
    _ measurement: FathomKit.Measurement<Value>
) throws -> Value {
    guard case let .known(value, _) = measurement else {
        throw ExpectedFamilyKnownValue()
    }
    return value
}

private struct FamilyFixture {
    let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appending(path: "FathomFamilyTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: false
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}
