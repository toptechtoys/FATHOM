@testable import FathomKit
import Foundation
import Testing

@Test
func volumeEncryptionIsPublishedOrNamesTheFilesystemGap() {
    switch VolumeEncryptionReader().read(volumeURL: URL(fileURLWithPath: "/")) {
    case let .known(_, source):
        #expect(source == .volumeIsEncrypted)
    case let .notPublished(reason):
        #expect(!reason.isEmpty)
    case .notAttributable:
        Issue.record("A direct volume Boolean cannot be unattributable")
    }
}
