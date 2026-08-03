import Darwin
import Foundation
import FathomKit
import Testing

@Test func engineRunsTraversalExtentsAndFamiliesAsOneScan() async throws {
    let fixture = try EngineFixture()
    defer { fixture.remove() }

    let sourceURL = fixture.root.appending(path: "source")
    let cloneURL = fixture.root.appending(path: "clone")
    let ordinaryURL = fixture.root.appending(path: "ordinary")
    let linkURL = fixture.root.appending(path: "link")

    try Data(repeating: 0x41, count: 1_048_576).write(to: sourceURL)
    guard clonefile(sourceURL.path, cloneURL.path, 0) == 0 else {
        throw CocoaError(.fileWriteUnknown)
    }
    try Data("ordinary".utf8).write(to: ordinaryURL)
    try FileManager.default.createSymbolicLink(
        at: linkURL,
        withDestinationURL: ordinaryURL
    )

    let engine = StorageEngine(
        configuration: StorageEngineConfiguration(
            maximumConcurrentExtentReads: 2
        )
    )
    let result = try await engine.scan(
        at: fixture.root,
        scope: .subtree
    )

    #expect(result.isComplete)
    #expect(result.issues.isEmpty)
    #expect(result.entries.count == 5)
    #expect(result.inspectedFiles.count == 3)
    #expect(
        result.inspectedFiles.map(\.entry.path) ==
            [sourceURL.path, cloneURL.path, ordinaryURL.path].sorted()
    )

    let families = try engineKnownValue(result.cloneFamilies)
    let family = try #require(families.first)
    #expect(families.count == 1)
    #expect(family.memberPaths == [sourceURL.path, cloneURL.path].sorted())

    let accounting = try engineKnownValue(
        StorageAccountingBuilder().build(from: result)
    )
    let rootNode = accounting.nodes[Int(accounting.rootID.rawValue)]
    let rootBytes = try engineKnownValue(rootNode.subtreeSizeOnDisk)
    let rawBytes = try result.entries.reduce(UInt64(0)) {
        $0 + (try engineKnownValue($1.sizeOnDisk))
    }
    let familyMemberBytes = try result.entries
        .filter { family.memberPaths.contains($0.path) }
        .reduce(UInt64(0)) {
            $0 + (try engineKnownValue($1.sizeOnDisk))
        }
    let familyBytes = try engineKnownValue(family.sizeOnDisk)

    #expect(rootBytes == rawBytes - familyMemberBytes + familyBytes)
    #expect(accounting.path(for: accounting.rootID) == fixture.root.path)
    let cloneNode = try #require(
        accounting.nodes.first {
            accounting.path(for: $0.id) == cloneURL.path
        }
    )
    #expect(
        try engineKnownValue(cloneNode.exclusiveSizeOnDisk) == 0
    )
}

@Test func engineKeepsAnEmptyDirectoryAsACompleteResult() async throws {
    let fixture = try EngineFixture()
    defer { fixture.remove() }

    let result = try await StorageEngine().scan(
        at: fixture.root,
        scope: .subtree
    )

    #expect(result.isComplete)
    #expect(result.entries.count == 1)
    #expect(result.inspectedFiles.isEmpty)
    #expect(try engineKnownValue(result.cloneFamilies).isEmpty)
}

private struct ExpectedEngineKnownValue: Error {}

private func engineKnownValue<Value: Sendable>(
    _ measurement: FathomKit.Measurement<Value>
) throws -> Value {
    guard case let .known(value, _) = measurement else {
        throw ExpectedEngineKnownValue()
    }
    return value
}

private struct EngineFixture {
    let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appending(path: "FathomEngineTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: false
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}
