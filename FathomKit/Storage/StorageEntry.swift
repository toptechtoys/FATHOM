public struct FileIdentity: Hashable, Sendable {
    public let device: UInt64
    public let inode: UInt64

    public init(device: UInt64, inode: UInt64) {
        self.device = device
        self.inode = inode
    }
}

public enum StorageEntryKind: Sendable, Equatable {
    case regularFile
    case directory
    case symbolicLink
    case other
}

public struct FileTimestamp: Sendable, Equatable {
    public let secondsSinceEpoch: Int64
    public let nanoseconds: Int32

    public init(secondsSinceEpoch: Int64, nanoseconds: Int32) {
        self.secondsSinceEpoch = secondsSinceEpoch
        self.nanoseconds = nanoseconds
    }
}

public struct StorageTraversalLocation: Sendable, Equatable {
    public let name: String
    public let depth: UInt64
    public let parentIdentity: FileIdentity?

    public init(
        name: String,
        depth: UInt64,
        parentIdentity: FileIdentity?
    ) {
        self.name = name
        self.depth = depth
        self.parentIdentity = parentIdentity
    }
}

/// Metadata gathered without opening or reading file contents.
public struct StorageEntry: Sendable, Equatable {
    public let path: String
    public let kind: StorageEntryKind
    public let identity: FileIdentity
    public let hardLinkCount: UInt64
    public let isDataless: Bool
    public let logicalSize: Measurement<UInt64>
    public let sizeOnDisk: Measurement<UInt64>
    public let modificationTime: Measurement<FileTimestamp>
    public let freedIfDeleted: Measurement<UInt64>
    public let traversalLocation: StorageTraversalLocation?

    public init(
        path: String,
        kind: StorageEntryKind,
        identity: FileIdentity,
        hardLinkCount: UInt64,
        isDataless: Bool,
        logicalSize: Measurement<UInt64>,
        sizeOnDisk: Measurement<UInt64>,
        modificationTime: Measurement<FileTimestamp>,
        freedIfDeleted: Measurement<UInt64>,
        traversalLocation: StorageTraversalLocation? = nil
    ) {
        self.path = path
        self.kind = kind
        self.identity = identity
        self.hardLinkCount = hardLinkCount
        self.isDataless = isDataless
        self.logicalSize = logicalSize
        self.sizeOnDisk = sizeOnDisk
        self.modificationTime = modificationTime
        self.freedIfDeleted = freedIfDeleted
        self.traversalLocation = traversalLocation
    }
}
