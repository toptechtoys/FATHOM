@testable import FathomKit
import Foundation
import Testing

@Test
func weeklyDigestRequiresEvidenceAndSilencesAQuietWeek() {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    #expect(
        WeeklyDigestPlanner.plan(
            changeInFreeBytes: .notPublished(reason: "Two scans required"),
            now: now
        ) == .notPublished(reason: "Two scans required")
    )
    #expect(
        WeeklyDigestPlanner.plan(
            changeInFreeBytes: .known(0, source: .persistedStorageHistoryDelta),
            now: now
        ) == .notPublished(reason: "The week is quiet; no notification is scheduled")
    )
}

@Test
func weeklyDigestPlansTheNextSundayAtNineWithMeasuredBytes() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let result = WeeklyDigestPlanner.plan(
        changeInFreeBytes: .known(-4_100_000_000, source: .persistedStorageHistoryDelta),
        now: now,
        calendar: calendar
    )
    guard case let .known(plan, source) = result else {
        Issue.record("Expected a known notification plan")
        return
    }
    let components = calendar.dateComponents([.weekday, .hour, .minute], from: plan.fireDate)
    #expect(components.weekday == 1)
    #expect(components.hour == 9)
    #expect(components.minute == 0)
    #expect(plan.fireDate > now)
    #expect(plan.body.contains("4.1 GB"))
    #expect(source == .persistedStorageHistoryDelta)
}
