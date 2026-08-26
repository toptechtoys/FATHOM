import CFathomHardware
import Foundation

public struct SMCReading: Sendable, Equatable, Identifiable {
    public let key: String
    public let value: Measurement<Double>

    public var id: String { key }

    public init(key: String, value: Measurement<Double>) {
        self.key = key
        self.value = value
    }
}

public struct SMCSnapshot: Sendable, Equatable {
    public let keyInventory: Measurement<[String]>
    public let fanSpeedsRPM: [SMCReading]
    public let totalSystemPowerWatts: Measurement<Double>

    public init(
        keyInventory: Measurement<[String]>,
        fanSpeedsRPM: [SMCReading],
        totalSystemPowerWatts: Measurement<Double>
    ) {
        self.keyInventory = keyInventory
        self.fanSpeedsRPM = fanSpeedsRPM
        self.totalSystemPowerWatts = totalSystemPowerWatts
    }
}

/// Remembers failed keys for this process session. AppleSMC reads are
/// synchronous hardware transactions, so absent or timing-out keys are not
/// probed again until the next launch.
public final class SMCProbeSession: @unchecked Sendable {
    private let lock = NSLock()
    private var failures: [String: Measurement<Double>] = [:]

    public init() {}

    public func measurement(
        for key: String,
        probe: () -> Measurement<Double>
    ) -> Measurement<Double> {
        lock.lock()
        if let failure = failures[key] {
            lock.unlock()
            return failure
        }
        lock.unlock()

        let result = probe()
        guard case .known = result else {
            lock.lock()
            failures[key] = result
            lock.unlock()
            return result
        }
        return result
    }

    public var blacklistedKeys: [String] {
        lock.lock()
        defer { lock.unlock() }
        return failures.keys.sorted()
    }
}

/// One SMC key as it came off the wire: the four-character code, the
/// four-character type AppleSMC declared for it, and the bytes themselves.
///
/// `readNumericKey` decodes to a `Double` and lets the bytes die, which is
/// correct for the UI and useless for a fixture — a decoder tested only against
/// values it produced itself proves nothing about how it reads a real SMC.
public struct SMCRawValue: Sendable, Equatable, Codable {
    public let key: String
    public let dataType: String
    public let dataSize: UInt32
    public let bytes: Data

    public init(
        key: String,
        dataType: String,
        dataSize: UInt32,
        bytes: Data
    ) {
        self.key = key
        self.dataType = dataType
        self.dataSize = dataSize
        self.bytes = bytes
    }
}

/// A key AppleSMC enumerated but would not read, kept with the IOReturn that
/// says so.
public struct SMCRefusedKey: Sendable, Equatable, Codable {
    public let key: String
    public let reason: String

    public init(key: String, reason: String) {
        self.key = key
        self.reason = reason
    }
}

/// Every enumerated key, split into the ones that answered and the ones that
/// did not. The two halves are never merged: the second is the measurement of
/// what this Mac will not publish.
public struct SMCRawInventory: Sendable, Equatable, Codable {
    public let values: [SMCRawValue]
    public let refusedKeys: [SMCRefusedKey]

    public init(values: [SMCRawValue], refusedKeys: [SMCRefusedKey]) {
        self.values = values
        self.refusedKeys = refusedKeys
    }
}

public struct SMCReader: Sendable {
    /// The fixed width of `fathom_smc_value.bytes`. The bridge refuses any key
    /// whose declared size exceeds it, so a raw value never carries more.
    static let rawValueByteCapacity = 32

    public init() {}

    public func readSnapshot() -> SMCSnapshot {
        readSnapshot(session: nil)
    }

    public func readSnapshot(session: SMCProbeSession?) -> SMCSnapshot {
        let inventory = readKeyInventory()
        return readSnapshot(keyInventory: inventory, session: session)
    }

