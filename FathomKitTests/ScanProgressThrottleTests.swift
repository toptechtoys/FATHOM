@testable import FathomKit
import Foundation
import Testing

private let epoch = Date(timeIntervalSince1970: 1_756_000_000)

@Test
func theFirstEntryPublishesAtOnce() {
    var throttle = ScanProgressThrottle(interval: 0.1)
    let shown = throttle.accumulate(
        path: "/Users/a/Documents/report.pdf",
        bytesOnDisk: 4096,
        now: epoch
    )
    #expect(shown?.currentDirectory == "/Users/a/Documents")
    #expect(shown?.entryCount == 1)
    #expect(shown?.bytesOnDisk == 4096)
}

@Test
func anEntryInsideTheIntervalPublishesNothing() {
    var throttle = ScanProgressThrottle(interval: 0.1)
    _ = throttle.accumulate(path: "/a/b.txt", bytesOnDisk: 10, now: epoch)
    #expect(
        throttle.accumulate(
            path: "/a/c.txt",
            bytesOnDisk: 10,
            now: epoch.addingTimeInterval(0.05)
        ) == nil
    )
}

@Test
func aDirectoryEntryShowsItselfRatherThanItsParent() {
    var throttle = ScanProgressThrottle(interval: 0.1)
    let shown = throttle.accumulate(
        path: "/Users/a/Documents",
        isDirectory: true,
        bytesOnDisk: 0,
        now: epoch
    )
    #expect(shown?.currentDirectory == "/Users/a/Documents")
}

@Test
func theHomeDirectoryIsAbbreviated() {
    var throttle = ScanProgressThrottle(
        interval: 0.1,
        home: "/Users/exhibinaut"
    )
    let shown = throttle.accumulate(
        path: "/Users/exhibinaut/Documents/report.pdf",
        bytesOnDisk: 10,
        now: epoch
    )
    #expect(shown?.currentDirectory == "~/Documents")
}

/// The point of the throttle is to publish less, not to count less. Entries
/// that never reach the screen still have to reach the totals.
@Test
func suppressedEntriesStillReachTheTotals() {
    var throttle = ScanProgressThrottle(interval: 0.1, home: "")
    _ = throttle.accumulate(path: "/a/1", bytesOnDisk: 100, now: epoch)
    for second in [0.01, 0.02, 0.03] {
        #expect(
            throttle.accumulate(
                path: "/a/x",
                bytesOnDisk: 100,
                now: epoch.addingTimeInterval(second)
            ) == nil
        )
    }
    let shown = throttle.accumulate(
        path: "/a/5",
        bytesOnDisk: 100,
        now: epoch.addingTimeInterval(0.5)
    )
    #expect(shown?.entryCount == 5)
    #expect(shown?.bytesOnDisk == 500)
}

@Test
func anEntryWithNoPublishedSizeStillCounts() {
    var throttle = ScanProgressThrottle(interval: 0, home: "")
    _ = throttle.accumulate(path: "/a/1", bytesOnDisk: nil, now: epoch)
    let shown = throttle.accumulate(
        path: "/a/2",
        bytesOnDisk: 7,
        now: epoch.addingTimeInterval(1)
    )
    #expect(shown?.entryCount == 2)
    #expect(shown?.bytesOnDisk == 7)
}

/// The walk starts at the volume root, so home arrives firmlinked — the same
/// directory reached by its `/System/Volumes/Data` path rather than by
/// `/Users`. A readout that only knows the short form abbreviates nothing
/// during the phase where almost every entry is under home.
@Test
func aFirmlinkedHomePathIsAbbreviatedToo() {
    var throttle = ScanProgressThrottle(
        interval: 0.1,
        home: "/Users/exhibinaut"
    )
    let shown = throttle.accumulate(
        path: "/System/Volumes/Data/Users/exhibinaut/Documents/report.pdf",
        bytesOnDisk: 10,
        now: epoch
    )
    #expect(shown?.currentDirectory == "~/Documents")
}
