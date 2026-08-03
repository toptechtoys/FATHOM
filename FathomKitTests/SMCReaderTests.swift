import CFathomHardware
import Testing
@testable import FathomKit

@Test func smcFourCharacterKeysRoundTripExactly() throws {
    let raw = try #require(SMCReader.key(forString: "F0Ac"))
    #expect(raw == 0x46304163)
    #expect(SMCReader.string(forKey: raw) == "F0Ac")
    #expect(SMCReader.key(forString: "three") == nil)
}

@Test func smcFanSelectionUsesOnlyEnumeratedActualSpeedKeys() {
    #expect(SMCReader.isActualFanSpeedKey("F0Ac"))
    #expect(SMCReader.isActualFanSpeedKey("F9Ac"))
    #expect(!SMCReader.isActualFanSpeedKey("F0Mn"))
    #expect(!SMCReader.isActualFanSpeedKey("TC0P"))
}

@Test func smcFixedPointFormatsDecodeWithoutEstimation() {
    var fan = fathom_smc_value()
    fan.data_type = 0x66706532 // fpe2
    fan.data_size = 2
    withUnsafeMutableBytes(of: &fan.bytes) {
        $0[0] = 0x13
        $0[1] = 0x88
    }
    var fanValue = 0.0
    #expect(fathom_smc_decode_numeric(&fan, &fanValue) == 0)
    #expect(fanValue == 1_250)

    var temperature = fathom_smc_value()
    temperature.data_type = 0x73703738 // sp78
    temperature.data_size = 2
    withUnsafeMutableBytes(of: &temperature.bytes) {
        $0[0] = 0x2F
        $0[1] = 0x80
    }
    var temperatureValue = 0.0
    #expect(
        fathom_smc_decode_numeric(
            &temperature,
            &temperatureValue
        ) == 0
    )
    #expect(temperatureValue == 47.5)
}

@Test func smcUnknownWireFormatIsNotDecoded() {
    var raw = fathom_smc_value()
    raw.data_type = 0x78787878
    raw.data_size = 4
    var value = 0.0
    #expect(fathom_smc_decode_numeric(&raw, &value) != 0)
}

@Test func failedSMCProbeIsBlacklistedForTheSession() {
    let session = SMCProbeSession()
    var probes = 0
    let first = session.measurement(for: "PSTR") {
        probes += 1
        return .notPublished(reason: "timed out")
    }
    let second = session.measurement(for: "PSTR") {
        probes += 1
        return .known(42, source: .appleSMCReadKey)
    }
    #expect(first == .notPublished(reason: "timed out"))
    #expect(second == first)
    #expect(probes == 1)
    #expect(session.blacklistedKeys == ["PSTR"])
}
