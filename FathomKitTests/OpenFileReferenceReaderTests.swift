import Darwin
import Foundation
import FathomKit
import Testing

@Test func readerObservesTheCurrentProcessesOpenFileIdentity() throws {
    let root = FileManager.default.temporaryDirectory
        .appending(path: "FathomOpenFileTests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(
        at: root,
        withIntermediateDirectories: false
    )
    defer { try? FileManager.default.removeItem(at: root) }

    let fileURL = root.appending(path: "held-open")
    let descriptor = open(
        fileURL.path,
        O_CREAT | O_RDWR,
        S_IRUSR | S_IWUSR
    )
    guard descriptor >= 0 else {
        throw CocoaError(.fileWriteUnknown)
    }
    defer { close(descriptor) }

    var metadata = stat()
    guard fstat(descriptor, &metadata) == 0 else {
        throw CocoaError(.fileReadUnknown)
    }
    let identity = FileIdentity(
        device: UInt64(metadata.st_dev),
        inode: UInt64(metadata.st_ino)
    )

    let inventory = try OpenFileReferenceReader().inventory()
    #expect(inventory.observedIdentities.contains(identity))
    if inventory.inaccessibleProcessCount == 0 {
        #expect(
            inventory.completeIdentities ==
                .known(
                    inventory.observedIdentities,
                    source: .procOpenFileDescriptors
                )
        )
    } else if case let .notPublished(reason) =
        inventory.completeIdentities
    {
        #expect(!reason.isEmpty)
    } else {
        Issue.record(
            "An incomplete process walk must not publish a complete identity set"
        )
    }
}
