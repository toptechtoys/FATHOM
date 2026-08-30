import CFathomHardware
import Foundation

public struct TemperatureSensorReading:
    Sendable,
    Equatable,
    Identifiable
{
    public let name: String
    public let celsius: Measurement<Double>

    public var id: String { name }

    public init(name: String, celsius: Measurement<Double>) {
        self.name = name
        self.celsius = celsius
    }
}

public struct TemperatureSensorReader: Sendable {
    public init() {}

    public func read() -> Measurement<[TemperatureSensorReading]> {
        var pointer: UnsafeMutablePointer<UInt8>?
        var length: UInt64 = 0
        var errorCode: Int32 = 0
        guard fathom_iohid_copy_temperature_sensors(
            &pointer,
            &length,
            &errorCode
        ) == 0, let pointer else {
            return .notPublished(
                reason: "IOHID temperature sensors are unavailable (bridge error \(errorCode))"
            )
        }
        defer { fathom_hardware_free(pointer) }
        guard length <= UInt64(Int.max) else {
            return .notPublished(
                reason: "The temperature inventory exceeds the process range"
            )
        }
        let data = Data(bytes: pointer, count: Int(length))
        return Self.decodeSensors(data)
    }

    /// Decodes a live or recorded IOHID temperature payload.
    public static func decodeSensors(
        _ data: Data
    ) -> Measurement<[TemperatureSensorReading]> {
        do {
            let payloads = try PropertyListDecoder().decode(
                [TemperaturePayload].self,
                from: data
            )
            let readings = payloads.map {
                TemperatureSensorReading(
                    name: $0.name,
                    celsius: .known(
                        $0.celsius,
                        source: .ioHIDTemperatureEvent
                    )
                )
            }
            guard !readings.isEmpty else {
                return .notPublished(
                    reason: "This Mac published no IOHID temperature services"
                )
            }
            return .known(readings, source: .ioHIDTemperatureEvent)
        } catch {
            return .notPublished(
                reason: "IOHID returned an unreadable temperature payload: \(error)"
            )
        }
    }
}

private struct TemperaturePayload: Decodable {
    let name: String
    let celsius: Double
}
