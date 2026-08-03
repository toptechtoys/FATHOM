import Darwin
import Foundation
import FathomKit
import Testing

@Test func scannerUsesPhysicalTraversalAndReportsStatSizes() throws {
    let fixture = try TemporaryFixture()
    defer { fixture.remove() }

    let fileURL = fixture.root.appending(path: "payload")
    let bytes = Data(repeating: 0xA5, count: 8_193)
    try bytes.write(to: fileURL)

    let linkURL = fixture.root.appending(path: "payload-link")
    try FileManager.default.createSymbolicLink(
        at: linkURL,
        withDestinationURL: fileURL
    )

    var entries: [StorageEntry] = []
    let summary = try StorageScanner().walk(at: fixture.root) {
        entries.append($0)
    }

    #expect(summary.issues.isEmpty)
    #expect(summary.entryCount == 3)

    let file = try #require(entries.first { $0.path == fileURL.path })
    #expect(file.kind == .regularFile)
    #expect(file.logicalSize == .known(8_193, source: .statLogicalSize))

    let metadata = try FileManager.default.attributesOfItem(
        atPath: fileURL.path
    )
    let expectedAllocated = try #require(
        metadata[.systemFileNumber] != nil
            ? allocatedSize(at: fileURL)
            : nil
    )
    #expect(
        file.sizeOnDisk == .known(
            expectedAllocated,
            source: .statAllocatedBlocks
        )
    )
    #expect(
        file.freedIfDeleted == .notPublished(
            reason: "Clone extents and snapshot references have not been attributed"
        )
    )

    let link = try #require(entries.first { $0.path == linkURL.path })
    #expect(link.kind == .symbolicLink)
    #expect(entries.filter { $0.kind == .regularFile }.count == 1)
}

@Test func scannerReportsHardlinkIdentityWithoutDoubleCountingItYet() throws {
    let fixture = try TemporaryFixture()
    defer { fixture.remove() }

    let firstURL = fixture.root.appending(path: "first")
    let secondURL = fixture.root.appending(path: "second")
    try Data("same inode".utf8).write(to: firstURL)
    try FileManager.default.linkItem(at: firstURL, to: secondURL)

    var files: [StorageEntry] = []
    try StorageScanner().walk(at: fixture.root) {
        if $0.kind == .regularFile {
            files.append($0)
        }
    }

    #expect(files.count == 2)
    #expect(files[0].identity == files[1].identity)
    #expect(files.allSatisfy { $0.hardLinkCount == 2 })
    #expect(
        files.allSatisfy {
            $0.freedIfDeleted == .notPublished(
                reason: "Clone extents and snapshot references have not been attributed"
            )
        }
    )
}

@Test func sparseFileReportsLogicalAndAllocatedBytesSeparately() throws {
    let fixture = try TemporaryFixture()
    defer { fixture.remove() }

    let sparseURL = fixture.root.appending(path: "sparse.img")
    let descriptor = open(sparseURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
    guard descriptor >= 0 else {
        throw CocoaError(.fileWriteUnknown)
    }
    defer { close(descriptor) }

    let logicalBytes = 64 * 1_024 * 1_024
    guard ftruncate(descriptor, off_t(logicalBytes)) == 0 else {
        throw CocoaError(.fileWriteUnknown)
    }

    var entry: StorageEntry?
    try StorageScanner().walk(at: sparseURL) {
        entry = $0
    }

    let sparse = try #require(entry)
    let expectedAllocated = try allocatedSize(at: sparseURL)
    #expect(
        sparse.logicalSize == .known(
            UInt64(logicalBytes),
            source: .statLogicalSize
        )
    )
    #expect(
        sparse.sizeOnDisk == .known(
            expectedAllocated,
            source: .statAllocatedBlocks
        )
    )
    #expect(expectedAllocated < logicalBytes)
}

@Test func missingRootIsAStartFailure() throws {
    let fixture = try TemporaryFixture()
    let missingURL = fixture.root.appending(path: "does-not-exist")
    defer { fixture.remove() }

    #expect(throws: StorageScanError.self) {
        try StorageScanner().walk(at: missingURL) { _ in }
    }
}

private func allocatedSize(at url: URL) throws -> UInt64 {
    var metadata = stat()
    guard lstat(url.path, &metadata) == 0 else {
        throw CocoaError(.fileReadUnknown)
    }
    return UInt64(metadata.st_blocks) * 512
}

private struct TemporaryFixture {
    let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appending(path: "FathomKitTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: false
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}
