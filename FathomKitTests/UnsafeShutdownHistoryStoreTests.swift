@testable import FathomKit
import Foundation
import Testing

@Test
func unsafeShutdownWindowWaitsThirtyDaysThenSubtractsExactCounters() async {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
        .appendingPathComponent("unsafe.json")
    let store = UnsafeShutdownHistoryStore(url: url)
    let start = Date(timeIntervalSince1970: 1_700_000_000)
    #expect(
        await store.record(
            .known(40, source: .nvmeSMARTLogPage),
            now: start
        ) == .notPublished(reason: "Thirty days of unsafe-shutdown history are required")
    )
    let result = await store.record(
        .known(43, source: .nvmeSMARTLogPage),
        now: start.addingTimeInterval(31 * 24 * 60 * 60)
    )
    guard case let .known(window, source) = result else {
        Issue.record("Expected a known counter window")
        return
    }
    #expect(window.count == 3)
    #expect(window.start == start)
    #expect(source == .persistedSMARTCounterDelta)
}

@Test
func unsafeShutdownWindowDoesNotHideACounterReset() async {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
        .appendingPathComponent("unsafe.json")
    let store = UnsafeShutdownHistoryStore(url: url)
    let start = Date(timeIntervalSince1970: 1_700_000_000)
    _ = await store.record(.known(40, source: .nvmeSMARTLogPage), now: start)
    #expect(
        await store.record(
            .known(2, source: .nvmeSMARTLogPage),
            now: start.addingTimeInterval(31 * 24 * 60 * 60)
        ) == .notPublished(reason: "The unsafe-shutdown counter reset")
    )
}
