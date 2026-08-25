import CFathomHardware
import Foundation
import Testing
@testable import FathomKit

/// Every figure below is a row from `FATHOM-DATA-SOURCES.md` §SSD health,
/// restated as parsed fields — the counters the doc records in, the
/// conversions it specifies out. That is what this test pins: the ×512 000,
/// the kelvin subtraction and the two endurance derivations, against the
/// reviewed contract rather than anyone's memory.
///
/// It is **not** the recorded-bytes fixture `RELEASE-GATES.md` gate 2 asks
/// for, and must not be mistaken for it when that capture lands: no raw
/// SMART log page has ever been committed here, and a parser that misreads
/// real bytes would still pass this test.
@Test func nvmeSMARTConversionsMatchTheRecordedContractRows() throws {
    var raw = fathom_nvme_smart_data()
    raw.temperature_kelvin = 321
    raw.available_spare = 100
    raw.percentage_used = 5
    raw.data_units_read_low = 333_359_375
    raw.data_units_written_low = 292_910_156
    raw.power_on_hours_low = 1_925
    raw.power_cycles_low = 520
    raw.unsafe_shutdowns_low = 43
    raw.media_errors_low = 0

    let snapshot = NVMeSMARTReader.parse(raw)

    #expect(
        try known(snapshot.bytesWritten) == 149_969_999_872_000
    )
    #expect(try known(snapshot.bytesRead) == 170_680_000_000_000)
    #expect(try known(snapshot.percentageUsed) == 5)
    #expect(try known(snapshot.availableSparePercent) == 100)
    #expect(try known(snapshot.powerOnHours) == 1_925)
    #expect(try known(snapshot.powerCycles) == 520)
    #expect(try known(snapshot.unsafeShutdowns) == 43)
    #expect(try known(snapshot.mediaErrors) == 0)
    #expect(
        abs(try known(snapshot.temperatureCelsius) - 47.85) < 0.0001
    )
    #expect(
        abs(
            try known(snapshot.lifetimeBytesWrittenPerHour) -
                77_906_493_440
        ) < 1
    )
    #expect(
        try known(snapshot.linearPowerOnHoursAtHundredPercent) == 38_500
    )
}

@Test func nvmeSMARTRefusesCountersOutsideItsPublishedRange() {
    var raw = fathom_nvme_smart_data()
    raw.temperature_kelvin = 300
    raw.data_units_written_high = 1
    raw.power_on_hours_low = 1
    raw.percentage_used = 1

    let snapshot = NVMeSMARTReader.parse(raw)
    guard case let .notPublished(reason) = snapshot.bytesWritten else {
        Issue.record("The overflowing counter was published")
        return
    }
    #expect(reason.contains("64-bit"))
    guard case .notPublished = snapshot.lifetimeBytesWrittenPerHour else {
        Issue.record("A rate derived from an unavailable counter was published")
        return
    }
}

@Test func nvmeSMARTDoesNotProjectFromZeroWear() {
    var raw = fathom_nvme_smart_data()
    raw.temperature_kelvin = 300
    raw.power_on_hours_low = 4_000
    raw.percentage_used = 0

    let snapshot = NVMeSMARTReader.parse(raw)
    guard
        case let .notPublished(reason) =
            snapshot.linearPowerOnHoursAtHundredPercent
    else {
        Issue.record("A finite projection was invented from zero wear")
        return
    }
    #expect(reason.contains("finite projection"))
}

private func known<T: Sendable>(
    _ measurement: FathomKit.Measurement<T>
) throws -> T {
    guard case let .known(value, _) = measurement else {
        throw NotKnownInTestError.notKnown
    }
    return value
}

private enum NotKnownInTestError: Error {
    case notKnown
}
