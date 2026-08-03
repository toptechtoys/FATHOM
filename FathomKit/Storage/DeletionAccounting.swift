public struct SnapshotPhysicalExtent: Sendable, Equatable {
    public let device: UInt64
    public let deviceOffset: UInt64
    public let length: UInt64

    public init(
        device: UInt64,
        deviceOffset: UInt64,
        length: UInt64
    ) {
        self.device = device
        self.deviceOffset = deviceOffset
        self.length = length
    }
}

public struct SnapshotExtentManifest: Sendable, Equatable {
    public let snapshotName: String
    public let physicalExtents: [SnapshotPhysicalExtent]

    public init(
        snapshotName: String,
        physicalExtents: [SnapshotPhysicalExtent]
    ) {
        self.snapshotName = snapshotName
        self.physicalExtents = physicalExtents
    }
}

public struct DeletionAccountingContext: Sendable, Equatable {
    public let scanScope: ScanScope
    public let snapshotInventory: Measurement<[LocalSnapshot]>
    public let snapshotManifests: Measurement<[SnapshotExtentManifest]>
    public let openFileIdentities: Measurement<Set<FileIdentity>>

    public init(
        scanScope: ScanScope,
        snapshotInventory: Measurement<[LocalSnapshot]>,
        snapshotManifests: Measurement<[SnapshotExtentManifest]> =
            .notPublished(
                reason: "Snapshot manifests have not been diffed"
            ),
        openFileIdentities: Measurement<Set<FileIdentity>>
    ) {
        self.scanScope = scanScope
        self.snapshotInventory = snapshotInventory
        self.snapshotManifests = snapshotManifests
        self.openFileIdentities = openFileIdentities
    }
}

public struct DeletionEstimate: Sendable, Equatable {
    public let sizeOnDisk: Measurement<UInt64>
    public let freedIfDeleted: Measurement<UInt64>

    public init(
        sizeOnDisk: Measurement<UInt64>,
        freedIfDeleted: Measurement<UInt64>
    ) {
        self.sizeOnDisk = sizeOnDisk
        self.freedIfDeleted = freedIfDeleted
    }
}

/// Accounts physical ranges by their complete set of live file references.
public struct DeletionAccountant: Sendable {
    public init() {}

