import Darwin
import Foundation

public struct ReclaimRecipe: Sendable, Equatable, Codable {
    public let identifier: String
    public let version: UInt64
    public let regenerationCost: String
    public let safetyClass: ReclaimSafetyClass
    public let allowedRootPath: String?

    public init(
        identifier: String,
        version: UInt64,
        regenerationCost: String,
        safetyClass: ReclaimSafetyClass = .safe,
        allowedRootPath: String? = nil
    ) throws {
        guard !identifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !regenerationCost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ReclaimError.invalidRecipe
        }
        self.identifier = identifier
        self.version = version
        self.regenerationCost = regenerationCost
        self.safetyClass = safetyClass
        self.allowedRootPath = allowedRootPath
    }
}

public struct ReclaimFileMetadata: Sendable, Equatable, Codable {
    public let device: UInt64
    public let inode: UInt64
    public let logicalBytes: UInt64
    public let modificationSeconds: Int64
    public let modificationNanoseconds: Int32

    public init(
        device: UInt64,
        inode: UInt64,
        logicalBytes: UInt64,
        modificationSeconds: Int64,
        modificationNanoseconds: Int32
    ) {
        self.device = device
        self.inode = inode
        self.logicalBytes = logicalBytes
        self.modificationSeconds = modificationSeconds
        self.modificationNanoseconds = modificationNanoseconds
    }

    public var identity: FileIdentity {
        FileIdentity(device: device, inode: inode)
    }
}

public struct ReclaimManifestItem: Sendable, Equatable, Codable, Identifiable {
    public let path: String
    public let metadata: ReclaimFileMetadata
    public let sizeOnDisk: Measurement<UInt64>
    public let freedIfDeleted: Measurement<UInt64>

    public var id: String { path }

    public init(
        path: String,
        metadata: ReclaimFileMetadata,
        sizeOnDisk: Measurement<UInt64>,
        freedIfDeleted: Measurement<UInt64>
    ) {
        self.path = path
        self.metadata = metadata
        self.sizeOnDisk = sizeOnDisk
        self.freedIfDeleted = freedIfDeleted
    }
}

public struct ReclaimManifest: Sendable, Equatable, Codable {
    public let createdAt: Date
    public let recipe: ReclaimRecipe
    public let items: [ReclaimManifestItem]
    public let confirmedItemPaths: Set<String>

    public init(
        createdAt: Date,
        recipe: ReclaimRecipe,
        items: [ReclaimManifestItem],
        confirmedItemPaths: Set<String> = []
    ) {
        self.createdAt = createdAt
        self.recipe = recipe
        self.items = items
        self.confirmedItemPaths = confirmedItemPaths
    }

    public func confirming(itemPaths: Set<String>) -> ReclaimManifest {
        ReclaimManifest(
            createdAt: createdAt,
            recipe: recipe,
            items: items,
            confirmedItemPaths: itemPaths
        )
    }

    public var knownFreeableBytes: UInt64? {
        items.reduce(UInt64(0)) { partial, item in
            guard let partial else { return nil }
            guard case let .known(value, _) = item.freedIfDeleted else {
                return nil
            }
            let (sum, overflow) = partial.addingReportingOverflow(value)
            return overflow ? nil : sum
        }
    }
}

public struct ReclaimRefusal: Sendable, Equatable, Codable {
    public let path: String
    public let reason: String
}

public struct ReclaimDryRun: Sendable, Equatable, Codable {
    public let manifest: ReclaimManifest
    public let refusals: [ReclaimRefusal]

    public func confirming(itemPaths: Set<String>) -> ReclaimDryRun {
        ReclaimDryRun(
            manifest: manifest.confirming(itemPaths: itemPaths),
            refusals: refusals
        )
    }
}

public struct ReclaimExecutionItem: Sendable, Equatable, Codable {
    public enum Outcome: String, Sendable, Codable {
        case movedToTrash
        case refused
        case failed
    }

    public let path: String
    public let outcome: Outcome
    public let detail: String
}

public struct ReclaimExecutionReport: Sendable, Equatable, Codable {
    public let recipe: ReclaimRecipe
    public let finishedAt: Date
    public let items: [ReclaimExecutionItem]
}

public enum ReclaimError: Error, Sendable, Equatable {
    case invalidRecipe
    case cannotReadMetadata(path: String, errorNumber: Int32)
    case openFileInventoryUnavailable(String)
    case journalFailure(String)
    case reportOnlyRecipe(String)
}

public protocol TrashMoving: Sendable {
    func moveToTrash(_ url: URL) throws -> URL?
}

public struct FoundationTrashMover: TrashMoving {
    public init() {}

    public func moveToTrash(_ url: URL) throws -> URL? {
        var resultingURL: NSURL?
        try FileManager.default.trashItem(
            at: url,
            resultingItemURL: &resultingURL
        )
        return resultingURL as URL?
    }
}

