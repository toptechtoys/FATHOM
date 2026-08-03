@testable import FathomKit
import Foundation
import Testing

@Test
func fullDiskAccessReaderDoesNotGuessWhenCanaryIsMissing() {
    let missingHome = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    #expect(
        FullDiskAccessReader().read(homeDirectory: missingHome) ==
            .notPublished(reason: "The Full Disk Access canary does not exist")
    )
}
