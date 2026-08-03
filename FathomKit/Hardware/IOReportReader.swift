import CFathomHardware
import Foundation

public struct IOReportChannel: Sendable, Equatable, Codable {
    public let group: String
    public let subgroup: String
    public let channel: String
    public let unit: String

    public init(
        group: String,
        subgroup: String,
        channel: String,
        unit: String
    ) {
        self.group = group
        self.subgroup = subgroup
        self.channel = channel
        self.unit = unit
    }
}

public struct IOReportReader: Sendable {
    public init() {}

    public func channelInventory() -> Measurement<[IOReportChannel]> {
        var pointer: UnsafeMutablePointer<UInt8>?
        var length: UInt64 = 0
        var errorCode: Int32 = 0
        guard fathom_ioreport_copy_channel_inventory(
            &pointer,
            &length,
            &errorCode
        ) == 0, let pointer else {
            return .notPublished(
                reason: "IOReport channel enumeration is unavailable (bridge error \(errorCode))"
            )
        }
        defer { fathom_hardware_free(pointer) }
        guard length <= UInt64(Int.max) else {
            return .notPublished(
                reason: "IOReport channel inventory exceeds the process range"
            )
        }
        let data = Data(bytes: pointer, count: Int(length))
        do {
            let channels = try PropertyListDecoder().decode(
                [IOReportChannel].self,
                from: data
            )
            return .known(
                channels,
                source: .ioReportChannelInventory
            )
        } catch {
            return .notPublished(
                reason: "IOReport returned an unreadable channel inventory: \(error)"
            )
        }
    }
}
