import Foundation
import Testing
@testable import FathomKit

@Test func volumeCapacityReaderKeepsFinderAndImportantUsageSeparate()
    throws
{
    let volumeURL = try #require(
        FileManager.default.temporaryDirectory.resourceValues(
            forKeys: [.volumeURLKey]
        ).volume
    )
    let snapshot = VolumeCapacityReader().read(volumeURL: volumeURL)

    guard
        case let .known(actual, actualSource) = snapshot.actuallyFree,
        case let .known(finder, finderSource) = snapshot.finderAvailable
    else {
        Issue.record("The fixture volume did not publish capacity")
        return
    }
    #expect(actualSource == .volumeAvailableCapacityForImportantUsage)
    #expect(finderSource == .statfsAvailableCapacity)
    switch snapshot.purgeable {
    case let .known(purgeable, source):
        #expect(source == .derivedPurgeableCapacity)
        #expect(finder == actual + purgeable)
    case .notPublished:
        // The two APIs are separate live reads and may cross while storage is
        // changing; the reader must refuse a negative derived value.
        #expect(finder < actual)
    case .notAttributable:
        Issue.record("A direct capacity difference must be attributable")
    }
}
