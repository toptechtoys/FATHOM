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

public struct SMCReader: Sendable {
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
