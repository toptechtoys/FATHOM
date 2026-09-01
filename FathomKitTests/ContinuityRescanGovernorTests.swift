@testable import FathomKit
import Foundation
import Testing

private let epoch = Date(timeIntervalSince1970: 1_756_000_000)

@Test
func theFirstContinuityRescanRunsImmediately() {
    var governor = ContinuityRescanGovernor(floor: 1800)
    #expect(governor.request(now: epoch) == .rescanNow)
}

@Test
func aRescanInsideTheFloorIsHeldUntilTheFloorExpires() {
    var governor = ContinuityRescanGovernor(floor: 1800)
    #expect(governor.request(now: epoch) == .rescanNow)
    governor.recordRescanEnded(at: epoch.addingTimeInterval(600))
    #expect(
        governor.request(now: epoch.addingTimeInterval(700))
            == .held(until: epoch.addingTimeInterval(2400))
    )
}

@Test
func theHeldTriggerRunsOnceWhenTheFloorLifts() {
    var governor = ContinuityRescanGovernor(floor: 1800)
    _ = governor.request(now: epoch)
    governor.recordRescanEnded(at: epoch.addingTimeInterval(600))
    _ = governor.request(now: epoch.addingTimeInterval(700))

    #expect(governor.releaseIfDue(now: epoch.addingTimeInterval(2399)) == nil)
    #expect(
        governor.releaseIfDue(now: epoch.addingTimeInterval(2400))
            == .rescanNow
    )
    #expect(governor.releaseIfDue(now: epoch.addingTimeInterval(2401)) == nil)
}

@Test
func aRescanThatRunsClearsATriggerStillHeld() {
    var governor = ContinuityRescanGovernor(floor: 1800)
    _ = governor.request(now: epoch)
    governor.recordRescanEnded(at: epoch)
    #expect(
        governor.request(now: epoch.addingTimeInterval(60))
            == .held(until: epoch.addingTimeInterval(1800))
    )

    // The floor lifts, and a fresh trigger arrives before anything polled the
    // held one. That scan answers both; nothing is left owing behind it.
    #expect(governor.request(now: epoch.addingTimeInterval(1900)) == .rescanNow)
    #expect(governor.releaseIfDue(now: epoch.addingTimeInterval(2000)) == nil)
}

/// The property the whole floor exists for: a storm of triggers inside one
/// floor costs one scan, not one scan each.
@Test
func manyTriggersInsideOneFloorCostOneScan() {
    var governor = ContinuityRescanGovernor(floor: 1800)
    _ = governor.request(now: epoch)
    governor.recordRescanEnded(at: epoch)

    var scans = 0
    for second in stride(from: 1.0, through: 1799.0, by: 1.0) {
        let moment = epoch.addingTimeInterval(second)
        if governor.request(now: moment) == .rescanNow { scans += 1 }
        if governor.releaseIfDue(now: moment) == .rescanNow { scans += 1 }
    }
    #expect(scans == 0)
    #expect(
        governor.releaseIfDue(now: epoch.addingTimeInterval(1800))
            == .rescanNow
    )
}

/// A floor shorter than a scan is not a floor: the next trigger would arrive
/// before the previous scan had even finished. A Deep Scan measured about ten
/// minutes end to end on this machine on 1 September 2026.
@Test
func theDefaultFloorOutlastsAScan() {
    #expect(ContinuityRescanGovernor.defaultFloor > 600)
}

@Test
func aScanFromAnywhereSatisfiesAHeldTrigger() {
    var governor = ContinuityRescanGovernor(floor: 1800)
    _ = governor.request(now: epoch)
    governor.recordRescanEnded(at: epoch)
    #expect(
        governor.request(now: epoch.addingTimeInterval(60))
            == .held(until: epoch.addingTimeInterval(1800))
    )

    // The owner starts a Deep Scan by hand and it finishes. Whatever the hold
    // was owed, that scan has already paid it.
    governor.recordRescanEnded(at: epoch.addingTimeInterval(600))
    #expect(governor.releaseIfDue(now: epoch.addingTimeInterval(3000)) == nil)
}
