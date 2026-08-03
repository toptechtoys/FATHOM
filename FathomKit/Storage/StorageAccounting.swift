import Foundation

public struct StorageNodeID: RawRepresentable, Hashable, Sendable, Codable {
    public let rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }
}

public struct PathComponentID: RawRepresentable, Hashable, Sendable, Codable {
    public let rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }
}

public struct StorageAccountingNode: Sendable, Equatable {
    public let id: StorageNodeID
    public let parentID: StorageNodeID?
    public let componentID: PathComponentID
    public let kind: StorageEntryKind
    public let entryAllocatedSize: Measurement<UInt64>

    /// Bytes credited directly to this node after shared-family deduplication.
    public let exclusiveSizeOnDisk: Measurement<UInt64>

    /// Additive total of all credits in this node's subtree.
    public let subtreeSizeOnDisk: Measurement<UInt64>

    public init(
        id: StorageNodeID,
        parentID: StorageNodeID?,
        componentID: PathComponentID,
        kind: StorageEntryKind,
        entryAllocatedSize: Measurement<UInt64>,
        exclusiveSizeOnDisk: Measurement<UInt64>,
        subtreeSizeOnDisk: Measurement<UInt64>
    ) {
        self.id = id
        self.parentID = parentID
        self.componentID = componentID
        self.kind = kind
        self.entryAllocatedSize = entryAllocatedSize
        self.exclusiveSizeOnDisk = exclusiveSizeOnDisk
        self.subtreeSizeOnDisk = subtreeSizeOnDisk
    }
}

public struct StorageAccountingSnapshot: Sendable, Equatable {
    public let rootID: StorageNodeID
    public let rootPath: String
    public let pathComponents: [String]
    public let nodes: [StorageAccountingNode]
    public let cloneFamilies: [CloneFamily]

    public init(
        rootID: StorageNodeID,
        rootPath: String,
        pathComponents: [String],
        nodes: [StorageAccountingNode],
        cloneFamilies: [CloneFamily]
    ) {
        self.rootID = rootID
        self.rootPath = rootPath
        self.pathComponents = pathComponents
        self.nodes = nodes
        self.cloneFamilies = cloneFamilies
    }

    public func path(for nodeID: StorageNodeID) -> String? {
        guard Int(nodeID.rawValue) < nodes.count else {
            return nil
        }

        var components: [String] = []
        var currentID: StorageNodeID? = nodeID
        while let id = currentID {
            if id == rootID {
                break
            }
            let node = nodes[Int(id.rawValue)]
            let componentIndex = Int(node.componentID.rawValue)
            guard componentIndex < pathComponents.count else {
                return nil
            }
            components.append(pathComponents[componentIndex])
            currentID = node.parentID
        }

        var resolved = URL(fileURLWithPath: rootPath)
        for component in components.reversed() {
            resolved.append(path: component)
        }
        return resolved.path
    }
}

public struct StorageAccountingBuilder: Sendable {
    public init() {}

