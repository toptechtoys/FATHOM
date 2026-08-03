import CFathomStorage
import Foundation

public enum FileExtentError: Error, Sendable, Equatable {
    case notARegularFile(path: String)
    case cannotInspect(path: String, errorNumber: Int32)
    case identityChanged(path: String)
}

/// Reads allocation metadata only. It never reads file contents.
public struct FileExtentReader: Sendable {
    public init() {}

    public func inspect(_ entry: StorageEntry) throws -> FileExtentMap {
        guard entry.kind == .regularFile else {
            throw FileExtentError.notARegularFile(path: entry.path)
        }

        if entry.isDataless {
            return FileExtentMap(
                dataExtents: .known([], source: .statDatalessFlag),
                physicalExtents: .known([], source: .statDatalessFlag),
                cloneMetadata: .notPublished(
                    reason: "Dataless files are not opened for clone metadata"
                ),
                allocationBlockSize: .notPublished(
                    reason: "Dataless files are not opened for allocation metadata"
                )
            )
        }

        let state = ExtentState()
        let retainedState = Unmanaged.passRetained(state)
        defer { retainedState.release() }

        var isDataless: Int32 = 0
        var cloneID: UInt64 = 0
        var cloneReferenceCount: UInt32 = 0
        var cloneMetadataError: Int32 = 0
        var allocationBlockSize: UInt64 = 0
        var physicalMappingError: Int32 = 0
        var errorNumber: Int32 = 0
        let result = entry.path.withCString { path in
            fathom_file_extents(
                path,
                entry.identity.device,
                entry.identity.inode,
                extentCallback,
                retainedState.toOpaque(),
                &isDataless,
                &cloneID,
                &cloneReferenceCount,
                &cloneMetadataError,
                &allocationBlockSize,
                &physicalMappingError,
                &errorNumber
            )
        }

        if isDataless != 0 {
            return FileExtentMap(
                dataExtents: .known([], source: .statDatalessFlag),
                physicalExtents: .known([], source: .statDatalessFlag),
                cloneMetadata: .notPublished(
                    reason: "Dataless files are not opened for clone metadata"
                ),
                allocationBlockSize: .notPublished(
                    reason: "Dataless files are not opened for allocation metadata"
                )
            )
        }

        if result != 0 {
            if errorNumber == ESTALE {
                throw FileExtentError.identityChanged(path: entry.path)
            }
            if isUnsupported(errorNumber) {
                let reason = "The filesystem does not publish file extents"
                return FileExtentMap(
                    dataExtents: .notPublished(reason: reason),
                    physicalExtents: .notPublished(reason: reason),
                    cloneMetadata: .notPublished(reason: reason),
                    allocationBlockSize: .notPublished(reason: reason)
                )
            }
            throw FileExtentError.cannotInspect(
                path: entry.path,
                errorNumber: errorNumber
            )
        }

        let physicalExtents: Measurement<[PhysicalFileExtent]>
        if physicalMappingError == 0 {
            physicalExtents = reconciledPhysicalExtents(
                state.physicalExtents,
                allocationBlockSize: allocationBlockSize,
                expectedAllocatedSize: entry.sizeOnDisk
            )
        } else {
            physicalExtents = .notPublished(
                reason: "The filesystem does not publish physical extent addresses"
            )
        }

        let cloneMetadata: Measurement<CloneMetadata>
        if cloneMetadataError == 0 {
            cloneMetadata = .known(
                CloneMetadata(
                    identifier: cloneID,
                    referenceCount: cloneReferenceCount
                ),
                source: .getattrlistCloneIdentity
            )
        } else {
            cloneMetadata = .notPublished(
                reason: "The filesystem does not publish clone identity"
            )
        }

        return FileExtentMap(
            dataExtents: .known(
                state.dataExtents,
                source: .seekDataAndHole
            ),
            physicalExtents: physicalExtents,
            cloneMetadata: cloneMetadata,
            allocationBlockSize: .known(
                allocationBlockSize,
                source: .statfsAllocationBlockSize
            )
        )
    }
}

