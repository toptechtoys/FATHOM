import Foundation
import Testing
@testable import FathomKit

// Replays the recorded IOReport and IOHID payloads through the shipping
// decoders, and records what this Mac refuses to publish. See
// `RecordedHardwareFixtures.swift` for what these recordings are.

// MARK: - IOReport

@Test func recordedIOReportChannelInventoryDecodesThroughTheShippingDecoder() throws {
    let payload = try RecordedHardware.data("ioreport-channel-inventory.plist")
    let decoded = try RecordedHardware.known(
        IOReportReader.decodeChannelInventory(payload)
    )
    #expect(decoded.source == .ioReportChannelInventory)
    #expect(decoded.value.count == 10_570)
    #expect(decoded.value.contains { $0.group == "Energy Model" })
    #expect(decoded.value.allSatisfy { !$0.channel.isEmpty })
}

@Test func recordedIOReportDeltaConvertsToTheWattageTheProductRenders() throws {
    let manifest = try RecordedHardware.manifest()
    let snapshot = try RecordedHardware.delta()
    #expect(snapshot.channels.count == 664)
    #expect(snapshot.elapsedSeconds == manifest.ioReportSampleElapsedSeconds)

    let cpu0 = try #require(
        snapshot.channels.first { $0.channel == "EACC_CPU0" },
        "EACC_CPU0 is not in the recorded delta"
    )
    #expect(cpu0.group == "Energy Model")
    #expect(cpu0.unit == "mJ")
    #expect(try RecordedHardware.known(cpu0.integerValue).value == 100)

    // 100 mJ over 1.0147145 s. This is the exact arithmetic the Sensors and
    // Power sections render, run against a counter a real SoC produced.
    let watts = try RecordedHardware.known(
        IOReportSampler.watts(
            value: cpu0.integerValue,
            unit: cpu0.unit,
            elapsedSeconds: manifest.ioReportSampleElapsedSeconds
        )
    )
    #expect(watts.source == .ioReportEnergyDelta)
    #expect(watts.value == 0.09854988767776553)
}

@Test func recordedIOReportChannelsThatAreNotEnergyAreNeverRenderedAsWatts() throws {
    let manifest = try RecordedHardware.manifest()
    let snapshot = try RecordedHardware.delta()
    // The delta carries clock ticks, microseconds, event counts and kibibytes
    // beside its joules. Converting any of them would render a figure that
    // looks like power and is not.
    let energyUnits = ["J", "mJ", "uJ", "\u{00B5}J", "nJ"]
    let nonEnergy = snapshot.channels.filter {
        !energyUnits.contains(
            $0.unit.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }
    #expect(!nonEnergy.isEmpty)
    for channel in nonEnergy {
        #expect(
            RecordedHardware.isNotPublished(
                IOReportSampler.watts(
                    value: channel.integerValue,
                    unit: channel.unit,
                    elapsedSeconds: manifest.ioReportSampleElapsedSeconds
                )
            ),
            "\(channel.channel) in \(channel.unit) was converted to watts"
        )
    }
}

@Test func recordedIOReportStateChannelsPublishResidenciesNotACounter() throws {
    let snapshot = try RecordedHardware.delta()
    let withoutCounter = snapshot.channels.filter {
        RecordedHardware.isNotPublished($0.integerValue)
    }
    // A channel with no simple counter renders not published rather than zero.
    // Zero is a number the product would have drawn.
    #expect(withoutCounter.count == 54)

    let complex = try #require(
        snapshot.channels.first {
            $0.channel == "ECPU" && $0.subgroup == "CPU Complex Voltage States"
        },
        "The ECPU voltage-state channel is not in the recorded delta"
    )
    #expect(RecordedHardware.isNotPublished(complex.integerValue))
    let states = try RecordedHardware.known(complex.states)
    #expect(states.source == .ioReportSampleDelta)
    #expect(states.value.count == 6)
    #expect(states.value.allSatisfy { !$0.name.isEmpty })
}

// MARK: - IOHID temperatures

@Test func recordedIOHIDTemperaturesDecodeThroughTheShippingDecoder() throws {
    let payload = try RecordedHardware.data("iohid-temperature-sensors.plist")
    let decoded = try RecordedHardware.known(
        TemperatureSensorReader.decodeSensors(payload)
    )
    #expect(decoded.source == .ioHIDTemperatureEvent)
    #expect(decoded.value.count == 45)

    let pmu = try #require(
        decoded.value.first { $0.name == "PMU tdie1" },
        "PMU tdie1 is not in the recorded sensor set"
    )
    #expect(try RecordedHardware.known(pmu.celsius).value == 53.170257568359375)

    // Every sensor names itself and reads inside the range silicon survives.
    for reading in decoded.value {
        #expect(!reading.name.isEmpty)
        let celsius = try RecordedHardware.known(reading.celsius).value
        #expect(
            celsius > -40 && celsius < 125,
            "\(reading.name) read \(celsius) C, outside anything a die reports"
        )
    }
}

@Test func anEmptyTemperaturePayloadIsNotPublishedRatherThanAnEmptyList() {
    let empty = Data("<plist version=\"1.0\"><array/></plist>".utf8)
    #expect(
        RecordedHardware.isNotPublished(
            TemperatureSensorReader.decodeSensors(empty)
        )
    )
}

// MARK: - What this Mac will not publish

@Test func theRecordingMacDoesNotPublishNVMeSMARTAndSaysWhy() throws {
    let manifest = try RecordedHardware.manifest()
    let nvme = try #require(
        manifest.payloads.first { $0.name == "nvme-smart-log-page.bin" },
        "The NVMe payload is not named in the manifest"
    )
    #expect(nvme.state == "not published")
    #expect(nvme.sha256 == nil)
    #expect(nvme.byteCount == nil)

    // IOReturn -536870201 is 0xe00002c7, kIOReturnUnsupported -- not
    // kIOReturnNotPrivileged (0x2c1) and not kIOReturnNotPermitted (0x2e2).
    // AppleANS3CGv2Controller offers no SMART user client, so no entitlement
    // changes this reading, and the fixture records the refusal rather than
    // leaving a gap someone later fills with an estimate.
    let reason = try #require(nvme.reason)
    #expect(reason.contains("-536870201"))

    let sidecar = try #require(
        String(
            bytes: RecordedHardware.data(
                "nvme-smart-log-page.bin.notpublished.txt"
            ),
            encoding: .utf8
        ),
        "The NVMe refusal reason is not readable as UTF-8"
    )
    #expect(sidecar.contains("-536870201"))
}
