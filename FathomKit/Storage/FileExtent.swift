public struct LogicalFileExtent: Sendable, Equatable {
    public let offset: UInt64
    public let length: UInt64

    public init(offset: UInt64, length: UInt64) {
        self.offset = offset
        self.length = length
    }
}

/// A contiguous file range and its corresponding byte offset on the device.
///
/// Physical offsets are identities used for clone-family accounting. They are
/// not presented as storage capacity or freeable-byte measurements.
public struct PhysicalFileExtent: Sendable, Equatable {
    public let logicalOffset: UInt64
    public let deviceOffset: UInt64
    public let length: UInt64

    public init(
        logicalOffset: UInt64,
        deviceOffset: UInt64,
        length: UInt64
    ) {
        self.logicalOffset = logicalOffset
        self.deviceOffset = deviceOffset
        self.length = length
    }
}

public struct CloneMetadata: Sendable, Equatable {
    public let identifier: UInt64
    public let referenceCount: UInt32

    public init(identifier: UInt64, referenceCount: UInt32) {
        self.identifier = identifier
        self.referenceCount = referenceCount
    }
}

public struct FileExtentMap: Sendable, Equatable {
    public let dataExtents: Measurement<[LogicalFileExtent]>
    public let physicalExtents: Measurement<[PhysicalFileExtent]>
    public let cloneMetadata: Measurement<CloneMetadata>
    public let allocationBlockSize: Measurement<UInt64>

    public init(
        dataExtents: Measurement<[LogicalFileExtent]>,
        physicalExtents: Measurement<[PhysicalFileExtent]>,
        cloneMetadata: Measurement<CloneMetadata>,
        allocationBlockSize: Measurement<UInt64>
    ) {
        self.dataExtents = dataExtents
        self.physicalExtents = physicalExtents
        self.cloneMetadata = cloneMetadata
        self.allocationBlockSize = allocationBlockSize
    }
}