private final class ExtentState {
    var dataExtents: [LogicalFileExtent] = []
    var physicalExtents: [PhysicalFileExtent] = []
}

private let extentCallback: @convention(c) (
    UnsafePointer<FathomExtent>?,
    UnsafeMutableRawPointer?
) -> Int32 = { rawExtent, context in
    guard let rawExtent, let context else {
        return 1
    }

    let state = Unmanaged<ExtentState>.fromOpaque(context).takeUnretainedValue()
    let extent = rawExtent.pointee
    switch extent.kind {
    case FATHOM_EXTENT_DATA:
        state.dataExtents.append(
            LogicalFileExtent(
                offset: extent.logical_offset,
                length: extent.length
            )
        )
    case FATHOM_EXTENT_PHYSICAL:
        state.physicalExtents.append(
            PhysicalFileExtent(
                logicalOffset: extent.logical_offset,
                deviceOffset: extent.device_offset,
                length: extent.length
            )
        )
    default:
        return 1
    }
    return 0
}

private func isUnsupported(_ errorNumber: Int32) -> Bool {
    errorNumber == EINVAL ||
        errorNumber == ENOTSUP ||
        errorNumber == ENOSYS
}

private func reconciledPhysicalExtents(
    _ rawExtents: [PhysicalFileExtent],
    allocationBlockSize: UInt64,
    expectedAllocatedSize: Measurement<UInt64>
) -> Measurement<[PhysicalFileExtent]> {
    guard
        allocationBlockSize > 0,
        case let .known(expectedBytes, _) = expectedAllocatedSize
    else {
        return .notPublished(
            reason: "Allocation block metadata is unavailable"
        )
    }

    var normalized: [PhysicalFileExtent] = []
    normalized.reserveCapacity(rawExtents.count)
    for extent in rawExtents {
        let blockStart = extent.deviceOffset -
            (extent.deviceOffset % allocationBlockSize)
        let (unroundedEnd, overflow) = extent.deviceOffset
            .addingReportingOverflow(extent.length)
        guard !overflow else {
            return .notPublished(
                reason: "A physical extent address overflowed"
            )
        }
        let remainder = unroundedEnd % allocationBlockSize
        let padding = remainder == 0
            ? 0
            : allocationBlockSize - remainder
        let (blockEnd, endOverflow) = unroundedEnd
            .addingReportingOverflow(padding)
        guard !endOverflow else {
            return .notPublished(
                reason: "A physical extent address overflowed"
            )
        }
        normalized.append(
            PhysicalFileExtent(
                logicalOffset: extent.logicalOffset,
                deviceOffset: blockStart,
                length: blockEnd - blockStart
            )
        )
    }

    normalized.sort {
        if $0.deviceOffset == $1.deviceOffset {
            return $0.length < $1.length
        }
        return $0.deviceOffset < $1.deviceOffset
    }
    var merged: [PhysicalFileExtent] = []
    for extent in normalized {
        guard let last = merged.last else {
            merged.append(extent)
            continue
        }
        let lastEnd = last.deviceOffset + last.length
        let extentEnd = extent.deviceOffset + extent.length
        if extent.deviceOffset <= lastEnd {
            merged[merged.count - 1] = PhysicalFileExtent(
                logicalOffset: last.logicalOffset,
                deviceOffset: last.deviceOffset,
                length: max(lastEnd, extentEnd) - last.deviceOffset
            )
        } else {
            merged.append(extent)
        }
    }

    var explainedBytes: UInt64 = 0
    for extent in merged {
        let (next, overflow) = explainedBytes.addingReportingOverflow(
            extent.length
        )
        guard !overflow else {
            return .notPublished(
                reason: "The normalized physical extent total overflowed"
            )
        }
        explainedBytes = next
    }
    guard explainedBytes == expectedBytes else {
        return .notAttributable(
            measured: rawExtents,
            explained: merged
        )
    }
    return .known(merged, source: .fcntlPhysicalExtents)
}