    public func build(
        from result: StorageEngineResult
    ) -> Measurement<StorageAccountingSnapshot> {
        guard !result.entries.isEmpty else {
            return .notPublished(reason: "The scan contains no root entry")
        }
        guard case let .known(families, _) = result.cloneFamilies else {
            return .notPublished(
                reason: "Clone-family accounting did not complete"
            )
        }
        guard result.entries.count <= Int(UInt32.max) else {
            return .notPublished(
                reason: "The scan contains more nodes than the index can represent"
            )
        }

        let sortedEntries = result.entries.sorted { $0.path < $1.path }
        var pathToIndex: [String: Int] = [:]
        pathToIndex.reserveCapacity(sortedEntries.count)
        for (index, entry) in sortedEntries.enumerated() {
            pathToIndex[entry.path] = index
        }

        var componentInterner = ComponentInterner()
        var nodes: [MutableAccountingNode] = []
        nodes.reserveCapacity(sortedEntries.count)
        for (index, entry) in sortedEntries.enumerated() {
            let parentPath = URL(fileURLWithPath: entry.path)
                .deletingLastPathComponent()
                .path
            let parentID = pathToIndex[parentPath].map {
                StorageNodeID(rawValue: UInt32($0))
            }
            guard case let .known(allocatedSize, _) = entry.sizeOnDisk else {
                return .notPublished(
                    reason: "An entry has no allocated-byte measurement"
                )
            }

            nodes.append(
                MutableAccountingNode(
                    id: StorageNodeID(rawValue: UInt32(index)),
                    parentID: parentID,
                    componentID: componentInterner.intern(
                        URL(fileURLWithPath: entry.path).lastPathComponent
                    ),
                    kind: entry.kind,
                    entryAllocatedSize: entry.sizeOnDisk,
                    exclusiveBytes: allocatedSize,
                    subtreeBytes: 0
                )
            )
        }

        let familyMemberPaths = Set(families.flatMap(\.memberPaths))
        for path in familyMemberPaths {
            guard let index = pathToIndex[path] else {
                return .notPublished(
                    reason: "A clone-family member is absent from the scan tree"
                )
            }
            nodes[index].exclusiveBytes = 0
        }

        for family in families {
            guard
                let creditIndex = pathToIndex[family.creditedAtPath],
                case let .known(familyBytes, _) = family.sizeOnDisk
            else {
                return .notPublished(
                    reason: "A clone-family credit cannot be placed in the scan tree"
                )
            }
            let (creditedBytes, overflow) = nodes[creditIndex]
                .exclusiveBytes
                .addingReportingOverflow(familyBytes)
            guard !overflow else {
                return .notPublished(
                    reason: "A clone-family credit overflowed"
                )
            }
            nodes[creditIndex].exclusiveBytes = creditedBytes
        }

        for index in nodes.indices.reversed() {
            let (subtreeBytes, overflow) = nodes[index]
                .subtreeBytes
                .addingReportingOverflow(nodes[index].exclusiveBytes)
            guard !overflow else {
                return .notPublished(
                    reason: "A subtree allocated-byte total overflowed"
                )
            }
            nodes[index].subtreeBytes = subtreeBytes

            if let parentID = nodes[index].parentID {
                let parentIndex = Int(parentID.rawValue)
                let (parentBytes, parentOverflow) = nodes[parentIndex]
                    .subtreeBytes
                    .addingReportingOverflow(subtreeBytes)
                guard !parentOverflow else {
                    return .notPublished(
                        reason: "A subtree allocated-byte total overflowed"
                    )
                }
                nodes[parentIndex].subtreeBytes = parentBytes
            }
        }

        let immutableNodes = nodes.map {
            StorageAccountingNode(
                id: $0.id,
                parentID: $0.parentID,
                componentID: $0.componentID,
                kind: $0.kind,
                entryAllocatedSize: $0.entryAllocatedSize,
                exclusiveSizeOnDisk: .known(
                    $0.exclusiveBytes,
                    source: .storageTreeAccounting
                ),
                subtreeSizeOnDisk: .known(
                    $0.subtreeBytes,
                    source: .storageTreeAccounting
                )
            )
        }
        let rootIndex = sortedEntries.firstIndex {
            $0.path == result.rootURL.path
        } ?? 0
        return .known(
            StorageAccountingSnapshot(
                rootID: StorageNodeID(rawValue: UInt32(rootIndex)),
                rootPath: result.rootURL.path,
                pathComponents: componentInterner.components,
                nodes: immutableNodes,
                cloneFamilies: families
            ),
            source: .storageTreeAccounting
        )
    }
}

private struct MutableAccountingNode {
    let id: StorageNodeID
    let parentID: StorageNodeID?
    let componentID: PathComponentID
    let kind: StorageEntryKind
    let entryAllocatedSize: Measurement<UInt64>
    var exclusiveBytes: UInt64
    var subtreeBytes: UInt64
}

private struct ComponentInterner {
    private(set) var components: [String] = []
    private var identifiers: [String: PathComponentID] = [:]

    mutating func intern(_ component: String) -> PathComponentID {
        if let existing = identifiers[component] {
            return existing
        }
        let identifier = PathComponentID(rawValue: UInt32(components.count))
        components.append(component)
        identifiers[component] = identifier
        return identifier
    }
}
