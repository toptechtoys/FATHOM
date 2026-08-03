import CoreServices
@testable import FathomKit
import Foundation
import Testing

@Test
func fseventContinuityFlagsNeverPublishACompleteWindow() {
    let flags: [FSEventStreamEventFlags] = [
        FSEventStreamEventFlags(kFSEventStreamEventFlagMustScanSubDirs),
        FSEventStreamEventFlags(kFSEventStreamEventFlagUserDropped),
        FSEventStreamEventFlags(kFSEventStreamEventFlagKernelDropped),
        FSEventStreamEventFlags(kFSEventStreamEventFlagEventIdsWrapped),
        FSEventStreamEventFlags(kFSEventStreamEventFlagRootChanged)
    ]
    for flag in flags {
        #expect(FSEventRecorder.continuityReason(flags: flag) != nil)
    }
    #expect(FSEventRecorder.continuityReason(flags: 0) == nil)
}

@Test
func fseventVolumeIdentityIsStableForTheSameVolume() {
    let url = FileManager.default.homeDirectoryForCurrentUser
    let first = FSEventRecorder.volumeUUID(for: url)
    let second = FSEventRecorder.volumeUUID(for: url)
    #expect(first == second)
}

@Test
func fathomIndexWritesAreExcludedFromItsOwnEventStream() {
    let home = URL(fileURLWithPath: "/Users/fixture")
    #expect(
        FSEventRecorder.isFathomPrivatePath(
            "/Users/fixture/Library/Application Support/FATHOM/storage.sqlite-wal",
            home: home
        )
    )
    #expect(
        !FSEventRecorder.isFathomPrivatePath(
            "/Users/fixture/Library/Application Support/Xcode/cache",
            home: home
        )
    )
}