public struct ReclaimEngine<Mover: TrashMoving>: Sendable {
    private let mover: Mover

    public init(mover: Mover) {
        self.mover = mover
    }

    public func dryRun(
        entries: [StorageEntry],
        recipe: ReclaimRecipe,
        now: Date = Date()
    ) -> ReclaimDryRun {
        var items: [ReclaimManifestItem] = []
        var refusals: [ReclaimRefusal] = []
        for entry in entries {
            if let reason = ReclaimSafety.refusalReason(for: entry) {
                refusals.append(.init(path: entry.path, reason: reason))
                continue
            }
            do {
                let metadata = try Self.metadata(atPath: entry.path)
                guard metadata.identity == entry.identity else {
                    refusals.append(.init(
                        path: entry.path,
                        reason: "The path identity changed during dry run"
                    ))
                    continue
                }
                items.append(
                    ReclaimManifestItem(
                        path: entry.path,
                        metadata: metadata,
                        sizeOnDisk: entry.sizeOnDisk,
                        freedIfDeleted: entry.freedIfDeleted
                    )
                )
            } catch {
                refusals.append(.init(
                    path: entry.path,
                    reason: "Metadata could not be re-read: \(error)"
                ))
            }
        }
        return ReclaimDryRun(
            manifest: ReclaimManifest(
                createdAt: now,
                recipe: recipe,
                items: items
            ),
            refusals: refusals
        )
    }

    public func execute(
        _ manifest: ReclaimManifest,
        journalURL: URL
    ) throws -> ReclaimExecutionReport {
        let openInventory: Set<FileIdentity>
        do {
            let inventory = try OpenFileReferenceReader().inventory()
            guard case let .known(identities, _) = inventory.completeIdentities else {
                throw ReclaimError.openFileInventoryUnavailable(
                    "Open-file enumeration was incomplete"
                )
            }
            openInventory = identities
        } catch let error as ReclaimError {
            throw error
        } catch {
            throw ReclaimError.openFileInventoryUnavailable("\(error)")
        }

        return try execute(
            manifest,
            journalURL: journalURL,
            knownOpenFileIdentities: openInventory
        )
    }

    func execute(
        _ manifest: ReclaimManifest,
        journalURL: URL,
        knownOpenFileIdentities openInventory: Set<FileIdentity>
    ) throws -> ReclaimExecutionReport {
        guard manifest.recipe.safetyClass != .reportOnly else {
            throw ReclaimError.reportOnlyRecipe(
                manifest.recipe.identifier
            )
        }
        var results: [ReclaimExecutionItem] = []
        for item in manifest.items {
            let result: ReclaimExecutionItem
            do {
                // Re-apply the protected-path refusals here as well as in the
                // dry run: this is the last check before anything moves.
                if let reason = ReclaimSafety.refusalReason(forPath: item.path) {
                    result = .init(
                        path: item.path,
                        outcome: .refused,
                        detail: reason
                    )
                    results.append(result)
                    continue
                }
                if manifest.recipe.safetyClass == .requiresPerItemConfirmation,
                   !manifest.confirmedItemPaths.contains(item.path) {
                    result = .init(
                        path: item.path,
                        outcome: .refused,
                        detail: "This item did not receive explicit per-item confirmation"
                    )
                    results.append(result)
                    continue
                }
                if let root = manifest.recipe.allowedRootPath,
                   !Self.isContained(item.path, in: root) {
                    result = .init(
                        path: item.path,
                        outcome: .refused,
                        detail: "The resolved path escaped its recipe root"
                    )
                    results.append(result)
                    continue
                }
                let current = try Self.metadata(atPath: item.path)
                guard current == item.metadata else {
                    result = .init(
                        path: item.path,
                        outcome: .refused,
                        detail: "Identity, size, or modification time changed after dry run"
                    )
                    results.append(result)
                    continue
                }
                guard !openInventory.contains(current.identity) else {
                    result = .init(
                        path: item.path,
                        outcome: .refused,
                        detail: "A live process has this item open"
                    )
                    results.append(result)
                    continue
                }
                guard case .known = item.freedIfDeleted else {
                    result = .init(
                        path: item.path,
                        outcome: .refused,
                        detail: "Freed-if-deleted is not published"
                    )
                    results.append(result)
                    continue
                }
                try ReclaimJournal.append(
                    ReclaimJournalRecord(
                        timestamp: Date(),
                        phase: .intent,
                        recipe: manifest.recipe,
                        path: item.path,
                        outcome: nil,
                        detail: "Approved dry-run identity \(current.device):\(current.inode)"
                    ),
                    to: journalURL
                )
                let destination = try mover.moveToTrash(
                    URL(fileURLWithPath: item.path)
                )
                result = .init(
                    path: item.path,
                    outcome: .movedToTrash,
                    detail: destination?.path ?? "Moved to Trash"
                )
            } catch {
                result = .init(
                    path: item.path,
                    outcome: .failed,
                    detail: "\(error)"
                )
            }
            results.append(result)
            do {
                try ReclaimJournal.append(
                    ReclaimJournalRecord(
                        timestamp: Date(),
                        phase: .outcome,
                        recipe: manifest.recipe,
                        path: result.path,
                        outcome: result.outcome,
                        detail: result.detail
                    ),
                    to: journalURL
                )
            } catch {
                throw ReclaimError.journalFailure("\(error)")
            }
        }
        let report = ReclaimExecutionReport(
            recipe: manifest.recipe,
            finishedAt: Date(),
            items: results
        )
        do {
            try ReclaimJournal.append(report, to: journalURL)
        } catch {
            throw ReclaimError.journalFailure("\(error)")
        }
        return report
    }

