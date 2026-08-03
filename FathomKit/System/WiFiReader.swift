import CoreWLAN
import Foundation

public struct WiFiSnapshot: Sendable, Equatable {
    public let interfaceName: Measurement<String>
    public let ssid: Measurement<String>
    public let rssi: Measurement<Int>

    public init(
        interfaceName: Measurement<String>,
        ssid: Measurement<String>,
        rssi: Measurement<Int>
    ) {
        self.interfaceName = interfaceName
        self.ssid = ssid
        self.rssi = rssi
    }
}

public struct WiFiReader: Sendable {
    public init() {}

    public func read() -> WiFiSnapshot {
        guard let interface = CWWiFiClient.shared().interface() else {
            return Self.notPublished(
                reason: "CoreWLAN did not publish a Wi-Fi interface"
            )
        }
        let interfaceMeasurement: Measurement<String>
        if let name = interface.interfaceName, !name.isEmpty {
            interfaceMeasurement = .known(
                name,
                source: .coreWLANAssociationState
            )
        } else {
            interfaceMeasurement = .notPublished(
                reason: "CoreWLAN did not publish the interface name"
            )
        }
        let ssid: Measurement<String>
        if let value = interface.ssid(), !value.isEmpty {
            ssid = .known(value, source: .coreWLANAssociationState)
        } else {
            ssid = .notPublished(
                reason: "Wi-Fi is not associated or Location Services did not publish the SSID"
            )
        }
        let rawRSSI = interface.rssiValue()
        let rssi: Measurement<Int> = rawRSSI < 0
            ? .known(rawRSSI, source: .coreWLANAssociationState)
            : .notPublished(
                reason: "CoreWLAN did not publish an associated RSSI"
            )
        return WiFiSnapshot(
            interfaceName: interfaceMeasurement,
            ssid: ssid,
            rssi: rssi
        )
    }

    private static func notPublished(reason: String) -> WiFiSnapshot {
        WiFiSnapshot(
            interfaceName: .notPublished(reason: reason),
            ssid: .notPublished(reason: reason),
            rssi: .notPublished(reason: reason)
        )
    }
}
