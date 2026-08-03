import CFathomStorage
import Foundation

public enum SnapshotManifestError: Error, Sendable, Equatable {
    case mountPointNotEmpty(path: String)
    case cannotMount(snapshot: String, errorNumber: Int32)
    case cannotUnmount(snapshot: String, errorNumber: Int32)
    case cannotTraverse(snapshot: String, reason: String)
    case cannotInspect(
        snapshot: String,
        path: String,
        reason: String
    )
    case extentOverflow(snapshot: String)
}

/// Builds an exact physical-reference manifest from read-only snapshot mounts.
///
/// Snapshot calls may be denied by macOS unless the process has Apple's
/// additional snapshot entitlement. Denial is an expected publication state,
/// not a reason to substitute an estimate.
public struct SnapshotManifestReader: Sendable {
    public init() {}

    /// Streams physical references as they are discovered. The callback is
    /// intentionally synchronous so callers can bind each extent directly to
    /// an on-disk index without retaining a volume-sized manifest in memory.
    public func streamPhysicalExtents(
        forVolumeAt volumeURL: URL,
        snapshots: [LocalSnapshot],
        mountPointURL: URL,
        onExtent: @escaping (
            _ snapshotName: String,
            _ extent: SnapshotPhysicalExtent
        ) throws -> Void
    ) throws -> Measurement<[String]> {
        guard !snapshots.isEmpty else {
            return .known([], source: .snapshotManifestDiff)
        }

        try prepareMountPoint(mountPointURL)
        var inspectedNames: [String] = []
        inspectedNames.reserveCapacity(snapshots.count)
        for snapshot in snapshots.sorted(by: { $0.name < $1.name }) {
            try Task.checkCancellation()
            try mount(
                snapshot: snapshot,
                volumeURL: volumeURL,
                mountPointURL: mountPointURL
            )

            do {
                try inspectMountedSnapshot(
                    snapshot: snapshot,
                    mountPointURL: mountPointURL,
                    onExtent: onExtent
                )
                try unmount(
                    snapshot: snapshot,
                    mountPointURL: mountPointURL
                )
                inspectedNames.append(snapshot.name)
            } catch {
                try? unmount(
                    snapshot: snapshot,
                    mountPointURL: mountPointURL
                )
                throw error
            }
        }
        return .known(inspectedNames, source: .snapshotManifestDiff)
    }

    public func manifests(
        forVolumeAt volumeURL: URL,
        snapshots: [LocalSnapshot],
        mountPointURL: URL
    ) throws -> Measurement<[SnapshotExtentManifest]> {
        guard !snapshots.isEmpty else {
            return .known([], source: .snapshotManifestDiff)
        }

        try prepareMountPoint(mountPointURL)

        var manifests: [SnapshotExtentManifest] = []
        manifests.reserveCapacity(snapshots.count)
        for snapshot in snapshots.sorted(by: { $0.name < $1.name }) {
            try Task.checkCancellation()
            try mount(
                snapshot: snapshot,
                volumeURL: volumeURL,
                mountPointURL: mountPointURL
            )

            do {
                let manifest = try inspectMountedSnapshot(
                    snapshot: snapshot,
                    mountPointURL: mountPointURL
                )
                try unmount(
                    snapshot: snapshot,
                    mountPointURL: mountPointURL
                )
                manifests.append(manifest)
            } catch {
                try? unmount(
                    snapshot: snapshot,
                    mountPointURL: mountPointURL
                )
                throw error
            }
        }
        return .known(manifests, source: .snapshotManifestDiff)
    }

    private func prepareMountPoint(_ mountPointURL: URL) throws {
        try FileManager.default.createDirectory(
            at: mountPointURL,
            withIntermediateDirectories: true
        )
        let existing = try FileManager.default.contentsOfDirectory(
            at: mountPointURL,
            includingPropertiesForKeys: nil
        )
        guard existing.isEmpty else {
            throw SnapshotManifestError.mountPointNotEmpty(
                path: mountPointURL.path
            )
        }
    }

    private func mount(
        snapshot: LocalSnapshot,
        volumeURL: URL,
        mountPointURL: URL
    ) throws {
        var errorNumber: Int32 = 0
        let result = volumeURL.withUnsafeFileSystemRepresentation {
            volumePath in
            mountPointURL.withUnsafeFileSystemRepresentation {
                mountPath in
                snapshot.name.withCString { snapshotName in
                    guard let volumePath, let mountPath else {
                        errorNumber = EINVAL
                        return Int32(-1)
                    }
                    return fathom_snapshot_mount(
                        volumePath,
                        mountPath,
                        snapshotName,
                        &errorNumber
                    )
                }
            }
        }
        guard result == 0 else {
            throw SnapshotManifestError.cannotMount(
                snapshot: snapshot.name,
                errorNumber: errorNumber
            )
        }
    }

    private func unmount(
        snapshot: LocalSnapshot,
        mountPointURL: URL
    ) throws {
        var errorNumber: Int32 = 0
        let result = mountPointURL.withUnsafeFileSystemRepresentation {
            mountPath in
            guard let mountPath else {
                errorNumber = EINVAL
                return Int32(-1)
            }
            return fathom_snapshot_unmount(
                mountPath,
                &errorNumber
            )
        }
        guard result == 0 else {
            throw SnapshotManifestError.cannotUnmount(
                snapshot: snapshot.name,
                errorNumber: errorNumber
            )
        }
    }

