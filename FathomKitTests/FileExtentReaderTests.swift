import Darwin
import Foundation
import FathomKit
import Testing

@Test func extentReaderFindsSparseDataWithoutReadingContents() throws {
    let fixture = try ExtentFixture()
    defer { fixture.remove() }

    let fileURL = fixture.root.appending(path: "sparse.img")
    let descriptor = open(
        fileURL.path,
        O_CREAT | O_RDWR,
        S_IRUSR | S_IWUSR
    )
    guard descriptor >= 0 else {
        throw CocoaError(.fileWriteUnknown)
    }
    var descriptorToClose = descriptor
    defer {
        if descriptorToClose >= 0 {
            close(descriptorToClose)
        }
    }

    let logicalSize = 64 * 1_024 * 1_024
    guard ftruncate(descriptor, off_t(logicalSize)) == 0 else {
        throw CocoaError(.fileWriteUnknown)
    }

    let marker = [UInt8](repeating: 0x5A, count: 4_096)
    let firstWrite = marker.withUnsafeBytes {
        pwrite(descriptor, $0.baseAddress, $0.count, 0)
    }
    let lastOffset = logicalSize - marker.count
    let lastWrite = marker.withUnsafeBytes {
        pwrite(descriptor, $0.baseAddress, $0.count, off_t(lastOffset))
    }
    guard firstWrite == marker.count, lastWrite == marker.count else {
        throw CocoaError(.fileWriteUnknown)
    }
    guard fsync(descriptor) == 0, close(descriptor) == 0 else {
        throw CocoaError(.fileWriteUnknown)
    }
    descriptorToClose = -1

    let entry = try scannedEntry(at: fileURL)
    let map = try FileExtentReader().inspect(entry)
    let dataExtents = try knownValue(map.dataExtents)

    #expect(!dataExtents.isEmpty)
    #expect(dataExtents.first?.offset == 0)
    #expect(
        dataExtents.last.map { $0.offset + $0.length } ==
            UInt64(logicalSize)
    )
    #expect(
        dataExtents.reduce(UInt64(0)) { $0 + $1.length } <
            UInt64(logicalSize)
    )

    let physicalExtents = try knownValue(map.physicalExtents)
    #expect(!physicalExtents.isEmpty)
    let physicalBytes = physicalExtents.reduce(UInt64(0)) {
        $0 + $1.length
    }
    let dataBytes = dataExtents.reduce(UInt64(0)) {
        $0 + $1.length
    }
    #expect(physicalBytes == dataBytes)
}

@Test func clonedFilesResolveToTheSamePhysicalExtents() throws {
    let fixture = try ExtentFixture()
    defer { fixture.remove() }

    let sourceURL = fixture.root.appending(path: "source")
    let cloneURL = fixture.root.appending(path: "clone")
    try Data(repeating: 0xC3, count: 1_048_576).write(to: sourceURL)
    guard clonefile(sourceURL.path, cloneURL.path, 0) == 0 else {
        throw CocoaError(.fileWriteUnknown)
    }

    let sourceMap = try FileExtentReader().inspect(
        try scannedEntry(at: sourceURL)
    )
    let cloneMap = try FileExtentReader().inspect(
        try scannedEntry(at: cloneURL)
    )

    let sourceExtents = try knownValue(sourceMap.physicalExtents)
    let cloneExtents = try knownValue(cloneMap.physicalExtents)
    let sourceClone = try knownValue(sourceMap.cloneMetadata)
    let cloneClone = try knownValue(cloneMap.cloneMetadata)
    #expect(!sourceExtents.isEmpty)
    #expect(sourceExtents == cloneExtents)
    #expect(sourceClone.identifier != 0)
    #expect(sourceClone.identifier == cloneClone.identifier)
    #expect(sourceClone.referenceCount >= 2)
    #expect(cloneClone.referenceCount >= 2)
}

@Test func extentReaderRejectsAPathWhoseIdentityChanged() throws {
    let fixture = try ExtentFixture()
    defer { fixture.remove() }

    let fileURL = fixture.root.appending(path: "replace-me")
    try Data("first".utf8).write(to: fileURL)
    let originalEntry = try scannedEntry(at: fileURL)

    try FileManager.default.removeItem(at: fileURL)
    try Data("replacement".utf8).write(to: fileURL)

    #expect(throws: FileExtentError.identityChanged(path: fileURL.path)) {
        try FileExtentReader().inspect(originalEntry)
    }
}

private func scannedEntry(at url: URL) throws -> StorageEntry {
    var result: StorageEntry?
    try StorageScanner().walk(at: url) {
        result = $0
    }
    return try #require(result)
}

private struct ExpectedKnownValue: Error {}

private func knownValue<Value: Sendable>(
    _ measurement: FathomKit.Measurement<Value>
) throws -> Value {
    guard case let .known(value, _) = measurement else {
        throw ExpectedKnownValue()
    }
    return value
}

private struct ExtentFixture {
    let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appending(path: "FathomExtentTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: false
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}
