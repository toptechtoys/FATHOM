import CFathomStorage
import Foundation

public struct StorageScanSummary: Sendable, Equatable {
    public let entryCount: UInt64
    public let issues: [StorageScanIssue]

    public init(entryCount: UInt64, issues: [StorageScanIssue]) {
        self.entryCount = entryCount
        self.issues = issues
    }
}

/// Streams filesystem metadata through `FTS(3)`.
///
/// Traversal is physical, so symbolic links are reported but never followed.
/// File contents are never opened, which prevents iCloud dataless files from
/// being materialized by a scan.
public struct StorageScanner: Sendable {
    public init() {}

    @discardableResult
    public func walk(
        at rootURL: URL,
        onEntry: @escaping (StorageEntry) throws -> Void
    ) throws -> StorageScanSummary {
        let state = WalkState(onEntry: onEntry)
        let retainedState = Unmanaged.passRetained(state)
        defer { retainedState.release() }

        var errorNumber: Int32 = 0
        let result = rootURL.withUnsafeFileSystemRepresentation { rootPath in
            guard let rootPath else {
                errorNumber = EINVAL
                return Int32(-1)
            }

            return fathom_fts_walk(
                rootPath,
                storageEntryCallback,
                retainedState.toOpaque(),
                &errorNumber
            )
        }

        if let thrownError = state.thrownError {
            throw thrownError
        }
        guard result == 0 else {
            throw StorageScanError.cannotStart(
                path: rootURL.path,
                errorNumber: errorNumber
            )
        }

        return StorageScanSummary(
            entryCount: state.entryCount,
            issues: state.issues
        )
    }
}

private final class WalkState {
    let onEntry: (StorageEntry) throws -> Void
    var entryCount: UInt64 = 0
    var issues: [StorageScanIssue] = []
    var thrownError: Error?

    init(onEntry: @escaping (StorageEntry) throws -> Void) {
        self.onEntry = onEntry
    }
}

private let storageEntryCallback: @convention(c) (
    UnsafePointer<FathomFTSEntry>?,
    UnsafeMutableRawPointer?
) -> Int32 = { rawEntry, context in
    guard let rawEntry, let context else {
        return 1
    }

    let state = Unmanaged<WalkState>.fromOpaque(context).takeUnretainedValue()
    let raw = rawEntry.pointee
    let path = String(cString: raw.path)
    let name: String
    if let rawName = raw.name {
        name = String(
            decoding: UnsafeBufferPointer(
                start: UnsafeRawPointer(rawName)
                    .assumingMemoryBound(to: UInt8.self),
                count: Int(raw.name_length)
            ),
            as: UTF8.self
        )
    } else {
        name = URL(fileURLWithPath: path).lastPathComponent
    }

    if raw.error_number != 0 {
        state.issues.append(
            StorageScanIssue(path: path, errorNumber: raw.error_number)
        )
        return 0
    }

    let isDataless = raw.is_dataless != 0
    let freeable: Measurement<UInt64>
    if isDataless {
        freeable = .known(0, source: .statDatalessFlag)
    } else {
        freeable = .notPublished(
            reason: "Clone extents and snapshot references have not been attributed"
        )
    }

    let entry = StorageEntry(
        path: path,
        kind: StorageEntryKind(rawValue: raw.kind),
        identity: FileIdentity(
            device: raw.device,
            inode: raw.inode
        ),
        hardLinkCount: raw.hard_link_count,
        isDataless: isDataless,
        logicalSize: .known(raw.logical_size, source: .statLogicalSize),
        sizeOnDisk: .known(raw.allocated_size, source: .statAllocatedBlocks),
        modificationTime: .known(
            FileTimestamp(
                secondsSinceEpoch: raw.modification_time_seconds,
                nanoseconds: raw.modification_time_nanoseconds
            ),
            source: .statModificationTime
        ),
        freedIfDeleted: freeable,
        traversalLocation: StorageTraversalLocation(
            name: name,
            depth: raw.level,
            parentIdentity: raw.has_parent != 0
                ? FileIdentity(
                    device: raw.parent_device,
                    inode: raw.parent_inode
                )
                : nil
        )
    )

    do {
        try state.onEntry(entry)
        state.entryCount += 1
        return 0
    } catch {
        state.thrownError = error
        return 1
    }
}

private extension StorageEntryKind {
    init(rawValue: FathomFTSEntryKind) {
        switch rawValue {
        case FATHOM_FTS_REGULAR:
            self = .regularFile
        case FATHOM_FTS_DIRECTORY:
            self = .directory
        case FATHOM_FTS_SYMBOLIC_LINK:
            self = .symbolicLink
        default:
            self = .other
        }
    }
}
