import CFathomHardware
import Darwin
import Foundation
import SystemConfiguration

public struct NetworkInterfaceMetrics: Sendable, Equatable, Identifiable {
    public let name: String
    public let receivedBytes: UInt64
    public let sentBytes: UInt64
    public let receivedBytesPerSecond: Measurement<Double>
    public let sentBytesPerSecond: Measurement<Double>

    public var id: String { name }

    public init(
        name: String,
        receivedBytes: UInt64,
        sentBytes: UInt64,
        receivedBytesPerSecond: Measurement<Double>,
        sentBytesPerSecond: Measurement<Double>
    ) {
        self.name = name
        self.receivedBytes = receivedBytes
        self.sentBytes = sentBytes
        self.receivedBytesPerSecond = receivedBytesPerSecond
        self.sentBytesPerSecond = sentBytesPerSecond
    }
}

public struct NetworkSnapshot: Sendable, Equatable {
    public let interfaces: Measurement<[NetworkInterfaceMetrics]>
    public let localAddresses: Measurement<[NetworkAddress]>
    public let configuration: NetworkConfigurationSnapshot

    public init(
        interfaces: Measurement<[NetworkInterfaceMetrics]>,
        localAddresses: Measurement<[NetworkAddress]>,
        configuration: NetworkConfigurationSnapshot
    ) {
        self.interfaces = interfaces
        self.localAddresses = localAddresses
        self.configuration = configuration
    }
}

public struct NetworkConfigurationSnapshot: Sendable, Equatable {
    public let primaryInterface: Measurement<String>
    public let router: Measurement<String>
    public let dnsServers: Measurement<[String]>

    public init(
        primaryInterface: Measurement<String>,
        router: Measurement<String>,
        dnsServers: Measurement<[String]>
    ) {
        self.primaryInterface = primaryInterface
        self.router = router
        self.dnsServers = dnsServers
    }
}

public struct NetworkAddress: Sendable, Equatable, Identifiable {
    public let interfaceName: String
    public let address: String
    public let family: Int

    public var id: String { "\(interfaceName)-\(family)-\(address)" }

    public init(interfaceName: String, address: String, family: Int) {
        self.interfaceName = interfaceName
        self.address = address
        self.family = family
    }
}

private struct RawNetworkInterface: Sendable, Equatable {
    let name: String
    let receivedBytes: UInt64
    let sentBytes: UInt64
    let flags: UInt32
}