    public func estimate(
        deletingPaths: Set<String>,
        from files: [InspectedFile],
        context: DeletionAccountingContext
    ) -> DeletionEstimate {
        let indicesByPath = Dictionary(
            uniqueKeysWithValues: files.enumerated().map {
                ($0.element.entry.path, $0.offset)
            }
        )
        guard deletingPaths.allSatisfy({ indicesByPath[$0] != nil }) else {
            let reason = "The deletion set contains a path absent from the scan"
            return DeletionEstimate(
                sizeOnDisk: .notPublished(reason: reason),
                freedIfDeleted: .notPublished(reason: reason)
            )
        }

        var eventsByDevice: [UInt64: [ReferenceEvent]] = [:]
        for (ownerIndex, file) in files.enumerated() {
            guard case let .known(extents, _) = file.extents.physicalExtents
            else {
                let reason = "At least one file has no physical extent map"
                return DeletionEstimate(
                    sizeOnDisk: .notPublished(reason: reason),
                    freedIfDeleted: .notPublished(reason: reason)
                )
            }
            for extent in extents where extent.length > 0 {
                let (end, overflow) = extent.deviceOffset
                    .addingReportingOverflow(extent.length)
                guard !overflow else {
                    let reason = "A physical extent address overflowed"
                    return DeletionEstimate(
                        sizeOnDisk: .notPublished(reason: reason),
                        freedIfDeleted: .notPublished(reason: reason)
                    )
                }
                eventsByDevice[
                    file.entry.identity.device,
                    default: []
                ].append(
                    ReferenceEvent(
                        position: extent.deviceOffset,
                        owner: .file(ownerIndex),
                        delta: 1
                    )
                )
                eventsByDevice[
                    file.entry.identity.device,
                    default: []
                ].append(
                    ReferenceEvent(
                        position: end,
                        owner: .file(ownerIndex),
                        delta: -1
                    )
                )
            }
        }

        let selectedIndices = Set(
            deletingPaths.compactMap { indicesByPath[$0] }
        )
        let openIdentities: Set<FileIdentity>
        let snapshotExtents: [SnapshotPhysicalExtent]
        let canPublishFreeable: Bool
        let unavailableReason: String?
        switch publicationReadiness(context) {
        case let .ready(identities, extents):
            openIdentities = identities
            snapshotExtents = extents
            canPublishFreeable = true
            unavailableReason = nil
        case let .unavailable(reason):
            openIdentities = []
            snapshotExtents = []
            canPublishFreeable = false
            unavailableReason = reason
        }

        for extent in snapshotExtents where extent.length > 0 {
            let (end, overflow) = extent.deviceOffset
                .addingReportingOverflow(extent.length)
            guard !overflow else {
                let reason = "A snapshot physical extent address overflowed"
                return DeletionEstimate(
                    sizeOnDisk: .notPublished(reason: reason),
                    freedIfDeleted: .notPublished(reason: reason)
                )
            }
            eventsByDevice[extent.device, default: []].append(
                ReferenceEvent(
                    position: extent.deviceOffset,
                    owner: .snapshot,
                    delta: 1
                )
            )
            eventsByDevice[extent.device, default: []].append(
                ReferenceEvent(
                    position: end,
                    owner: .snapshot,
                    delta: -1
                )
            )
        }

        var onDiskBytes: UInt64 = 0
        var freeableBytes: UInt64 = 0
        for events in eventsByDevice.values {
            guard let totals = account(
                events: events,
                files: files,
                selectedIndices: selectedIndices,
                openIdentities: openIdentities
            ) else {
                let reason = "A physical reference total overflowed"
                return DeletionEstimate(
                    sizeOnDisk: .notPublished(reason: reason),
                    freedIfDeleted: .notPublished(reason: reason)
                )
            }
            let (nextOnDisk, onDiskOverflow) = onDiskBytes
                .addingReportingOverflow(totals.onDisk)
            let (nextFreeable, freeableOverflow) = freeableBytes
                .addingReportingOverflow(totals.freeable)
            guard !onDiskOverflow, !freeableOverflow else {
                let reason = "A physical reference total overflowed"
                return DeletionEstimate(
                    sizeOnDisk: .notPublished(reason: reason),
                    freedIfDeleted: .notPublished(reason: reason)
                )
            }
            onDiskBytes = nextOnDisk
            freeableBytes = nextFreeable
        }

        let freeable: Measurement<UInt64>
        if canPublishFreeable {
            freeable = .known(
                freeableBytes,
                source: .physicalReferenceAccounting
            )
        } else {
            freeable = .notPublished(
                reason: unavailableReason ??
                    "Deletion references are not fully attributable"
            )
        }
        return DeletionEstimate(
            sizeOnDisk: .known(
                onDiskBytes,
                source: .physicalReferenceAccounting
            ),
            freedIfDeleted: freeable
        )
    }
}

private enum PublicationReadiness {
    case ready(
        openIdentities: Set<FileIdentity>,
        snapshotExtents: [SnapshotPhysicalExtent]
    )
    case unavailable(reason: String)
}

