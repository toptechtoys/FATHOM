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
        switch channelInventoryPayload() {
        case let .known(data, _):
            return Self.decodeChannelInventory(data)
        case let .notPublished(reason):
            return .notPublished(reason: reason)
        case .notAttributable:
            return .notPublished(
                reason: "The IOReport channel inventory is not attributable"
            )
        }
    }

    /// The serialized inventory before anything decodes it.
    ///
    /// The bridge already builds a binary property list and the reader used to
    /// decode and free it in the same breath, so the payload existed for
    /// microseconds and reached nobody. Gate 2 has to commit it.
    public func channelInventoryPayload() -> Measurement<Data> {
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
        return .known(
            Data(bytes: pointer, count: Int(length)),
            source: .ioReportChannelInventory
        )
    }

    /// Decodes a live or recorded inventory payload.
    public static func decodeChannelInventory(
        _ data: Data
    ) -> Measurement<[IOReportChannel]> {
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