    private func inspectMountedSnapshot(
        snapshot: LocalSnapshot,
        mountPointURL: URL
    ) throws -> SnapshotExtentManifest {
        var extentsByDevice: [UInt64: [SnapshotPhysicalExtent]] = [:]
        let summary: StorageScanSummary
        do {
            summary = try StorageScanner().walk(at: mountPointURL) { entry in
                try Task.checkCancellation()
                guard entry.kind == .regularFile else {
                    return
                }
                let map: FileExtentMap
                do {
                    map = try FileExtentReader().inspect(entry)
                } catch {
                    throw SnapshotManifestError.cannotInspect(
                        snapshot: snapshot.name,
                        path: entry.path,
                        reason: String(describing: error)
                    )
                }
                guard
                    case let .known(physicalExtents, _) =
                        map.physicalExtents
                else {
                    throw SnapshotManifestError.cannotInspect(
                        snapshot: snapshot.name,
                        path: entry.path,
                        reason: "macOS did not publish physical extents"
                    )
                }
                for extent in physicalExtents where extent.length > 0 {
                    extentsByDevice[
                        entry.identity.device,
                        default: []
                    ].append(
                        SnapshotPhysicalExtent(
                            device: entry.identity.device,
                            deviceOffset: extent.deviceOffset,
                            length: extent.length
                        )
                    )
                }
            }
        } catch let error as SnapshotManifestError {
            throw error
        } catch {
            throw SnapshotManifestError.cannotTraverse(
                snapshot: snapshot.name,
                reason: String(describing: error)
            )
        }
        guard summary.issues.isEmpty else {
            throw SnapshotManifestError.cannotTraverse(
                snapshot: snapshot.name,
                reason: "\(summary.issues.count) snapshot entries could not be read"
            )
        }

        return SnapshotExtentManifest(
            snapshotName: snapshot.name,
            physicalExtents: try mergedSnapshotExtents(
                extentsByDevice,
                snapshotName: snapshot.name
            )
        )
    }

    private func inspectMountedSnapshot(
        snapshot: LocalSnapshot,
        mountPointURL: URL,
        onExtent: @escaping (
            _ snapshotName: String,
            _ extent: SnapshotPhysicalExtent
        ) throws -> Void
    ) throws {
        let summary: StorageScanSummary
        do {
            summary = try StorageScanner().walk(at: mountPointURL) { entry in
                try Task.checkCancellation()
                guard entry.kind == .regularFile else {
                    return
                }
                let map: FileExtentMap
                do {
                    map = try FileExtentReader().inspect(entry)
                } catch {
                    throw SnapshotManifestError.cannotInspect(
                        snapshot: snapshot.name,
                        path: entry.path,
                        reason: String(describing: error)
                    )
                }
                guard case let .known(physicalExtents, _) = map.physicalExtents else {
                    throw SnapshotManifestError.cannotInspect(
                        snapshot: snapshot.name,
                        path: entry.path,
                        reason: "macOS did not publish physical extents"
                    )
                }
                for extent in physicalExtents where extent.length > 0 {
                    try onExtent(
                        snapshot.name,
                        SnapshotPhysicalExtent(
                            device: entry.identity.device,
                            deviceOffset: extent.deviceOffset,
                            length: extent.length
                        )
                    )
                }
            }
        } catch let error as SnapshotManifestError {
            throw error
        } catch {
            throw SnapshotManifestError.cannotTraverse(
                snapshot: snapshot.name,
                reason: String(describing: error)
            )
        }
        guard summary.issues.isEmpty else {
            throw SnapshotManifestError.cannotTraverse(
                snapshot: snapshot.name,
                reason: "\(summary.issues.count) snapshot entries could not be read"
            )
        }
    }
}

func mergedSnapshotExtents(
    _ extentsByDevice: [UInt64: [SnapshotPhysicalExtent]],
    snapshotName: String
) throws -> [SnapshotPhysicalExtent] {
    var result: [SnapshotPhysicalExtent] = []
    for (device, extents) in extentsByDevice {
        let sorted = try extents.map { extent -> (UInt64, UInt64) in
            let (end, overflow) = extent.deviceOffset
                .addingReportingOverflow(extent.length)
            guard !overflow else {
                throw SnapshotManifestError.extentOverflow(
                    snapshot: snapshotName
                )
            }
            return (extent.deviceOffset, end)
        }
        .sorted {
            if $0.0 == $1.0 {
                return $0.1 < $1.1
            }
            return $0.0 < $1.0
        }

        guard var active = sorted.first else {
            continue
        }
        for extent in sorted.dropFirst() {
            if extent.0 <= active.1 {
                active.1 = max(active.1, extent.1)
            } else {
                result.append(
                    SnapshotPhysicalExtent(
                        device: device,
                        deviceOffset: active.0,
                        length: active.1 - active.0
                    )
                )
                active = extent
            }
        }
        result.append(
            SnapshotPhysicalExtent(
                device: device,
                deviceOffset: active.0,
                length: active.1 - active.0
            )
        )
    }
    return result.sorted {
        if $0.device == $1.device {
            return $0.deviceOffset < $1.deviceOffset
        }
        return $0.device < $1.device
    }
}
