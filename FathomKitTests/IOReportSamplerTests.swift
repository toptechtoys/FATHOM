import Foundation
@testable import FathomKit
import Testing

@Test
func bundledIOReportChannelMapHasAValidEd25519Signature() {
    #expect(IOReportChannelMapLoader.bundledSignatureIsValid())
    #expect(!IOReportChannelMapLoader.verify(payload: Data("tampered".utf8), signature: Data()))
}
@Test func ioReportEnergyUnitsConvertOnlyWhenNamed() throws {
    let raw: FathomKit.Measurement<Int64> = .known(
        500_000,
        source: .ioReportSampleDelta
    )
    #expect(
        try known(
            IOReportSampler.watts(
                value: raw,
                unit: "uJ",
                elapsedSeconds: 0.5
            )
        ) == 1
    )
    guard case let .notPublished(reason) = IOReportSampler.watts(
        value: raw,
        unit: "ticks",
        elapsedSeconds: 0.5
    ) else {
        Issue.record("An unknown energy unit was converted")
        return
    }
    #expect(reason.contains("not supported"))
}

@Test func ioReportInventoryIsPublishedOrNamesTheRuntimeGap() {
    switch IOReportReader().channelInventory() {
    case let .known(channels, source):
        #expect(source == .ioReportChannelInventory)
        #expect(!channels.isEmpty)
    case let .notPublished(reason):
        #expect(!reason.isEmpty)
    case .notAttributable:
        Issue.record("Channel enumeration is not an attribution problem")
    }
}

private func known<T: Sendable>(
    _ measurement: FathomKit.Measurement<T>
) throws -> T {
    guard case let .known(value, _) = measurement else {
        throw IOReportFixtureError.notKnown
    }
    return value
}

private enum IOReportFixtureError: Error {
    case notKnown
}