    public func readSnapshot(
        keyInventory inventory: Measurement<[String]>,
        session: SMCProbeSession? = nil
    ) -> SMCSnapshot {
        guard case let .known(keys, _) = inventory else {
            let reason: String
            switch inventory {
            case let .notPublished(value):
                reason = value
            case .notAttributable:
                reason = "The SMC key inventory is not attributable"
            case .known:
                preconditionFailure("Handled by the guard")
            }
            return SMCSnapshot(
                keyInventory: inventory,
                fanSpeedsRPM: [],
                totalSystemPowerWatts: .notPublished(reason: reason)
            )
        }

        let fanKeys = keys.filter(Self.isActualFanSpeedKey).sorted()
        let fanReadings = fanKeys.map { key in
            SMCReading(
                key: key,
                value: session?.measurement(for: key) {
                    readNumericKey(key)
                } ?? readNumericKey(key)
            )
        }
        let power: Measurement<Double>
        if keys.contains("PSTR") {
            power = session?.measurement(for: "PSTR") {
                readNumericKey("PSTR")
            } ?? readNumericKey("PSTR")
        } else {
            power = .notPublished(
                reason: "This Mac's SMC does not publish PSTR"
            )
        }
        return SMCSnapshot(
            keyInventory: inventory,
            fanSpeedsRPM: fanReadings,
            totalSystemPowerWatts: power
        )
    }

    public func readKeyInventory() -> Measurement<[String]> {
        var pointer: UnsafeMutablePointer<UInt32>?
        var count: UInt32 = 0
        var errorCode: Int32 = 0
        guard fathom_smc_copy_keys(
            &pointer,
            &count,
            &errorCode
        ) == 0, let pointer else {
            return .notPublished(
                reason: "macOS did not publish a readable AppleSMC key inventory (IOReturn \(errorCode))"
            )
        }
        defer { fathom_hardware_free(pointer) }
        let keys = (0..<Int(count)).map {
            Self.string(forKey: pointer[$0])
        }
        return .known(keys, source: .appleSMCKeyInventory)
    }

    public func readNumericKey(
        _ key: String
    ) -> Measurement<Double> {
        guard let rawKey = Self.key(forString: key) else {
            return .notPublished(reason: "\(key) is not a four-byte SMC key")
        }
        var raw = fathom_smc_value()
        var errorCode: Int32 = 0
        guard fathom_smc_read_key(rawKey, &raw, &errorCode) == 0 else {
            return .notPublished(
                reason: "AppleSMC did not publish \(key) (IOReturn \(errorCode))"
            )
        }
        var decoded = 0.0
        guard fathom_smc_decode_numeric(&raw, &decoded) == 0 else {
            return .notPublished(
                reason: "AppleSMC key \(key) uses an unsupported data type"
            )
        }
        return .known(decoded, source: .appleSMCReadKey)
    }

    /// One key's wire bytes, undecoded.
    public func readRawKey(_ key: String) -> Measurement<SMCRawValue> {
        guard let rawKey = Self.key(forString: key) else {
            return .notPublished(reason: "\(key) is not a four-byte SMC key")
        }
        var raw = fathom_smc_value()
        var errorCode: Int32 = 0
        guard fathom_smc_read_key(rawKey, &raw, &errorCode) == 0 else {
            return .notPublished(
                reason: "AppleSMC did not publish \(key) (IOReturn \(errorCode))"
            )
        }
        let width = Int(min(raw.data_size, UInt32(Self.rawValueByteCapacity)))
        let bytes = withUnsafeBytes(of: raw.bytes) {
            Data($0.prefix(width))
        }
        return .known(
            SMCRawValue(
                key: key,
                dataType: Self.string(forKey: raw.data_type),
                dataSize: raw.data_size,
                bytes: bytes
            ),
            source: .appleSMCReadKey
        )
    }