public actor NetworkSampler {
    private var previous: (time: ContinuousClock.Instant, values: [String: RawNetworkInterface])?
    private let clock = ContinuousClock()
    private var cachedConfiguration: (
        time: ContinuousClock.Instant,
        value: NetworkConfigurationSnapshot
    )?

    public init() {}

    public func sample() -> NetworkSnapshot {
        let now = clock.now
        let configuration: NetworkConfigurationSnapshot
        if let cachedConfiguration,
           Self.seconds(cachedConfiguration.time.duration(to: now)) < 10 {
            configuration = cachedConfiguration.value
        } else {
            configuration = Self.readConfiguration()
            cachedConfiguration = (now, configuration)
        }
        let current: [RawNetworkInterface]
        do {
            current = try Self.readCounters()
        } catch {
            return NetworkSnapshot(
                interfaces: .notPublished(
                    reason: "Network interface counters unavailable: \(error)"
                ),
                localAddresses: Self.readAddresses(),
                configuration: configuration
            )
        }
        let currentMap = Dictionary(uniqueKeysWithValues: current.map {
            ($0.name, $0)
        })
        defer { previous = (now, currentMap) }
        let elapsed = previous.map {
            Double($0.time.duration(to: now).components.seconds) +
                Double($0.time.duration(to: now).components.attoseconds) / 1e18
        }
        let visible = current.filter {
            $0.flags & UInt32(IFF_UP) != 0 &&
                $0.flags & UInt32(IFF_LOOPBACK) == 0
        }
        let metrics = visible.map { item in
            let prior = previous?.values[item.name]
            return NetworkInterfaceMetrics(
                name: item.name,
                receivedBytes: item.receivedBytes,
                sentBytes: item.sentBytes,
                receivedBytesPerSecond: Self.rate(
                    previous: prior?.receivedBytes,
                    current: item.receivedBytes,
                    elapsed: elapsed
                ),
                sentBytesPerSecond: Self.rate(
                    previous: prior?.sentBytes,
                    current: item.sentBytes,
                    elapsed: elapsed
                )
            )
        }
        return NetworkSnapshot(
            interfaces: .known(
                metrics.sorted { $0.name < $1.name },
                source: .sysctlNetworkInterfaceList
            ),
            localAddresses: Self.readAddresses(),
            configuration: configuration
        )
    }

    static func rate(
        previous: UInt64?,
        current: UInt64,
        elapsed: Double?
    ) -> Measurement<Double> {
        guard let previous, let elapsed, elapsed > 0 else {
            return .notPublished(reason: "A second counter sample is required")
        }
        guard current >= previous else {
            return .notPublished(reason: "The interface counter reset")
        }
        return .known(
            Double(current - previous) / elapsed,
            source: .sysctlNetworkInterfaceList
        )
    }

    private static func readCounters() throws -> [RawNetworkInterface] {
        var raw = fathom_network_counters()
        var errorCode: Int32 = 0
        guard fathom_network_read_counters(&raw, &errorCode) == 0 else {
            throw CocoaError(.fileReadUnknown, userInfo: [
                NSDebugDescriptionErrorKey: "sysctl errno \(errorCode)"
            ])
        }
        let count = min(
            Int(raw.interface_count),
            Int(FATHOM_MAX_NETWORK_INTERFACES)
        )
        return withUnsafeBytes(of: &raw.interfaces) { bytes in
            let items = bytes.bindMemory(to: fathom_network_interface.self)
            return items.prefix(count).compactMap { item in
                var item = item
                let name = withUnsafeBytes(of: &item.name) { nameBytes in
                    String(
                        cString: nameBytes.bindMemory(to: CChar.self).baseAddress!
                    )
                }
                guard !name.isEmpty else { return nil }
                return RawNetworkInterface(
                    name: name,
                    receivedBytes: item.received_bytes,
                    sentBytes: item.sent_bytes,
                    flags: item.flags
                )
            }
        }
    }

    static func readAddresses() -> Measurement<[NetworkAddress]> {
        var raw = fathom_network_addresses()
        var errorCode: Int32 = 0
        guard fathom_network_read_addresses(&raw, &errorCode) == 0 else {
            return .notPublished(
                reason: "getifaddrs failed with errno \(errorCode)"
            )
        }
        let count = min(
            Int(raw.address_count),
            Int(FATHOM_MAX_NETWORK_ADDRESSES)
        )
        let addresses = withUnsafeBytes(of: &raw.addresses) { bytes in
            bytes.bindMemory(to: fathom_network_address.self)
                .prefix(count)
                .compactMap { value -> NetworkAddress? in
                    var value = value
                    let interfaceName = withUnsafeBytes(
                        of: &value.interface_name
                    ) {
                        String(cString: $0.bindMemory(to: CChar.self).baseAddress!)
                    }
                    let address = withUnsafeBytes(of: &value.address) {
                        String(cString: $0.bindMemory(to: CChar.self).baseAddress!)
                    }
                    guard !interfaceName.isEmpty, !address.isEmpty else {
                        return nil
                    }
                    return NetworkAddress(
                        interfaceName: interfaceName,
                        address: address,
                        family: Int(value.family)
                    )
                }
        }
        return .known(
            addresses.sorted {
                if $0.interfaceName != $1.interfaceName {
                    return $0.interfaceName < $1.interfaceName
                }
                if $0.family != $1.family {
                    return $0.family < $1.family
                }
                return $0.address < $1.address
            },
            source: .getifaddrsNetworkAddresses
        )
    }

    static func readConfiguration() -> NetworkConfigurationSnapshot {
        guard let store = SCDynamicStoreCreate(
            kCFAllocatorDefault,
            "FATHOM network state" as CFString,
            nil,
            nil
        ) else {
            let reason = "SCDynamicStore could not be created"
            return NetworkConfigurationSnapshot(
                primaryInterface: .notPublished(reason: reason),
                router: .notPublished(reason: reason),
                dnsServers: .notPublished(reason: reason)
            )
        }
        let ipv4 = SCDynamicStoreCopyValue(
            store,
            "State:/Network/Global/IPv4" as CFString
        ) as? [String: Any]
        let dns = SCDynamicStoreCopyValue(
            store,
            "State:/Network/Global/DNS" as CFString
        ) as? [String: Any]
        func string(
            _ key: CFString,
            in dictionary: [String: Any]?,
            label: String
        ) -> Measurement<String> {
            guard let value = dictionary?[key as String] as? String,
                  !value.isEmpty else {
                return .notPublished(
                    reason: "SCDynamicStore did not publish \(label)"
                )
            }
            return .known(value, source: .scDynamicStoreNetworkState)
        }
        let servers: Measurement<[String]>
        if let values = dns?[kSCPropNetDNSServerAddresses as String]
            as? [String], !values.isEmpty {
            servers = .known(
                values,
                source: .scDynamicStoreNetworkState
            )
        } else {
            servers = .notPublished(
                reason: "SCDynamicStore did not publish DNS servers"
            )
        }
        return NetworkConfigurationSnapshot(
            primaryInterface: string(
                kSCDynamicStorePropNetPrimaryInterface,
                in: ipv4,
                label: "a primary interface"
            ),
            router: string(
                kSCPropNetIPv4Router,
                in: ipv4,
                label: "an IPv4 router"
            ),
            dnsServers: servers
        )
    }

    private static func seconds(_ duration: Duration) -> Double {
        let components = duration.components
        return Double(components.seconds) +
            Double(components.attoseconds) / 1e18
    }
}