    private static func isContained(_ path: String, in rootPath: String) -> Bool {
        let resolvedPath = URL(fileURLWithPath: path)
            .standardizedFileURL.resolvingSymlinksInPath().path
        let resolvedRoot = URL(fileURLWithPath: rootPath)
            .standardizedFileURL.resolvingSymlinksInPath().path
        return resolvedPath == resolvedRoot ||
            resolvedPath.hasPrefix(resolvedRoot + "/")
    }

    private static func metadata(
        atPath path: String
    ) throws -> ReclaimFileMetadata {
        var value = stat()
        guard lstat(path, &value) == 0 else {
            throw ReclaimError.cannotReadMetadata(
                path: path,
                errorNumber: errno
            )
        }
        return ReclaimFileMetadata(
            device: UInt64(value.st_dev),
            inode: UInt64(value.st_ino),
            logicalBytes: UInt64(max(value.st_size, 0)),
            modificationSeconds: Int64(value.st_mtimespec.tv_sec),
            modificationNanoseconds: Int32(value.st_mtimespec.tv_nsec)
        )
    }
}

public extension ReclaimEngine where Mover == FoundationTrashMover {
    init() {
        self.init(mover: FoundationTrashMover())
    }
}

private enum ReclaimSafety {
    static func refusalReason(for entry: StorageEntry) -> String? {
        if let reason = refusalReason(forPath: entry.path) {
            return reason
        }
        if entry.isDataless {
            return "Dataless files are never materialized for reclaim"
        }
        return nil
    }

    /// The path-only refusals, split out so `execute` can re-apply them against
    /// the path as it resolves at that moment. No shipped recipe sets an
    /// `allowedRootPath`, so this is the guard that holds for a manifest that
    /// did not come straight from `dryRun`.
    static func refusalReason(forPath candidatePath: String) -> String? {
        let path = URL(fileURLWithPath: candidatePath)
            .standardizedFileURL.resolvingSymlinksInPath().path
        if path == "/System" || path.hasPrefix("/System/") {
            return "System paths are never reclaim targets"
        }
        if path == "/private/var/vm" || path.hasPrefix("/private/var/vm/") {
            return "Virtual-memory paths are read-only"
        }
        if path.contains("/Library/Group Containers/") {
            return "Group Containers are never reclaim targets"
        }
        if path.lowercased().contains(".photoslibrary/") ||
            path.lowercased().hasSuffix(".photoslibrary") {
            return "Photo libraries are never reclaim targets"
        }
        if path.contains("/MobileSync/Backup") {
            return "Device backups require their dedicated flow"
        }
        if path.range(
            of: #"/Library/Mail/V[0-9]+(?:/|$)"#,
            options: .regularExpression
        ) != nil {
            return "Live and migrated Mail stores require dedicated confirmation"
        }
        if let range = path.range(of: "/Library/Containers/"),
           path[range.upperBound...].contains("/Data"),
           !path.contains("/Data/Library/Caches/") &&
           !path.hasSuffix("/Data/Library/Caches") {
            return "A sandbox container Data directory is an app home"
        }
        if path.contains(".app/Contents/") {
            return "Application bundle internals are never modified"
        }
        return nil
    }
}

private enum ReclaimJournal {
    static func append<Value: Encodable>(
        _ value: Value,
        to url: URL
    ) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        if !FileManager.default.fileExists(atPath: url.path) {
            guard FileManager.default.createFile(atPath: url.path, contents: nil) else {
                throw CocoaError(.fileWriteUnknown)
            }
        }
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        var data = try JSONEncoder().encode(value)
        data.append(0x0A)
        try handle.write(contentsOf: data)
        try handle.synchronize()
    }
}

private struct ReclaimJournalRecord: Encodable {
    enum Phase: String, Encodable {
        case intent
        case outcome
    }

    let timestamp: Date
    let phase: Phase
    let recipe: ReclaimRecipe
    let path: String
    let outcome: ReclaimExecutionItem.Outcome?
    let detail: String
}
