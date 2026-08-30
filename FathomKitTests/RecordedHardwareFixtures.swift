import Foundation
import Testing
@testable import FathomKit

// Until these fixtures landed, `FathomKitTests` held no recorded hardware
// bytes: every hardware test asserted behaviour, and no test had ever put a
// real AppleSMC or IOReport payload through the shipping decoder. A parser that
// misread a real log had nothing standing in its way, which is what
// RELEASE-GATES gate 2 exists to fix.
//
// These recordings came from a **MacBook Pro Mac15,9, Apple M3 Max**, not from
// the Mac mini M4 Pro that RELEASE-GATES names as the reference machine. They
// are real Apple-silicon bytes and they test the decoders; they are not the
// reference-machine comparison that gate 2 also asks for. The manifest names
// the Mac, and `theRecordingNamesTheMacItCameFrom` pins it, so nobody mistakes
// one recording for the other.
//
// Regenerate with `fathom capture-fixtures FathomKitTests/Fixtures`.
//
// The replay tests themselves live in `RecordedSMCReplayTests.swift` and
// `RecordedIOReportReplayTests.swift`.

struct MissingFixture: Error, CustomStringConvertible {
    let name: String

    var description: String {
        "The recorded fixture \(name) is not in the test bundle"
    }
}

struct NotKnown: Error, CustomStringConvertible {
    let measurement: String

    var description: String {
        "Expected a known measurement, got \(measurement)"
    }
}

// MARK: - The capture file schemas

/// The shape `fathom capture-fixtures` writes. It is deliberately not
/// `SMCRawInventory`: the capture withholds the bytes of any key whose type the
/// shipping decoder cannot read, because these files go to a public repository,
/// and a withheld key keeps its name, type and size so what was withheld stays
/// visible. If the CLI ever changes this format, these tests fail to decode
/// rather than quietly testing something else.
struct RecordedSMCValue: Decodable {
    let key: String
    let dataType: String
    let dataSize: UInt32
    /// Base64 in the file; `nil` when the bytes were withheld.
    let bytes: Data?
    let withheld: String?
}

struct RecordedSMCInventory: Decodable {
    let readKeyCount: Int
    let refusedKeyCount: Int
    let withheldByteCount: Int
    let values: [RecordedSMCValue]
    let refusedKeys: [SMCRefusedKey]
}

struct RecordedManifestPayload: Decodable {
    let name: String
    let state: String
    let sha256: String?
    let byteCount: Int?
    let reason: String?
}

struct RecordedManifestMachine: Decodable {
    let hardwareModel: String
    let chipBrand: String
    let appleSilicon: String
}

struct RecordedManifest: Decodable {
    let ioReportSampleElapsedSeconds: Double
    let machine: RecordedManifestMachine
    let payloads: [RecordedManifestPayload]
}

// MARK: - Reading the recordings

enum RecordedHardware {
    static func data(_ name: String) throws -> Data {
        guard let directory = Bundle.module.url(
            forResource: "Fixtures",
            withExtension: nil
        ) else {
            throw MissingFixture(name: "Fixtures")
        }
        let url = directory.appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw MissingFixture(name: name)
        }
        return try Data(contentsOf: url)
    }

    static func manifest() throws -> RecordedManifest {
        try JSONDecoder().decode(
            RecordedManifest.self,
            from: data("capture-manifest.json")
        )
    }

    static func smc() throws -> RecordedSMCInventory {
        try JSONDecoder().decode(
            RecordedSMCInventory.self,
            from: data("smc-key-values.json")
        )
    }

    /// The recorded delta, decoded through the shipping decoder against the
    /// interval the capture recorded beside it.
    static func delta() throws -> IOReportDeltaSnapshot {
        try IOReportSampler.decodeDelta(
            data("ioreport-delta-sample.plist"),
            elapsedSeconds: manifest().ioReportSampleElapsedSeconds
        )
    }

    /// Unwraps a known measurement, or fails with what it actually held.
    /// Written once because every replay test needs it, and `Measurement`
    /// deliberately has no accessor that pretends the other two states cannot
    /// happen.
    static func known<Value>(
        _ measurement: FathomKit.Measurement<Value>
    ) throws -> (value: Value, source: DataSource) {
        guard case let .known(value, source) = measurement else {
            throw NotKnown(measurement: String(describing: measurement))
        }
        return (value, source)
    }

    static func isNotPublished<Value>(
        _ measurement: FathomKit.Measurement<Value>
    ) -> Bool {
        if case .notPublished = measurement { return true }
        return false
    }
}
