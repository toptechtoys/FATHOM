import Foundation
import IOBluetooth

public struct BluetoothDeviceSnapshot: Sendable, Equatable, Identifiable {
    public let name: Measurement<String>
    public let address: String
    public let connected: Measurement<Bool>
    public let batteryPercent: Measurement<Int>

    public var id: String { address }

    public init(
        name: Measurement<String>,
        address: String,
        connected: Measurement<Bool>,
        batteryPercent: Measurement<Int>
    ) {
        self.name = name
        self.address = address
        self.connected = connected
        self.batteryPercent = batteryPercent
    }
}

public struct BluetoothSnapshot: Sendable, Equatable {
    public let devices: Measurement<[BluetoothDeviceSnapshot]>

    public init(devices: Measurement<[BluetoothDeviceSnapshot]>) {
        self.devices = devices
    }
}

/// Paired devices, as IOBluetooth publishes them.
///
/// **Deliberately not `@MainActor`, and it must stay that way.**
/// `+[IOBluetoothDevice pairedDevices]` builds the CoreBluetooth coordinator
/// on first use, and that call can block for an unbounded time — it did, on
/// the first machine that ever ran this app: opening the Bluetooth section
/// froze the whole window, the 1 Hz loop stopped in every section, and forty
/// seconds later the main thread was still parked in
/// `-[IOBluetoothCoreBluetoothCoordinator init]` at 0% CPU.
///
/// It was waiting on the TCC consent prompt, which arrived minutes later and
/// on the other display. That is the ordinary case, not an exotic one: the
/// first paired-device request on any Mac raises that prompt, and the answer
/// arrives whenever the person gets to it. A screen may not be at the mercy of
/// a hardware read, and this one was at the mercy of a dialog nobody had seen.
///
/// `MemoryReader` and `GPUReader` are already taken through `Task.detached` on
/// the same sampling loop. This is the one that was not.
public struct BluetoothReader {
    /// macOS terminates a process that asks for Bluetooth access without this
    /// string in its bundle, and enumerating paired devices issues that request.
    static let usageDescriptionKey = "NSBluetoothAlwaysUsageDescription"

    public init() {}

    /// True when the host bundle declares the usage string TCC requires before
    /// a paired-device request may be made.
    static var hostDeclaresBluetoothUsage: Bool {
        guard let description = Bundle.main.object(
            forInfoDictionaryKey: usageDescriptionKey
        ) as? String else {
            return false
        }
        return !description.isEmpty
    }

    public func read() -> BluetoothSnapshot {
        // Ask only once the declaration is in place. A host without it names the
        // gap instead of being killed by TCC mid-read.
        guard Self.hostDeclaresBluetoothUsage else {
            return BluetoothSnapshot(
                devices: .notPublished(
                    reason: """
                        The host bundle does not declare \
                        \(Self.usageDescriptionKey), so macOS does not permit \
                        paired-device enumeration
                        """
                )
            )
        }
        guard let devices = IOBluetoothDevice.pairedDevices()
            as? [IOBluetoothDevice] else {
            return BluetoothSnapshot(
                devices: .notPublished(
                    reason: "IOBluetooth did not publish paired devices"
                )
            )
        }
        return BluetoothSnapshot(
            devices: .known(
                devices.map(Self.snapshot),
                source: .ioBluetoothPairedDevices
            )
        )
    }

    private static func snapshot(
        _ device: IOBluetoothDevice
    ) -> BluetoothDeviceSnapshot {
        let address = device.addressString ?? "address not published"
        let name: Measurement<String>
        if let publishedName = device.nameOrAddress, !publishedName.isEmpty {
            name = .known(publishedName, source: .ioBluetoothPairedDevices)
        } else {
            name = .notPublished(reason: "The paired device has no name")
        }
        return BluetoothDeviceSnapshot(
            name: name,
            address: address,
            connected: .known(
                device.isConnected(),
                source: .ioBluetoothConnectionStatus
            ),
            batteryPercent: battery(device)
        )
    }

    private static func battery(
        _ device: IOBluetoothDevice
    ) -> Measurement<Int> {
        let object = device as NSObject
        for key in ["batteryPercent", "headsetBatteryPercent", "BatteryPercent"] {
            guard object.responds(to: NSSelectorFromString(key)) else {
                continue
            }
            if let number = object.value(forKey: key) as? NSNumber {
                let value = number.intValue
                guard (0...100).contains(value) else {
                    return .notPublished(
                        reason: "The device published an invalid battery percentage"
                    )
                }
                return .known(
                    value,
                    source: .ioBluetoothBatteryPercent
                )
            }
        }
        return .notPublished(reason: "This device does not report battery level")
    }
}