    /// Reads every enumerated key's wire bytes, and records the ones that
    /// refused alongside the ones that answered.
    ///
    /// This is expensive in a way the 1 Hz loop must never be:
    /// `fathom_smc_read_key` opens and closes a fresh `AppleSMC` connection per
    /// key (Sources/CFathomHardware/FathomHardware.c:352-378), so a machine
    /// publishing a thousand keys pays a thousand synchronous IOKit
    /// transactions, and individual keys are known to stall. It belongs in the
    /// capture path only. Pass `progress` so a stall is visible at the key it
    /// stalled on rather than as a silent hang.
    ///
    /// A refused key is kept with its reason rather than dropped: gate 2 asks
    /// what the machine would not publish, and a shorter list with no
    /// explanation answers a different question.
    public func readRawInventory(
        progress: ((_ read: Int, _ total: Int, _ key: String) -> Void)? = nil
    ) -> Measurement<SMCRawInventory> {
        switch readKeyInventory() {
        case let .known(keys, _):
            var values: [SMCRawValue] = []
            var refusals: [SMCRefusedKey] = []
            values.reserveCapacity(keys.count)
            for (index, key) in keys.enumerated() {
                progress?(index, keys.count, key)
                switch readRawKey(key) {
                case let .known(value, _):
                    values.append(value)
                case let .notPublished(reason):
                    refusals.append(
                        SMCRefusedKey(key: key, reason: reason)
                    )
                case .notAttributable:
                    refusals.append(
                        SMCRefusedKey(
                            key: key,
                            reason: "AppleSMC key \(key) is not attributable"
                        )
                    )
                }
            }
            return .known(
                SMCRawInventory(values: values, refusedKeys: refusals),
                source: .appleSMCKeyInventory
            )
        case let .notPublished(reason):
            return .notPublished(reason: reason)
        case let .notAttributable(measured, explained):
            return .notAttributable(
                measured: SMCRawInventory(
                    values: [],
                    refusedKeys: measured.map {
                        SMCRefusedKey(
                            key: $0,
                            reason: "The key inventory is not attributable"
                        )
                    }
                ),
                explained: SMCRawInventory(
                    values: [],
                    refusedKeys: explained.map {
                        SMCRefusedKey(
                            key: $0,
                            reason: "The key inventory is not attributable"
                        )
                    }
                )
            )
        }
    }

    /// Replays a recorded value through the shipping numeric decoder.
    ///
    /// The wording matches `readNumericKey`'s so a fixture failure reads
    /// exactly like the live failure it stands in for.
    public static func decodeNumeric(
        _ value: SMCRawValue
    ) -> Measurement<Double> {
        guard let rawKey = key(forString: value.key) else {
            return .notPublished(
                reason: "\(value.key) is not a four-byte SMC key"
            )
        }
        guard let rawType = key(forString: value.dataType) else {
            return .notPublished(
                reason: "AppleSMC key \(value.key) uses an unsupported data type"
            )
        }
        guard value.bytes.count <= rawValueByteCapacity else {
            return .notPublished(
                reason: "AppleSMC key \(value.key) carries more bytes than the SMC wire format holds"
            )
        }
        var raw = fathom_smc_value()
        raw.key = rawKey
        raw.data_type = rawType
        raw.data_size = value.dataSize
        withUnsafeMutableBytes(of: &raw.bytes) { destination in
            value.bytes.copyBytes(
                to: destination.bindMemory(to: UInt8.self),
                count: value.bytes.count
            )
        }
        var decoded = 0.0
        guard fathom_smc_decode_numeric(&raw, &decoded) == 0 else {
            return .notPublished(
                reason: "AppleSMC key \(value.key) uses an unsupported data type"
            )
        }
        return .known(decoded, source: .appleSMCReadKey)
    }

    static func isActualFanSpeedKey(_ key: String) -> Bool {
        guard key.count == 4 else { return false }
        let characters = Array(key)
        return characters[0] == "F" &&
            characters[1].isNumber &&
            characters[2] == "A" &&
            characters[3] == "c"
    }

    static func key(forString value: String) -> UInt32? {
        let bytes = Array(value.utf8)
        guard bytes.count == 4 else { return nil }
        return bytes.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
    }

    static func string(forKey value: UInt32) -> String {
        let bytes = [
            UInt8((value >> 24) & 0xFF),
            UInt8((value >> 16) & 0xFF),
            UInt8((value >> 8) & 0xFF),
            UInt8(value & 0xFF),
        ]
        return String(decoding: bytes, as: UTF8.self)
    }
}
