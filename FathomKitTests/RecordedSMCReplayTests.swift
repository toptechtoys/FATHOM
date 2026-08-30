import CryptoKit
import Foundation
import Testing
@testable import FathomKit

// Replays the recorded AppleSMC payloads through the shipping decoder, and
// checks the recording itself. See `RecordedHardwareFixtures.swift` for what
// these recordings are and which Mac they came from.

// MARK: - What the recording is

@Test func theRecordingNamesTheMacItCameFrom() throws {
    let manifest = try RecordedHardware.manifest()
    #expect(manifest.machine.hardwareModel == "Mac15,9")
    #expect(manifest.machine.chipBrand == "Apple M3 Max")
    #expect(manifest.machine.appleSilicon == "yes")
}

@Test func recordedFixturesStillMatchTheHashesTheCaptureWrote() throws {
    let manifest = try RecordedHardware.manifest()
    var checked = 0
    for payload in manifest.payloads {
        guard let expected = payload.sha256 else {
            // The only payload without a hash is the one this Mac refused.
            #expect(payload.state == "not published")
            continue
        }
        let bytes = try RecordedHardware.data(payload.name)
        let actual = SHA256.hash(data: bytes)
            .map { String(format: "%02x", $0) }
            .joined()
        #expect(
            actual == expected,
            "\(payload.name) no longer matches the hash the capture recorded"
        )
        #expect(bytes.count == payload.byteCount)
        checked += 1
    }
    #expect(checked == 6)
}

// MARK: - AppleSMC

@Test func recordedSMCCaptureAccountsForEveryKeyTheMacEnumerated() throws {
    let enumerated = try JSONDecoder().decode(
        [String].self,
        from: RecordedHardware.data("smc-key-inventory.json")
    )
    let recorded = try RecordedHardware.smc()

    #expect(enumerated.count == 2_750)
    #expect(recorded.values.count == 2_611)
    #expect(recorded.readKeyCount == recorded.values.count)
    #expect(recorded.refusedKeys.count == 139)
    #expect(recorded.refusedKeyCount == recorded.refusedKeys.count)

    // Non-negotiable 2, at the fixture layer: a key AppleSMC would not read is
    // carried with the reason, never quietly dropped. Every enumerated key is
    // in exactly one of the two halves.
    #expect(
        recorded.values.count + recorded.refusedKeys.count == enumerated.count
    )
    let accounted = Set(recorded.values.map(\.key))
        .union(recorded.refusedKeys.map(\.key))
    #expect(accounted == Set(enumerated))
}

@Test func recordedSMCFloatKeysDecodeToTheFiguresTheProductRenders() throws {
    let recorded = try RecordedHardware.smc()

    func decode(_ key: String) throws -> Double {
        let value = try #require(
            recorded.values.first { $0.key == key },
            "\(key) is not in the recording"
        )
        let bytes = try #require(value.bytes, "\(key) had its bytes withheld")
        let decoded = try RecordedHardware.known(
            SMCReader.decodeNumeric(
                SMCRawValue(
                    key: value.key,
                    dataType: value.dataType,
                    dataSize: value.dataSize,
                    bytes: bytes
                )
            )
        )
        #expect(decoded.source == .appleSMCReadKey)
        return decoded.value
    }

    // Total system power and both fan speeds, decoded by the shipping decoder
    // from the bytes AppleSMC actually returned. `flt ` is the little-endian
    // IEEE single the bridge memcpys, so these are exact, not rounded.
    #expect(try decode("PSTR") == 27.51932144165039)
    #expect(try decode("F0Ac") == 1_343.3135986328125)
    #expect(try decode("F1Ac") == 1_447.43408203125)
}

@Test func everyRecordedSMCValueEitherDecodesOrNamesWhyNot() throws {
    let recorded = try RecordedHardware.smc()
    var decoded = 0
    for value in recorded.values {
        guard let bytes = value.bytes else { continue }
        let raw = SMCRawValue(
            key: value.key,
            dataType: value.dataType,
            dataSize: value.dataSize,
            bytes: bytes
        )
        switch SMCReader.decodeNumeric(raw) {
        case let .known(number, source):
            #expect(
                number.isFinite,
                "\(value.key) decoded to a figure that is not finite"
            )
            #expect(source == .appleSMCReadKey)
            decoded += 1
        case let .notPublished(reason):
            #expect(
                !reason.isEmpty,
                "\(value.key) was not published with no reason given"
            )
        case .notAttributable:
            Issue.record(
                "\(value.key) came back not attributable, which no SMC key is"
            )
        }
    }
    // 2611 read, 405 with bytes withheld, so 2206 carry bytes -- and the
    // shipping decoder reads every one of them without a single refusal.
    #expect(decoded == 2_206)
}

@Test func recordedSMCWithholdingMatchesWhatTheShippingDecoderRefuses() throws {
    let recorded = try RecordedHardware.smc()
    var withheld = 0
    for value in recorded.values where value.bytes == nil {
        withheld += 1
        #expect(
            !(value.withheld ?? "").isEmpty,
            "\(value.key) withheld its bytes without saying why"
        )
        // The capture withholds by type. Prove the shipping decoder would have
        // refused that type anyway, so the fixture hides nothing the product
        // could have rendered. The probe is zero bytes at the declared size,
        // clamped to the SMC wire width so the type is what fails, not length.
        let width = min(Int(value.dataSize), SMCReader.rawValueByteCapacity)
        let probe = SMCRawValue(
            key: value.key,
            dataType: value.dataType,
            dataSize: value.dataSize,
            bytes: Data(repeating: 0, count: width)
        )
        #expect(
            RecordedHardware.isNotPublished(SMCReader.decodeNumeric(probe)),
            "\(value.key) type \(value.dataType) was withheld, but the decoder reads it"
        )
    }
    #expect(withheld == recorded.withheldByteCount)
    #expect(withheld == 405)
}

@Test func recordedSMCRefusalsCarryTheIOReturnThatCausedThem() throws {
    let recorded = try RecordedHardware.smc()
    for refusal in recorded.refusedKeys {
        #expect(
            refusal.reason.contains("IOReturn"),
            "\(refusal.key) was refused with no IOReturn to explain it"
        )
        #expect(refusal.reason.contains(refusal.key))
    }
}
