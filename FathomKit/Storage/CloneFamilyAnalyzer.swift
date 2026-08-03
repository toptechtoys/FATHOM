import Foundation

public enum ScanScope: Sendable, Equatable {
    case subtree
    case wholeVolume
}

public struct InspectedFile: Sendable, Equatable {
    public let entry: StorageEntry
    public let extents: FileExtentMap

    public init(entry: StorageEntry, extents: FileExtentMap) {
        self.entry = entry
        self.extents = extents
    }
}

public struct CloneFamily: Sendable, Equatable {
    public let memberPaths: [String]
    public let creditedAtPath: String
    public let sizeOnDisk: Measurement<UInt64>
    public let hasMemberOutsideScan: Measurement<Bool>
    public let freedIfDeletingTogether: Measurement<UInt64>

    public init(
        memberPaths: [String],
        creditedAtPath: String,
        sizeOnDisk: Measurement<UInt64>,
        hasMemberOutsideScan: Measurement<Bool>,
        freedIfDeletingTogether: Measurement<UInt64>
    ) {
        self.memberPaths = memberPaths
        self.creditedAtPath = creditedAtPath
        self.sizeOnDisk = sizeOnDisk
        self.hasMemberOutsideScan = hasMemberOutsideScan
        self.freedIfDeletingTogether = freedIfDeletingTogether
    }
}

/// Groups files connected by overlapping physical extents.
///
/// This produces accounting families and their lowest common ancestors. It
/// does not claim bytes are freeable while snapshot attribution is absent.
public struct CloneFamilyAnalyzer: Sendable {
    public init() {}

    public func analyze(
        _ files: [InspectedFile],
        scope: ScanScope
    ) -> Measurement<[CloneFamily]> {
        var mappedExtents: [[PhysicalFileExtent]] = []
        mappedExtents.reserveCapacity(files.count)

        for file in files {
            guard case let .known(extents, _) = file.extents.physicalExtents
            else {
                return .notPublished(
                    reason: "At least one file has no physical extent map"
                )
            }
            mappedExtents.append(extents)
        }

        let unionFind = UnionFind(count: files.count)
        var intervalsByDevice: [UInt64: [PhysicalInterval]] = [:]
        for (fileIndex, file) in files.enumerated() {
            for extent in mappedExtents[fileIndex] where extent.length > 0 {
                let (end, overflow) = extent.deviceOffset.addingReportingOverflow(
                    extent.length
                )
                guard !overflow else {
                    return .notPublished(
                        reason: "A physical extent address overflowed"
                    )
                }
                intervalsByDevice[file.entry.identity.device, default: []]
                    .append(
                        PhysicalInterval(
                            start: extent.deviceOffset,
                            end: end,
                            fileIndex: fileIndex
                        )
                    )
            }
        }

        for intervals in intervalsByDevice.values {
            connectOverlapping(intervals, using: unionFind)
        }

        var indicesByRoot: [Int: [Int]] = [:]
        for index in files.indices {
            indicesByRoot[unionFind.find(index), default: []].append(index)
        }

        let cloneCounts = cloneIdentityCounts(in: files)
        var families: [CloneFamily] = []
        for indices in indicesByRoot.values {
            let outside = outsideMemberState(
                indices: indices,
                files: files,
                cloneCounts: cloneCounts,
                scope: scope
            )
            let hasProvenOutsideMember: Bool
            if case let .known(value, _) = outside {
                hasProvenOutsideMember = value
            } else {
                hasProvenOutsideMember = false
            }

            guard indices.count > 1 || hasProvenOutsideMember else {
                continue
            }

            let paths = indices.map { files[$0].entry.path }.sorted()
            guard let size = unionSize(
                indices: indices,
                files: files,
                mappedExtents: mappedExtents
            ) else {
                return .notPublished(
                    reason: "The physical extent byte total overflowed"
                )
            }
            let freeable: Measurement<UInt64>
            if hasProvenOutsideMember {
                freeable = .known(0, source: .cloneFamilyAccounting)
            } else {
                freeable = .notPublished(
                    reason: "Snapshot references have not been attributed"
                )
            }

            families.append(
                CloneFamily(
                    memberPaths: paths,
                    creditedAtPath: lowestCommonAncestor(of: paths),
                    sizeOnDisk: .known(
                        size,
                        source: .cloneFamilyAccounting
                    ),
                    hasMemberOutsideScan: outside,
                    freedIfDeletingTogether: freeable
                )
            )
        }

        families.sort {
            if $0.creditedAtPath == $1.creditedAtPath {
                return $0.memberPaths.lexicographicallyPrecedes(
                    $1.memberPaths
                )
            }
            return $0.creditedAtPath < $1.creditedAtPath
        }
        return .known(families, source: .cloneFamilyAccounting)
    }
}

private struct PhysicalInterval {
    let start: UInt64
    let end: UInt64
    let fileIndex: Int
}

private final class UnionFind {
    private var parents: [Int]
    private var ranks: [UInt8]