private func publicationReadiness(
    _ context: DeletionAccountingContext
) -> PublicationReadiness {
    guard context.scanScope == .wholeVolume else {
        return .unavailable(
            reason: "A subtree scan cannot prove all physical references"
        )
    }

    let snapshotExtents: [SnapshotPhysicalExtent]
    switch context.snapshotInventory {
    case let .known(snapshots, _):
        if snapshots.isEmpty {
            snapshotExtents = []
            break
        }
        switch context.snapshotManifests {
        case let .known(manifests, _):
            let inventoryNames = Set(snapshots.map(\.name))
            let manifestNames = Set(manifests.map(\.snapshotName))
            guard
                manifests.count == manifestNames.count,
                inventoryNames == manifestNames
            else {
                return .unavailable(
                    reason: "Snapshot manifests do not match the current inventory"
                )
            }
            snapshotExtents = manifests.flatMap(\.physicalExtents)
        case let .notPublished(reason):
            return .unavailable(reason: reason)
        case .notAttributable:
            return .unavailable(
                reason: "Snapshot references are not fully attributable"
            )
        }
    case let .notPublished(reason):
        return .unavailable(reason: reason)
    case .notAttributable:
        return .unavailable(
            reason: "Snapshot references are not fully attributable"
        )
    }

    switch context.openFileIdentities {
    case let .known(identities, _):
        return .ready(
            openIdentities: identities,
            snapshotExtents: snapshotExtents
        )
    case let .notPublished(reason):
        return .unavailable(reason: reason)
    case .notAttributable:
        return .unavailable(
            reason: "Open-file references are not fully attributable"
        )
    }
}

private struct ReferenceEvent {
    let position: UInt64
    let owner: ReferenceOwner
    let delta: Int
}

private enum ReferenceOwner: Hashable {
    case file(Int)
    case snapshot

    var sortKey: Int {
        switch self {
        case let .file(index):
            return index
        case .snapshot:
            return Int.max
        }
    }
}

private struct ReferenceTotals {
    let onDisk: UInt64
    let freeable: UInt64
}

private func account(
    events unsortedEvents: [ReferenceEvent],
    files: [InspectedFile],
    selectedIndices: Set<Int>,
    openIdentities: Set<FileIdentity>
) -> ReferenceTotals? {
    let events = unsortedEvents.sorted {
        if $0.position == $1.position {
            if $0.owner == $1.owner {
                return $0.delta < $1.delta
            }
            return $0.owner.sortKey < $1.owner.sortKey
        }
        return $0.position < $1.position
    }
    var activeCounts: [ReferenceOwner: Int] = [:]
    var onDiskBytes: UInt64 = 0
    var freeableBytes: UInt64 = 0
    var previousPosition = events.first?.position
    var cursor = 0

    while cursor < events.count {
        let position = events[cursor].position
        if
            let previousPosition,
            position > previousPosition,
            !activeCounts.isEmpty
        {
            let length = position - previousPosition
            let fileOwners = activeCounts.keys.compactMap {
                if case let .file(index) = $0 {
                    return index
                }
                return nil
            }
            if fileOwners.contains(where: { selectedIndices.contains($0) }) {
                let (next, overflow) = onDiskBytes.addingReportingOverflow(
                    length
                )
                guard !overflow else {
                    return nil
                }
                onDiskBytes = next
            }

            let everyOwnerSelected = !fileOwners.isEmpty &&
                fileOwners.allSatisfy {
                    selectedIndices.contains($0)
                }
            let heldBySnapshot = activeCounts[.snapshot] != nil
            let heldOpen = fileOwners.contains {
                openIdentities.contains(files[$0].entry.identity)
            }
            if everyOwnerSelected && !heldBySnapshot && !heldOpen {
                let (next, overflow) = freeableBytes
                    .addingReportingOverflow(length)
                guard !overflow else {
                    return nil
                }
                freeableBytes = next
            }
        }

        while cursor < events.count, events[cursor].position == position {
            let event = events[cursor]
            let nextCount = activeCounts[event.owner, default: 0] +
                event.delta
            if nextCount == 0 {
                activeCounts.removeValue(forKey: event.owner)
            } else {
                activeCounts[event.owner] = nextCount
            }
            cursor += 1
        }
        previousPosition = position
    }

    return ReferenceTotals(
        onDisk: onDiskBytes,
        freeable: freeableBytes
    )
}