    init(count: Int) {
        parents = Array(0..<count)
        ranks = Array(repeating: 0, count: count)
    }

    func find(_ value: Int) -> Int {
        if parents[value] != value {
            parents[value] = find(parents[value])
        }
        return parents[value]
    }

    func connect(_ left: Int, _ right: Int) {
        let leftRoot = find(left)
        let rightRoot = find(right)
        guard leftRoot != rightRoot else {
            return
        }

        if ranks[leftRoot] < ranks[rightRoot] {
            parents[leftRoot] = rightRoot
        } else if ranks[leftRoot] > ranks[rightRoot] {
            parents[rightRoot] = leftRoot
        } else {
            parents[rightRoot] = leftRoot
            ranks[leftRoot] += 1
        }
    }
}

private func connectOverlapping(
    _ unsortedIntervals: [PhysicalInterval],
    using unionFind: UnionFind
) {
    let intervals = unsortedIntervals.sorted {
        if $0.start == $1.start {
            return $0.end > $1.end
        }
        return $0.start < $1.start
    }

    var active: PhysicalInterval?
    for interval in intervals {
        if let current = active, interval.start < current.end {
            unionFind.connect(current.fileIndex, interval.fileIndex)
            if interval.end > current.end {
                active = interval
            }
        } else {
            active = interval
        }
    }
}

private func cloneIdentityCounts(
    in files: [InspectedFile]
) -> [UInt64: Int] {
    var identitiesByCloneID: [UInt64: Set<FileIdentity>] = [:]
    for file in files {
        guard
            case let .known(metadata, _) = file.extents.cloneMetadata,
            metadata.identifier != 0
        else {
            continue
        }
        identitiesByCloneID[metadata.identifier, default: []]
            .insert(file.entry.identity)
    }
    return identitiesByCloneID.mapValues(\.count)
}

private func outsideMemberState(
    indices: [Int],
    files: [InspectedFile],
    cloneCounts: [UInt64: Int],
    scope: ScanScope
) -> Measurement<Bool> {
    let identities = Dictionary(grouping: indices) {
        files[$0].entry.identity
    }
    for identityIndices in identities.values {
        let observedPaths = identityIndices.count
        let publishedLinkCount = files[identityIndices[0]].entry.hardLinkCount
        if UInt64(observedPaths) < publishedLinkCount {
            return .known(true, source: .cloneFamilyAccounting)
        }
    }

    for index in indices {
        guard
            case let .known(metadata, _) = files[index].extents.cloneMetadata,
            metadata.identifier != 0,
            let observedReferences = cloneCounts[metadata.identifier]
        else {
            continue
        }
        if UInt32(observedReferences) < metadata.referenceCount {
            return .known(true, source: .cloneFamilyAccounting)
        }
    }

    switch scope {
    case .wholeVolume:
        return .known(false, source: .cloneFamilyAccounting)
    case .subtree:
        return .notPublished(
            reason: "A subtree scan cannot prove that no member exists outside it"
        )
    }
}

private func unionSize(
    indices: [Int],
    files: [InspectedFile],
    mappedExtents: [[PhysicalFileExtent]]
) -> UInt64? {
    var intervalsByDevice: [UInt64: [(start: UInt64, end: UInt64)]] = [:]
    for index in indices {
        let device = files[index].entry.identity.device
        for extent in mappedExtents[index] {
            let end = extent.deviceOffset + extent.length
            intervalsByDevice[device, default: []].append(
                (extent.deviceOffset, end)
            )
        }
    }

    var total: UInt64 = 0
    for var intervals in intervalsByDevice.values {
        intervals.sort {
            if $0.start == $1.start {
                return $0.end < $1.end
            }
            return $0.start < $1.start
        }
        guard var merged = intervals.first else {
            continue
        }
        for interval in intervals.dropFirst() {
            if interval.start <= merged.end {
                merged.end = max(merged.end, interval.end)
            } else {
                let (nextTotal, overflow) = total.addingReportingOverflow(
                    merged.end - merged.start
                )
                guard !overflow else {
                    return nil
                }
                total = nextTotal
                merged = interval
            }
        }
        let (nextTotal, overflow) = total.addingReportingOverflow(
            merged.end - merged.start
        )
        guard !overflow else {
            return nil
        }
        total = nextTotal
    }
    return total
}

private func lowestCommonAncestor(of paths: [String]) -> String {
    guard let first = paths.first else {
        return "/"
    }
    if paths.count == 1 {
        return first
    }

    var common = URL(fileURLWithPath: first)
        .deletingLastPathComponent()
        .pathComponents
    for path in paths.dropFirst() {
        let components = URL(fileURLWithPath: path)
            .deletingLastPathComponent()
            .pathComponents
        let sharedCount = zip(common, components)
            .prefix { $0.0 == $0.1 }
            .count
        common.removeSubrange(sharedCount...)
    }

    guard !common.isEmpty else {
        return "/"
    }
    return NSString.path(withComponents: common)
}
