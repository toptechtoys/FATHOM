import CSQLite
import Foundation

public enum StorageIndexError: Error, Sendable, Equatable {
    case cannotOpen(path: String, code: Int32, message: String)
    case sqlite(code: Int32, message: String)
    case integrityFailure(message: String)
    case invalidScan(reason: String)
    case closed
}

public enum MemoryOnlyIndexReason: Sendable, Equatable {
    case storageFull
}

public enum StorageIndexWriteOutcome: Sendable, Equatable {
    case persisted(scanID: Int64)

    /// The caller's in-memory `StorageEngineResult` remains authoritative.
    case memoryOnly(reason: MemoryOnlyIndexReason)
}

public struct IndexedScanSummary: Sendable, Equatable {
    public let scanID: Int64
    public let rootPath: String
    public let isComplete: Bool
    public let nodeCount: Int64
    public let familyCount: Int64
    public let snapshotCount: Int64
    public let schemaVersion: Int32

    public init(
        scanID: Int64,
        rootPath: String,
        isComplete: Bool,
        nodeCount: Int64,
        familyCount: Int64,
        snapshotCount: Int64,
        schemaVersion: Int32
    ) {
        self.scanID = scanID
        self.rootPath = rootPath
        self.isComplete = isComplete
        self.nodeCount = nodeCount
        self.familyCount = familyCount
        self.snapshotCount = snapshotCount
        self.schemaVersion = schemaVersion
    }
}

public struct StagedTraversalScan: Sendable, Equatable {
    public let scanID: Int64
    public let rootURL: URL
    public let scope: ScanScope
    public let entryCount: UInt64
    public let regularFileCount: UInt64
    /// Directories reached by a second path and counted once. See
    /// `StorageScanSummary.aliasedDirectoriesSkipped`.
    public let aliasedDirectoriesSkipped: UInt64
    /// Mounts declined for belonging to another APFS container. See
    /// `StorageScanSummary.otherContainerMountsSkipped`.
    public let otherContainerMountsSkipped: UInt64
    public let issues: [StorageScanIssue]

    public var isComplete: Bool {
        issues.isEmpty
    }

    public init(
        scanID: Int64,
        rootURL: URL,
        scope: ScanScope,
        entryCount: UInt64,
        regularFileCount: UInt64,
        aliasedDirectoriesSkipped: UInt64 = 0,
        otherContainerMountsSkipped: UInt64 = 0,
        issues: [StorageScanIssue]
    ) {
        self.scanID = scanID
        self.rootURL = rootURL
        self.scope = scope
        self.entryCount = entryCount
        self.regularFileCount = regularFileCount
        self.aliasedDirectoriesSkipped = aliasedDirectoriesSkipped
        self.otherContainerMountsSkipped = otherContainerMountsSkipped
        self.issues = issues
    }
}

public struct StagedExtentInspectionSummary: Sendable, Equatable {
    public let inspectedFileCount: UInt64
    /// Files the scan could not inspect. Something is wrong, or something is
    /// denied: a read that failed, extents that would not reconcile, a
    /// filesystem that publishes no addresses.
    public let failedFileCount: UInt64
    /// Files the system would not open at all.
    ///
    /// `EACCES` and `EPERM` only: a path root owns, or one behind SIP. Full
    /// Disk Access does not reach them and only running as root would, which
    /// non-negotiable 8 forbids. Counting them as inspection failures asked
    /// this product to become root before its gate could pass.
    public let refusedBySystemCount: UInt64
    /// Files that were replaced while the scan was running.
    ///
    /// Kept apart from the failures because it measures the machine rather
    /// than the engine. A whole-volume scan takes minutes, and a Mac in use
    /// writes throughout: one run saw 64 of these, the next 2,035, with no
    /// code between them. Nothing was wrong either time.
    public let changedDuringScanCount: UInt64

    public init(
        inspectedFileCount: UInt64,
        failedFileCount: UInt64,
        refusedBySystemCount: UInt64 = 0,
        changedDuringScanCount: UInt64 = 0
    ) {
        self.inspectedFileCount = inspectedFileCount
        self.failedFileCount = failedFileCount
        self.refusedBySystemCount = refusedBySystemCount
        self.changedDuringScanCount = changedDuringScanCount
    }
}

public struct StagedAccountingSummary: Sendable, Equatable {
    public let scanID: Int64
    public let nodeCount: UInt64
    public let physicalSegmentCount: UInt64
    public let sizeOnDisk: Measurement<UInt64>

    public init(
        scanID: Int64,
        nodeCount: UInt64,
        physicalSegmentCount: UInt64,
        sizeOnDisk: Measurement<UInt64>
    ) {
        self.scanID = scanID
        self.nodeCount = nodeCount
        self.physicalSegmentCount = physicalSegmentCount
        self.sizeOnDisk = sizeOnDisk
    }
}

public struct StagedStorageNodeSummary: Identifiable, Sendable, Equatable {
    public let id: Int64
    public let parentID: Int64?
    public let name: String
    public let path: String
    public let kind: StorageEntryKind
    public let sizeOnDisk: Measurement<UInt64>
    public let freedIfDeleted: Measurement<UInt64>

    public init(
        id: Int64,
        parentID: Int64?,
        name: String,
        path: String,
        kind: StorageEntryKind,
        sizeOnDisk: Measurement<UInt64>,
        freedIfDeleted: Measurement<UInt64>
    ) {
        self.id = id
        self.parentID = parentID
        self.name = name
        self.path = path
        self.kind = kind
        self.sizeOnDisk = sizeOnDisk
        self.freedIfDeleted = freedIfDeleted
    }
}

public struct StagedFreeableAccountingSummary: Sendable, Equatable {
    public let scanID: Int64
    public let freedIfDeleted: Measurement<UInt64>

    public init(
        scanID: Int64,
        freedIfDeleted: Measurement<UInt64>
    ) {
        self.scanID = scanID
        self.freedIfDeleted = freedIfDeleted
    }
}

public struct StorageIndexDiagnostics: Sendable, Equatable {
    public let schemaVersion: Int32
    public let lastScanDurationSeconds: String?

    public init(schemaVersion: Int32, lastScanDurationSeconds: String?) {
        self.schemaVersion = schemaVersion
        self.lastScanDurationSeconds = lastScanDurationSeconds
    }
}

public enum StoragePaletteQuery: Sendable, Equatable {
    case text(String)
    case minimumAllocatedBytes(UInt64)
    case clones
    case changedThisWeek

    public static func parse(_ input: String) -> StoragePaletteQuery? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let lower = trimmed.lowercased()
        if lower == "clones" { return .clones }
        if lower == "changed this week" { return .changedThisWeek }
        let parts = lower.split(whereSeparator: \.isWhitespace)
        if parts.count == 3, parts[0] == "over",
           let amount = Double(parts[1]), amount >= 0 {
            let multiplier: Double
            switch parts[2] {
            case "kb": multiplier = 1_000
            case "mb": multiplier = 1_000_000
            case "gb": multiplier = 1_000_000_000
            case "tb": multiplier = 1_000_000_000_000
            default: return .text(trimmed)
            }
            let bytes = amount * multiplier
            guard bytes.isFinite, bytes <= Double(UInt64.max) else {
                return nil
            }
            return .minimumAllocatedBytes(UInt64(bytes.rounded(.up)))
        }
        return .text(trimmed)
    }
}

public struct DirectoryGrowthFinding: Sendable, Equatable {
    public let path: String
    public let growthBytes: UInt64

    public init(path: String, growthBytes: UInt64) {
        self.path = path
        self.growthBytes = growthBytes
    }
}

/// The regenerable storage index. Reclaim journaling must never use this file.
public actor StorageIndex {
    public static let schemaVersion: Int32 = 9

    /// 16,384 pages × 4,096 = 64 MB. This is a compromise, not a derived
    /// optimum. SQLite's default of 1,000 pages checkpoints every 4 MB, which
    /// writes the database file far harder — and this app ships an
    /// SSD-endurance screen, so bytes written to the drive are a cost it is
    /// not entitled to be careless with. The budget does nothing at all until
    /// the traversal commits in batches: SQLite only auto-checkpoints at the
    /// end of a committing write transaction, and a whole-volume walk used to
    /// be one transaction from first entry to last.
    static let defaultWALAutocheckpointPages: Int32 = 16_384

    /// One batch of staged entries per commit. At the 749 bytes/entry measured
    /// over 200,000 real paths on the owner's machine this is ≈37 MB of pages,
    /// one batch clear of the 64 MB autocheckpoint budget above.
    static let defaultTraversalBatchSize: Int64 = 50_000

    private let handle: DatabaseHandle
    private let traversalBatchSize: Int64

    public init(url: URL) throws {
        try self.init(
            url: url,
            maximumAdditionalPagesForTesting: nil
        )
    }

    public static func readOnlyDiagnostics(at url: URL) throws
        -> StorageIndexDiagnostics
    {
        var database: OpaquePointer?
        let code = sqlite3_open_v2(
            url.path,
            &database,
            SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX,
            nil
        )
        guard code == SQLITE_OK, let database else {
            let message = sqliteMessage(from: database)
            if let database { sqlite3_close(database) }
            throw StorageIndexError.cannotOpen(
                path: url.path,
                code: code,
                message: message
            )
        }
        defer { sqlite3_close(database) }
        let version = try currentSchemaVersion(database: database)
        let duration: String?
        do {
            let statement = try prepare(
                database: database,
                sql: """
                    SELECT value FROM diagnostic_values
                    WHERE key = 'last_scan_duration_seconds'
                    """
            )
            defer { sqlite3_finalize(statement) }
            let step = sqlite3_step(statement)
            if step == SQLITE_ROW, let text = sqlite3_column_text(statement, 0) {
                duration = String(cString: text)
            } else if step == SQLITE_DONE {
                duration = nil
            } else {
                throw sqliteError(database: database, code: step)
            }
        } catch let error as StorageIndexError {
            if case let .sqlite(_, message) = error,
               message.contains("no such table") {
                duration = nil
            } else {
                throw error
            }
        }
        return StorageIndexDiagnostics(
            schemaVersion: version,
            lastScanDurationSeconds: duration
        )
    }

    init(
        url: URL,
        walAutocheckpointPages: Int32 =
            StorageIndex.defaultWALAutocheckpointPages,
        traversalBatchSize: Int64 = StorageIndex.defaultTraversalBatchSize,
        maximumAdditionalPagesForTesting: Int32?
    ) throws {
        // Assigned before anything that can throw, so the failure paths below
        // do not have to care about it.
        self.traversalBatchSize = max(1, traversalBatchSize)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        var openedDatabase: OpaquePointer?
        let openCode = sqlite3_open_v2(
            url.path,
            &openedDatabase,
            SQLITE_OPEN_READWRITE |
                SQLITE_OPEN_CREATE |
                SQLITE_OPEN_FULLMUTEX,
            nil
        )
        guard openCode == SQLITE_OK, let openedDatabase else {
            let message = sqliteMessage(from: openedDatabase)
            if let openedDatabase {
                sqlite3_close(openedDatabase)
            }
            throw StorageIndexError.cannotOpen(
                path: url.path,
                code: openCode,
                message: message
            )
        }

        do {
            try execute(
                database: openedDatabase,
                sql: "PRAGMA foreign_keys = ON"
            )
            try execute(
                database: openedDatabase,
                sql: "PRAGMA journal_mode = WAL"
            )
            try execute(
                database: openedDatabase,
                sql: "PRAGMA cache_size = -32768"
            )
            try execute(
                database: openedDatabase,
                sql: "PRAGMA temp_store = FILE"
            )
            try execute(
                database: openedDatabase,
                sql: "PRAGMA wal_autocheckpoint = \(walAutocheckpointPages)"
            )
            try execute(
                database: openedDatabase,
                sql: Self.schemaSQL
            )
            try ensureColumn(
                database: openedDatabase,
                table: "staged_entries",
                name: "clone_id",
                definition: "INTEGER"
            )
            try ensureColumn(
                database: openedDatabase,
                table: "staged_node_totals",
                name: "raw_subtree_size",
                definition: "INTEGER NOT NULL DEFAULT 0"
            )
            try ensureColumn(
                database: openedDatabase,
                table: "staged_node_totals",
                name: "exclusive_freeable",
                definition: "INTEGER"
            )
            try ensureColumn(
                database: openedDatabase,
                table: "staged_node_totals",
                name: "subtree_freeable",
                definition: "INTEGER"
            )
            try ensureColumn(
                database: openedDatabase,
                table: "staged_node_totals",
                name: "freeable_state",
                definition: "INTEGER NOT NULL DEFAULT 1"
            )
            try ensureColumn(
                database: openedDatabase,
                table: "staged_node_totals",
                name: "freeable_reason",
                definition: "TEXT"
            )
            try ensureColumn(
                database: openedDatabase,
                table: "staged_node_totals",
                name: "on_disk_complete",
                definition: "INTEGER NOT NULL DEFAULT 0"
            )
            try ensureColumn(
                database: openedDatabase,
                table: "staged_entries",
                name: "clone_reference_count",
                definition: "INTEGER"
            )
            try ensureColumn(
                database: openedDatabase,
                table: "staged_entries",
                name: "allocation_block_size",
                definition: "INTEGER"
            )
            // Schema 9. The traversal now commits in batches, so a killed
            // scan leaves committed rows behind. This column is the only
            // thing that still distinguishes a finished scan from a partial
            // one, and `precedingStagedScanID` filters on it.
            try ensureColumn(
                database: openedDatabase,
                table: "staged_scans",
                name: "completed_at",
                definition: "REAL"
            )
            try execute(
                database: openedDatabase,
                sql: "PRAGMA user_version = \(Self.schemaVersion)"
            )
            if let maximumAdditionalPagesForTesting {
                let currentPages = try scalarInt32(
                    database: openedDatabase,
                    sql: "PRAGMA page_count"
                )
                let (maximumPages, overflow) = currentPages
                    .addingReportingOverflow(
                        maximumAdditionalPagesForTesting
                    )
                guard !overflow, maximumPages > 0 else {
                    throw StorageIndexError.invalidScan(
                        reason: "The test page limit is invalid"
                    )
                }
                try execute(
                    database: openedDatabase,
                    sql: "PRAGMA max_page_count = \(maximumPages)"
                )
            }
        } catch {
            sqlite3_close(openedDatabase)
            throw error
        }
        handle = DatabaseHandle(openedDatabase)
    }

    /// Checkpointing here is the difference between an index that costs what
    /// it holds and one that costs what it has ever held. Until a checkpoint
    /// runs, the `-wal` carries a full page-image copy of everything written
    /// since the last one, and SQLite only ever extends that file: it is
    /// shortened by a checkpoint in TRUNCATE mode, or by SQLite's own
    /// close-time cleanup, which a SIGKILL skips. Measured on the owner's
    /// machine: 3,841,203,752 bytes of `-wal` beside a 4,096-byte database,
    /// of which 3.48 GiB carried salts that no longer matched the header and
    /// could never be read again.
    ///
    /// `sqlite3_close_v2`, not `sqlite3_close`: the plain form returns
    /// SQLITE_BUSY and leaves the connection open when a statement is
    /// unfinalized, and this function used to throw that code away while
    /// nilling the handle — which stranded the connection and its log with
    /// nothing able to retry. `close_v2` always releases.
    public func close() {
        guard let database = handle.pointer else {
            return
        }
        try? execute(
            database: database,
            sql: "PRAGMA wal_checkpoint(TRUNCATE)"
        )
        handle.pointer = nil
        sqlite3_close_v2(database)
    }

    public func store(
        result: StorageEngineResult,
        accounting: StorageAccountingSnapshot,
        startedAt: Date = Date()
    ) throws -> StorageIndexWriteOutcome {
        guard let database = handle.pointer else {
            throw StorageIndexError.closed
        }

        var transactionStarted = false
        do {
            try execute(database: database, sql: "BEGIN IMMEDIATE")
            transactionStarted = true

            let scanID = try insertScan(
                database: database,
                result: result,
                startedAt: startedAt
            )
            try insertComponents(
                database: database,
                scanID: scanID,
                accounting: accounting
            )
            try insertNodes(
                database: database,
                scanID: scanID,
                result: result,
                accounting: accounting
            )
            try insertFamilies(
                database: database,
                scanID: scanID,
                accounting: accounting
            )
            try insertSnapshots(
                database: database,
                scanID: scanID,
                inventory: result.snapshotInventory,
                manifests: result.snapshotManifests
            )
            try execute(database: database, sql: "COMMIT")
            return .persisted(scanID: scanID)
        } catch let error as StorageIndexError {
            if transactionStarted {
                try? execute(database: database, sql: "ROLLBACK")
            }
            if case let .sqlite(code, _) = error, code == SQLITE_FULL {
                return .memoryOnly(reason: .storageFull)
            }
            throw error
        } catch {
            if transactionStarted {
                try? execute(database: database, sql: "ROLLBACK")
            }
            throw error
        }
    }

    public func latestScanSummary() throws -> IndexedScanSummary? {
        guard let database = handle.pointer else {
            throw StorageIndexError.closed
        }

        let sql = """
            SELECT
                scans.id,
                scans.root_path,
                scans.complete,
                (SELECT COUNT(*) FROM nodes WHERE scan_id = scans.id),
                (SELECT COUNT(*) FROM families WHERE scan_id = scans.id),
                (SELECT COUNT(*) FROM snapshots WHERE scan_id = scans.id)
            FROM scans
            ORDER BY scans.id DESC
            LIMIT 1
            """
        let statement = try prepare(database: database, sql: sql)
        defer { sqlite3_finalize(statement) }

        let stepCode = sqlite3_step(statement)
        if stepCode == SQLITE_DONE {
            return nil
        }
        guard stepCode == SQLITE_ROW else {
            throw sqliteError(database: database, code: stepCode)
        }
        guard let rootText = sqlite3_column_text(statement, 1) else {
            throw StorageIndexError.invalidScan(
                reason: "The latest scan has no root path"
            )
        }

        return IndexedScanSummary(
            scanID: sqlite3_column_int64(statement, 0),
            rootPath: String(cString: rootText),
            isComplete: sqlite3_column_int(statement, 2) != 0,
            nodeCount: sqlite3_column_int64(statement, 3),
            familyCount: sqlite3_column_int64(statement, 4),
            snapshotCount: sqlite3_column_int64(statement, 5),
            schemaVersion: try currentSchemaVersion(database: database)
        )
    }

    public func integrityCheck() throws -> String {
        guard let database = handle.pointer else {
            throw StorageIndexError.closed
        }
        let statement = try prepare(
            database: database,
            sql: "PRAGMA integrity_check"
        )
        defer { sqlite3_finalize(statement) }
        let stepCode = sqlite3_step(statement)
        guard
            stepCode == SQLITE_ROW,
            let text = sqlite3_column_text(statement, 0)
        else {
            throw sqliteError(database: database, code: stepCode)
        }
        return String(cString: text)
    }

    public func setDiagnosticValue(_ value: String, forKey key: String) throws {
        guard let database = handle.pointer else {
            throw StorageIndexError.closed
        }
        let statement = try prepare(
            database: database,
            sql: """
                INSERT INTO diagnostic_values(key, value)
                VALUES (?, ?)
                ON CONFLICT(key) DO UPDATE SET value = excluded.value
                """
        )
        defer { sqlite3_finalize(statement) }
        try bindText(key, at: 1, statement: statement)
        try bindText(value, at: 2, statement: statement)
        try stepDone(statement, database: database)
    }

    public func diagnosticValue(forKey key: String) throws -> String? {
        guard let database = handle.pointer else {
            throw StorageIndexError.closed
        }
        let statement = try prepare(
            database: database,
            sql: "SELECT value FROM diagnostic_values WHERE key = ?"
        )
        defer { sqlite3_finalize(statement) }
        try bindText(key, at: 1, statement: statement)
        let code = sqlite3_step(statement)
        if code == SQLITE_DONE { return nil }
        guard code == SQLITE_ROW,
              let text = sqlite3_column_text(statement, 0) else {
            throw sqliteError(database: database, code: code)
        }
        return String(cString: text)
    }

    public func schemaVersionOnDisk() throws -> Int32 {
        guard let database = handle.pointer else {
            throw StorageIndexError.closed
        }
        return try currentSchemaVersion(database: database)
    }

    /// Streams the FTS walk directly into SQLite.
    ///
    /// Only the current directory stack and the issue list remain in memory;
    /// full paths are bound into SQLite and released on each callback.
    public func stageTraversal(
        at rootURL: URL,
        scope: ScanScope,
        startedAt: Date = Date()
    ) throws -> StagedTraversalScan {
        guard let database = handle.pointer else {
            throw StorageIndexError.closed
        }

        try execute(database: database, sql: "BEGIN IMMEDIATE")
        do {
            let scanStatement = try prepare(
                database: database,
                sql: """
                    INSERT INTO staged_scans(root_path, scope, started_at)
                    VALUES (?, ?, ?)
                    """
            )
            defer { sqlite3_finalize(scanStatement) }
            try bindText(rootURL.path, at: 1, statement: scanStatement)
            try bindInt64(
                scope == .wholeVolume ? 1 : 0,
                at: 2,
                statement: scanStatement
            )
            try check(
                sqlite3_bind_double(
                    scanStatement,
                    3,
                    startedAt.timeIntervalSince1970
                ),
                database: database
            )
            try stepDone(scanStatement, database: database)
            let scanID = sqlite3_last_insert_rowid(database)

            let entryStatement = try prepare(
                database: database,
                sql: """
                    INSERT INTO staged_entries(
                        scan_id, id, parent_id, component, path, kind,
                        device, inode, hard_link_count,
                        logical_size, allocated_size,
                        modified_seconds, modified_nanoseconds,
                        is_dataless, extent_state
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0)
                    """
            )
            defer { sqlite3_finalize(entryStatement) }
            let searchStatement = try prepare(
                database: database,
                sql: """
                    INSERT INTO staged_path_fts(
                        scan_id, entry_id, component, path
                    ) VALUES (?, ?, ?, ?)
                    """
            )
            defer { sqlite3_finalize(searchStatement) }

            var directoryStack: [(depth: UInt64, id: Int64)] = []
            var nextID: Int64 = 0
            var regularFileCount: UInt64 = 0
            // Read once into a local so the walk closure captures a value
            // rather than the actor.
            let batchSize = traversalBatchSize
            let summary = try StorageScanner().walk(at: rootURL) { entry in
                guard
                    let location = entry.traversalLocation,
                    case let .known(logicalSize, _) = entry.logicalSize,
                    case let .known(allocatedSize, _) = entry.sizeOnDisk,
                    case let .known(modified, _) = entry.modificationTime
                else {
                    throw StorageIndexError.invalidScan(
                        reason: "A traversal record is missing required metadata"
                    )
                }

                while
                    let last = directoryStack.last,
                    last.depth >= location.depth
                {
                    directoryStack.removeLast()
                }
                let parentID = location.depth == 0
                    ? nil
                    : directoryStack.last?.id
                guard location.depth == 0 || parentID != nil else {
                    throw StorageIndexError.invalidScan(
                        reason: "A traversal record has no staged parent"
                    )
                }

                sqlite3_reset(entryStatement)
                sqlite3_clear_bindings(entryStatement)
                try bindInt64(scanID, at: 1, statement: entryStatement)
                try bindInt64(nextID, at: 2, statement: entryStatement)
                if let parentID {
                    try bindInt64(
                        parentID,
                        at: 3,
                        statement: entryStatement
                    )
                } else {
                    try bindNull(at: 3, statement: entryStatement)
                }
                try bindText(
                    location.name,
                    at: 4,
                    statement: entryStatement
                )
                try bindText(entry.path, at: 5, statement: entryStatement)
                try bindInt64(
                    Int64(storageKindCode(entry.kind)),
                    at: 6,
                    statement: entryStatement
                )
                try bindUInt64(
                    entry.identity.device,
                    at: 7,
                    statement: entryStatement
                )
                try bindUInt64(
                    entry.identity.inode,
                    at: 8,
                    statement: entryStatement
                )
                try bindUInt64(
                    entry.hardLinkCount,
                    at: 9,
                    statement: entryStatement
                )
                try bindUInt64(
                    logicalSize,
                    at: 10,
                    statement: entryStatement
                )
                try bindUInt64(
                    allocatedSize,
                    at: 11,
                    statement: entryStatement
                )
                try bindInt64(
                    modified.secondsSinceEpoch,
                    at: 12,
                    statement: entryStatement
                )
                try bindInt64(
                    Int64(modified.nanoseconds),
                    at: 13,
                    statement: entryStatement
                )
                try bindInt64(
                    entry.isDataless ? 1 : 0,
                    at: 14,
                    statement: entryStatement
                )
                try stepDone(entryStatement, database: database)

                sqlite3_reset(searchStatement)
                sqlite3_clear_bindings(searchStatement)
                try bindInt64(scanID, at: 1, statement: searchStatement)
                try bindInt64(nextID, at: 2, statement: searchStatement)
                try bindText(location.name, at: 3, statement: searchStatement)
                try bindText(entry.path, at: 4, statement: searchStatement)
                try stepDone(searchStatement, database: database)

                if entry.kind == .directory {
                    directoryStack.append(
                        (depth: location.depth, id: nextID)
                    )
                } else if entry.kind == .regularFile {
                    regularFileCount += 1
                }
                nextID += 1

                // The whole walk used to run inside one BEGIN IMMEDIATE, and
                // SQLite only auto-checkpoints at the end of a committing
                // write transaction — so the log was structurally guaranteed
                // to reach the full page image of an entire scan before any
                // checkpoint was possible. On the owner's volume that was a
                // 3.6 GB `-wal` beside a 4 KB database. Committing per batch
                // is what lets the autocheckpoint budget above ever fire.
                //
                // The cancellation check belongs on this boundary and nowhere
                // else: it is the only point in the walk where the database
                // is in a consistent state. Before it existed a whole-volume
                // scan could only be stopped by killing the process, which is
                // exactly how the 3.48 GiB of unreadable log was created.
                if nextID % batchSize == 0 {
                    try execute(database: database, sql: "COMMIT")
                    try Task.checkCancellation()
                    try execute(database: database, sql: "BEGIN IMMEDIATE")
                }
            }

            let issueStatement = try prepare(
                database: database,
                sql: """
                    INSERT INTO staged_issues(
                        scan_id, ordinal, path, stage, error_number, reason
                    ) VALUES (?, ?, ?, 0, ?, ?)
                    """
            )
            defer { sqlite3_finalize(issueStatement) }
            for (ordinal, issue) in summary.issues.enumerated() {
                sqlite3_reset(issueStatement)
                sqlite3_clear_bindings(issueStatement)
                try bindInt64(scanID, at: 1, statement: issueStatement)
                try bindInt64(
                    Int64(ordinal),
                    at: 2,
                    statement: issueStatement
                )
                try bindText(issue.path, at: 3, statement: issueStatement)
                try bindInt64(
                    Int64(issue.errorNumber),
                    at: 4,
                    statement: issueStatement
                )
                try bindText(
                    "FTS could not read this entry",
                    at: 5,
                    statement: issueStatement
                )
                try stepDone(issueStatement, database: database)
            }
            try markStagedScanComplete(
                database: database,
                scanID: scanID,
                completedAt: Date()
            )
            try execute(database: database, sql: "COMMIT")
            do {
                try pruneStagedScans(database: database, keeping: 2)
            } catch {
                // Retention is not worth discarding a completed whole-volume
                // scan for — that scan can take hours and is already durable.
                // Record why it failed rather than swallowing it.
                try? setDiagnosticValue(
                    String(describing: error),
                    forKey: "last_staged_scan_prune_error"
                )
            }
            // The log holds a full page image of everything written since the
            // last checkpoint. Truncating at the end of the longest stage is
            // what stops a finished scan from leaving a multi-gigabyte `-wal`
            // behind for a process that may never close cleanly.
            truncateWriteAheadLog(database: database)
            return StagedTraversalScan(
                scanID: scanID,
                rootURL: rootURL,
                scope: scope,
                entryCount: summary.entryCount,
                regularFileCount: regularFileCount,
                aliasedDirectoriesSkipped: summary.aliasedDirectoriesSkipped,
                otherContainerMountsSkipped: summary.otherContainerMountsSkipped,
                issues: summary.issues
            )
        } catch {
            try? execute(database: database, sql: "ROLLBACK")
            throw error
        }
    }

    /// Copies the log back into the database file and shortens it to nothing.
    ///
    /// Best-effort by design: TRUNCATE blocks until every reader has finished
    /// and returns busy without truncating if one has not, and a busy
    /// checkpoint at the end of a stage is not a reason to fail the stage.
    /// The next one will do it.
    ///
    /// Called at the end of the long stages only. `inspectStagedExtents`
    /// deliberately does not, because it already commits once per page of at
    /// least 128 files: a truncate per page would rewrite the database file
    /// thousands of times in one scan, and the autocheckpoint budget covers
    /// that loop instead.
    private func truncateWriteAheadLog(database: OpaquePointer) {
        try? execute(
            database: database,
            sql: "PRAGMA wal_checkpoint(TRUNCATE)"
        )
    }

    /// Marks a staged scan as one that reached its last entry.
    ///
    /// Before the traversal committed in batches, the single transaction was
    /// the only thing that made a partial staged scan impossible. It is not
    /// any more, so this marker is what `precedingStagedScanID` reads to tell
    /// a finished generation from an abandoned one.
    private func markStagedScanComplete(
        database: OpaquePointer,
        scanID: Int64,
        completedAt: Date
    ) throws {
        let statement = try prepare(
            database: database,
            sql: "UPDATE staged_scans SET completed_at = ? WHERE id = ?"
        )
        defer { sqlite3_finalize(statement) }
        try check(
            sqlite3_bind_double(
                statement,
                1,
                completedAt.timeIntervalSince1970
            ),
            database: database
        )
        try bindInt64(scanID, at: 2, statement: statement)
        try stepDone(statement, database: database)
    }

    /// Keeps the newest complete generations and drops everything older.
    ///
    /// Nothing pruned these before, so every completed whole-volume scan
    /// added a full index generation permanently — on the owner's machine one
    /// generation measures in gigabytes. `history_samples` already had
    /// retention in `compactHistory`; staged scans had none.
    ///
    /// Two generations, not one: `precedingStagedScanID` needs the previous
    /// scan for `directoryGrowthFindings` and for `changed this week`.
    ///
    /// The cutoff is the oldest *complete* scan being kept, and everything
    /// with a lower id goes — abandoned generations included. Nothing newer
    /// is ever touched, which is what keeps a traversal running on another
    /// connection safe: now that the walk commits in batches it no longer
    /// holds the write lock for its whole duration, so a second scan can be
    /// in flight, and an in-flight scan always holds the highest id.
    ///
    /// Deliberately no VACUUM. It needs a full temporary copy of a multi-GB
    /// database and `PRAGMA temp_store = FILE` puts that copy on the volume
    /// the user is already short of space on. Freed pages are reused by the
    /// next scan, so the file plateaus at about one generation's size instead
    /// of growing by one for every scan ever run.
    private func pruneStagedScans(
        database: OpaquePointer,
        keeping keepCount: Int64
    ) throws {
        try execute(database: database, sql: "BEGIN IMMEDIATE")
        do {
            // Deferred to COMMIT because staged_entries carries a
            // self-referential (scan_id, parent_id) key: a bulk delete would
            // otherwise trip on whichever parent SQLite happened to remove
            // before its children.
            try execute(
                database: database,
                sql: "PRAGMA defer_foreign_keys = ON"
            )
            let obsolete = try obsoleteStagedScanIDs(
                database: database,
                keeping: keepCount
            )
            for obsoleteScanID in obsolete {
                // staged_segments references staged_entries with no cascade,
                // so the derived accounting has to go first.
                try clearStagedDerivedAccounting(
                    database: database,
                    scanID: obsoleteScanID
                )
                try deleteStagedSnapshotReferences(
                    database: database,
                    scanID: obsoleteScanID
                )
                // Deleting staged_entries fires staged_entries_search_delete,
                // which is the only thing that clears the FTS5 rows: the
                // virtual table has no foreign key to cascade from.
                for table in [
                    "staged_entries",
                    "staged_issues"
                ] {
                    let statement = try prepare(
                        database: database,
                        sql: "DELETE FROM \(table) WHERE scan_id = ?"
                    )
                    defer { sqlite3_finalize(statement) }
                    try bindInt64(
                        obsoleteScanID,
                        at: 1,
                        statement: statement
                    )
                    try stepDone(statement, database: database)
                }
                let statement = try prepare(
                    database: database,
                    sql: "DELETE FROM staged_scans WHERE id = ?"
                )
                defer { sqlite3_finalize(statement) }
                try bindInt64(obsoleteScanID, at: 1, statement: statement)
                try stepDone(statement, database: database)
            }
            try execute(database: database, sql: "COMMIT")
        } catch {
            try? execute(database: database, sql: "ROLLBACK")
            throw error
        }
    }

    private func obsoleteStagedScanIDs(
        database: OpaquePointer,
        keeping keepCount: Int64
    ) throws -> [Int64] {
        // When no scan has ever completed the subquery is NULL, `id < NULL`
        // is NULL, and nothing is selected — which is the right answer, not
        // an accident.
        let statement = try prepare(
            database: database,
            sql: """
                SELECT id FROM staged_scans
                WHERE id < (
                    SELECT MIN(id) FROM (
                        SELECT id FROM staged_scans
                        WHERE completed_at IS NOT NULL
                        ORDER BY id DESC LIMIT ?
                    )
                )
                ORDER BY id
                """
        )
        defer { sqlite3_finalize(statement) }
        try bindInt64(keepCount, at: 1, statement: statement)
        var ids: [Int64] = []
        while true {
            let code = sqlite3_step(statement)
            if code == SQLITE_DONE { break }
            guard code == SQLITE_ROW else {
                throw sqliteError(database: database, code: code)
            }
            ids.append(sqlite3_column_int64(statement, 0))
        }
        return ids
    }

    /// The number of staged generations the index is holding.
    ///
    /// Exists so retention can be asserted directly rather than inferred from
    /// a query that would also pass for the wrong reason.
    public func stagedScanCount() throws -> Int64 {
        guard let database = handle.pointer else {
            throw StorageIndexError.closed
        }
        let statement = try prepare(
            database: database,
            sql: "SELECT COUNT(*) FROM staged_scans"
        )
        defer { sqlite3_finalize(statement) }
        let code = sqlite3_step(statement)
        guard code == SQLITE_ROW else {
            throw sqliteError(database: database, code: code)
        }
        return sqlite3_column_int64(statement, 0)
    }

    /// Rewalks only changed directory subtrees, preserving extent maps for
    /// untouched files. Derived clone-family and freeable totals are cleared
    /// so callers must reduce them again before publishing the scan.
    public func refreshStagedSubtrees(
        scanID: Int64,
        roots requestedRoots: [URL]
    ) throws -> [StorageScanIssue] {
        guard let database = handle.pointer else {
            throw StorageIndexError.closed
        }
        let scanRoot = try stagedRootPath(
            database: database,
            scanID: scanID
        )
        let roots = Self.coalescedRefreshRoots(
            requestedRoots,
            inside: scanRoot
        )
        guard !roots.isEmpty else { return [] }

        try execute(database: database, sql: "BEGIN IMMEDIATE")
        do {
            try clearStagedDerivedAccounting(
                database: database,
                scanID: scanID
            )
            var nextID = try nextStagedEntryID(
                database: database,
                scanID: scanID
            )
            var issues: [StorageScanIssue] = []
            for root in roots {
                try removeStagedSubtree(
                    database: database,
                    scanID: scanID,
                    rootPath: root.path
                )
                guard FileManager.default.fileExists(atPath: root.path) else {
                    continue
                }
                let parentPath = root.deletingLastPathComponent().path
                let externalParentID = root.path == scanRoot
                    ? nil
                    : try stagedEntryID(
                        database: database,
                        scanID: scanID,
                        path: parentPath
                    )
                if root.path != scanRoot, externalParentID == nil {
                    throw StorageIndexError.invalidScan(
                        reason: "An incremental root has no indexed parent"
                    )
                }
                issues.append(contentsOf: try insertStagedSubtree(
                    database: database,
                    scanID: scanID,
                    rootURL: root,
                    externalParentID: externalParentID,
                    nextID: &nextID
                ))
            }
            try renumberStagedEntries(
                database: database,
                scanID: scanID
            )
            try appendTraversalIssues(
                database: database,
                scanID: scanID,
                issues: issues
            )
            try execute(database: database, sql: "COMMIT")
            truncateWriteAheadLog(database: database)
            return issues
        } catch {
            try? execute(database: database, sql: "ROLLBACK")
            throw error
        }
    }

    private static func coalescedRefreshRoots(
        _ roots: [URL],
        inside scanRoot: String
    ) -> [URL] {
        let normalized = Set(roots.map { $0.standardizedFileURL.path })
            .filter {
                $0 == scanRoot ||
                    $0.hasPrefix(scanRoot == "/" ? "/" : scanRoot + "/")
            }
            .sorted {
                if $0.count != $1.count { return $0.count < $1.count }
                return $0 < $1
            }
        var result: [String] = []
        for path in normalized {
            guard !result.contains(where: {
                path == $0 || path.hasPrefix($0 == "/" ? "/" : $0 + "/")
            }) else { continue }
            result.append(path)
        }
        return result.map(URL.init(fileURLWithPath:))
    }

    public func stagedEntryCount(scanID: Int64) throws -> Int64 {
        guard let database = handle.pointer else {
            throw StorageIndexError.closed
        }
        let statement = try prepare(
            database: database,
            sql: "SELECT COUNT(*) FROM staged_entries WHERE scan_id = ?"
        )
        defer { sqlite3_finalize(statement) }
        try bindInt64(scanID, at: 1, statement: statement)
        let code = sqlite3_step(statement)
        guard code == SQLITE_ROW else {
            throw sqliteError(database: database, code: code)
        }
        return sqlite3_column_int64(statement, 0)
    }

    public func stagedPhysicalExtentCount(scanID: Int64) throws -> Int64 {
        guard let database = handle.pointer else {
            throw StorageIndexError.closed
        }
        let statement = try prepare(
            database: database,
            sql: "SELECT COUNT(*) FROM staged_extents WHERE scan_id = ?"
        )
        defer { sqlite3_finalize(statement) }
        try bindInt64(scanID, at: 1, statement: statement)
        let code = sqlite3_step(statement)
        guard code == SQLITE_ROW else {
            throw sqliteError(database: database, code: code)
        }
        return sqlite3_column_int64(statement, 0)
    }

    public func stagedIssueCount(scanID: Int64) throws -> Int64 {
        guard let database = handle.pointer else {
            throw StorageIndexError.closed
        }
        let statement = try prepare(
            database: database,
            sql: "SELECT COUNT(*) FROM staged_issues WHERE scan_id = ?"
        )
        defer { sqlite3_finalize(statement) }
        try bindInt64(scanID, at: 1, statement: statement)
        let code = sqlite3_step(statement)
        guard code == SQLITE_ROW else {
            throw sqliteError(database: database, code: code)
        }
        return sqlite3_column_int64(statement, 0)
    }

    /// Reads a bounded page of staged paths, inspects only that page, and
    /// immediately writes its extent maps back to SQLite.
    /// The number of files inspected at once by default.
    ///
    /// Measured on a 16-core M3 Max against `/System/Library`: four readers
    /// took 11.3 s, eight took 9.4 s, and sixteen took 14.8 s. More is worse
    /// past this point, and not because of Swift's thread pool — running the
    /// same work on libdispatch, which grows its pool freely, was slower still.
    /// Concurrent metadata reads contend inside the filesystem, so the useful
    /// width is small and flat rather than proportional to the core count.
    ///
    /// Halving the core count lands on eight for this machine and stays
    /// sensible on smaller ones, where oversubscribing would cost more.
    public static var defaultConcurrentReads: Int {
        max(2, min(4, ProcessInfo.processInfo.activeProcessorCount / 4))
    }


    /// Inspects one page of files, `width` at a time.
    ///
    /// Nonisolated so the caller can run it detached: the point of the pipeline
    /// is that this overlaps the actor's SQLite write, which it cannot do from
    /// inside the actor.
    private nonisolated static func inspectPage(
        _ page: [StagedRegularFileRecord],
        width: Int
    ) async -> [StagedExtentOutcome] {
        await withTaskGroup(
            of: StagedExtentOutcome.self,
            returning: [StagedExtentOutcome].self
        ) { group in
            var iterator = page.makeIterator()

            func submitNext() {
                guard let record = iterator.next() else {
                    return
                }
                group.addTask {
                    do {
                        return .inspected(
                            record: record,
                            map: try FileExtentReader().inspect(record.entry)
                        )
                    } catch {
                        // Classified by type, not by reading the message back
                        // out of a string.
                        var changed = false
                        var refused = false
                        if case FileExtentError.identityChanged = error {
                            changed = true
                        } else if case let FileExtentError.cannotInspect(
                            _,
                            errorNumber
                        ) = error {
                            refused = StorageIndex.isRefusedBySystem(errorNumber)
                        }
                        return .failed(
                            record: record,
                            reason: String(describing: error),
                            changedDuringScan: changed,
                            refusedBySystem: refused
                        )
                    }
                }
            }

            for _ in 0..<min(width, page.count) {
                submitNext()
            }
            var values: [StagedExtentOutcome] = []
            values.reserveCapacity(page.count)
            for await outcome in group {
                values.append(outcome)
                submitNext()
            }
            return values.sorted { $0.entryID < $1.entryID }
        }
    }

    /// Whether the system refused the read outright.
    ///
    /// Named in one place so the traversal and the extent stage cannot drift
    /// apart on what counts as a refusal.
    public static func isRefusedBySystem(_ errorNumber: Int32) -> Bool {
        errorNumber == EACCES || errorNumber == EPERM
    }

    public func inspectStagedExtents(
        scanID: Int64,
        maximumConcurrentReads: Int = StorageIndex.defaultConcurrentReads
    ) async throws -> StagedExtentInspectionSummary {
        precondition(
            maximumConcurrentReads > 0,
            "At least one extent reader is required"
        )
        guard let database = handle.pointer else {
            throw StorageIndexError.closed
        }

        var lastEntryID: Int64 = -1
        var inspectedCount: UInt64 = 0
        var failedCount: UInt64 = 0
        var changedCount: UInt64 = 0
        var refusedCount: UInt64 = 0
        var nextIssueOrdinal = try nextStagedIssueOrdinal(
            database: database,
            scanID: scanID
        )

        // One page is inspected while the previous one is written.
        //
        // The write is a fifth of this phase and touches no file, so running it
        // against the next page's syscalls costs nothing and hides it. The
        // inspection runs detached because a plain `Task` here would inherit
        // this actor and serialise against the very write it is meant to
        // overlap.
        var inFlight: Task<[StagedExtentOutcome], Never>?

        while true {
            try Task.checkCancellation()
            let page = try loadStagedRegularFiles(
                database: database,
                scanID: scanID,
                after: lastEntryID,
                limit: max(128, maximumConcurrentReads * 32)
            )
            if let last = page.last {
                lastEntryID = last.id
            }

            let width = maximumConcurrentReads
            let nextInFlight: Task<[StagedExtentOutcome], Never>? =
                page.isEmpty
                ? nil
                : Task.detached(priority: .userInitiated) {
                    await StorageIndex.inspectPage(page, width: width)
                }

            guard let current = inFlight else {
                guard let nextInFlight else { break }
                inFlight = nextInFlight
                continue
            }
            let outcomes = await current.value
            inFlight = nextInFlight

            try execute(database: database, sql: "BEGIN IMMEDIATE")
            do {
                for outcome in outcomes {
                    switch outcome {
                    case let .inspected(record, map):
                        if try storeStagedExtentMap(
                            database: database,
                            scanID: scanID,
                            record: record,
                            map: map,
                            issueOrdinal: &nextIssueOrdinal
                        ) {
                            inspectedCount += 1
                        } else {
                            failedCount += 1
                        }
                    case let .failed(
                        record,
                        reason,
                        changedDuringScan,
                        refusedBySystem
                    ):
                        try markStagedExtentFailure(
                            database: database,
                            scanID: scanID,
                            record: record,
                            reason: reason,
                            issueOrdinal: &nextIssueOrdinal
                        )
                        if changedDuringScan {
                            changedCount += 1
                        } else if refusedBySystem {
                            refusedCount += 1
                        } else {
                            failedCount += 1
                        }
                    }
                }
                try execute(database: database, sql: "COMMIT")
            } catch {
                try? execute(database: database, sql: "ROLLBACK")
                throw error
            }
            if inFlight == nil {
                break
            }
        }

        return StagedExtentInspectionSummary(
            inspectedFileCount: inspectedCount,
            failedFileCount: failedCount,
            refusedBySystemCount: refusedCount,
            changedDuringScanCount: changedCount
        )
    }

    /// Reduces sorted extent events into disjoint reference segments, credits
    /// every segment once at its owners' LCA, then computes subtree totals.
    ///
    /// Memory is O(node count) in fixed-width arrays plus the maximum number
    /// of simultaneous owners of one physical byte; no path strings are loaded.
    public func reduceStagedAccounting(
        scanID: Int64
    ) throws -> StagedAccountingSummary {
        guard let database = handle.pointer else {
            throw StorageIndexError.closed
        }
        guard
            try stagedReductionRowCount(
                database: database,
                scanID: scanID
            ) == 0
        else {
            throw StorageIndexError.invalidScan(
                reason: "This staged scan has already been reduced"
            )
        }

        var nodes = try loadStagedNodeVectors(
            database: database,
            scanID: scanID
        )
        guard !nodes.parents.isEmpty else {
            throw StorageIndexError.invalidScan(
                reason: "The staged scan contains no root node"
            )
        }

        // Moved, not copied: see StagedNodeVectors. Three of these five
        // vectors are never read again once the reduction owns them, and on a
        // 3.77 million entry volume each redundant copy was tens of megabytes
        // against a 300 MB budget.
        var exclusive = nodes.directCredits
        nodes.directCredits = []
        var segmentCount: UInt64 = 0
        try execute(database: database, sql: "BEGIN IMMEDIATE")
        do {
            segmentCount = try reduceStagedExtentEvents(
                database: database,
                scanID: scanID,
                parents: nodes.parents,
                depths: nodes.depths,
                exclusive: &exclusive
            )

            // `subtree` is a genuine copy: `exclusive` is stored alongside
            // it further down, so both have to survive the roll-up.
            var subtree = exclusive
            var rawSubtree = nodes.allocatedBytes
            nodes.allocatedBytes = []
            var incompleteSubtree = nodes.unmappedRegularFiles
            nodes.unmappedRegularFiles = []
            if subtree.count > 1 {
                for index in stride(
                    from: subtree.count - 1,
                    through: 1,
                    by: -1
                ) {
                    let parent = nodes.parents[index]
                    guard parent >= 0, parent < Int64(subtree.count) else {
                        throw StorageIndexError.invalidScan(
                            reason: "A staged node has an invalid parent"
                        )
                    }
                    let parentIndex = Int(parent)
                    let (sum, overflow) = subtree[parentIndex]
                        .addingReportingOverflow(subtree[index])
                    guard !overflow else {
                        throw StorageIndexError.invalidScan(
                            reason: "A staged subtree total overflowed"
                        )
                    }
                    subtree[parentIndex] = sum

                    let (rawSum, rawOverflow) = rawSubtree[parentIndex]
                        .addingReportingOverflow(rawSubtree[index])
                    guard !rawOverflow else {
                        throw StorageIndexError.invalidScan(
                            reason: "A raw staged subtree total overflowed"
                        )
                    }
                    rawSubtree[parentIndex] = rawSum
                    incompleteSubtree[parentIndex] =
                        incompleteSubtree[parentIndex] ||
                        incompleteSubtree[index]
                }
            }
            try storeStagedNodeTotals(
                database: database,
                scanID: scanID,
                exclusive: exclusive,
                subtree: subtree,
                rawSubtree: rawSubtree,
                incompleteSubtree: incompleteSubtree
            )
            try execute(database: database, sql: "COMMIT")
            truncateWriteAheadLog(database: database)

            let measurement: Measurement<UInt64>
            if incompleteSubtree[0] {
                measurement = .notAttributable(
                    measured: rawSubtree[0],
                    explained: subtree[0]
                )
            } else {
                measurement = .known(
                    subtree[0],
                    source: .storageTreeAccounting
                )
            }
            return StagedAccountingSummary(
                scanID: scanID,
                nodeCount: UInt64(nodes.parents.count),
                physicalSegmentCount: segmentCount,
                sizeOnDisk: measurement
            )
        } catch {
            try? execute(database: database, sql: "ROLLBACK")
            throw error
        }
    }

    public func reduceStagedFreeableAccounting(
        scanID: Int64,
        snapshotInventory: Measurement<[LocalSnapshot]>,
        snapshotManifests: Measurement<[SnapshotExtentManifest]>,
        openFileIdentities: Measurement<Set<FileIdentity>>
    ) throws -> StagedFreeableAccountingSummary {
        guard let database = handle.pointer else {
            throw StorageIndexError.closed
        }

        let readiness = try stagedReferenceReadiness(
            database: database,
            scanID: scanID,
            snapshotInventory: snapshotInventory,
            snapshotManifests: snapshotManifests,
            openFileIdentities: openFileIdentities
        )
        switch readiness {
        case let .unavailable(reason):
            try markStagedFreeableNotPublished(
                database: database,
                scanID: scanID,
                reason: reason
            )
            return StagedFreeableAccountingSummary(
                scanID: scanID,
                freedIfDeleted: .notPublished(reason: reason)
            )
        case let .ready(manifests, openIdentities):
            try execute(database: database, sql: "BEGIN IMMEDIATE")
            do {
                try deleteStagedSnapshotReferences(
                    database: database,
                    scanID: scanID
                )
                try insertStagedSnapshotExtents(
                    database: database,
                    scanID: scanID,
                    manifests: manifests
                )
                try mergeStagedSnapshotExtents(
                    database: database,
                    scanID: scanID
                )
                try insertStagedOpenIdentities(
                    database: database,
                    scanID: scanID,
                    identities: openIdentities
                )
                try deleteStagedBlockedEntries(
                    database: database,
                    scanID: scanID
                )
                try populateStagedBlockedEntries(
                    database: database,
                    scanID: scanID
                )
                let rootFreeable = try computeAndStoreStagedFreeable(
                    database: database,
                    scanID: scanID
                )
                try execute(database: database, sql: "COMMIT")
                truncateWriteAheadLog(database: database)
                return StagedFreeableAccountingSummary(
                    scanID: scanID,
                    freedIfDeleted: .known(
                        rootFreeable,
                        source: .physicalReferenceAccounting
                    )
                )
            } catch {
                try? execute(database: database, sql: "ROLLBACK")
                throw error
            }
        }
    }

    /// Mounts snapshots read-only and streams their physical references
    /// directly into SQLite. Memory is bounded by the filesystem walker and a
    /// snapshot-name-sized ordinal dictionary, not by the number of extents.
    public func stageSnapshotReferences(
        scanID: Int64,
        volumeURL: URL,
        snapshots: [LocalSnapshot],
        mountPointURL: URL
    ) throws -> Measurement<[String]> {
        guard let database = handle.pointer else {
            throw StorageIndexError.closed
        }
        try execute(database: database, sql: "BEGIN IMMEDIATE")
        do {
            try deleteStagedSnapshotReferences(
                database: database,
                scanID: scanID
            )
            let statement = try prepare(
                database: database,
                sql: """
                    INSERT INTO staged_snapshot_extents(
                        scan_id, snapshot_name, ordinal,
                        device, device_offset, length
                    ) VALUES (?, ?, ?, ?, ?, ?)
                    """
            )
            defer { sqlite3_finalize(statement) }
            var nextOrdinal: [String: Int64] = [:]
            let coverage = try SnapshotManifestReader()
                .streamPhysicalExtents(
                    forVolumeAt: volumeURL,
                    snapshots: snapshots,
                    mountPointURL: mountPointURL
                ) { snapshotName, extent in
                    let (end, overflow) = extent.deviceOffset
                        .addingReportingOverflow(extent.length)
                    guard
                        !overflow,
                        extent.device <= UInt64(Int64.max),
                        extent.deviceOffset <= UInt64(Int64.max),
                        extent.length <= UInt64(Int64.max),
                        end <= UInt64(Int64.max)
                    else {
                        throw StorageIndexError.invalidScan(
                            reason: "A snapshot extent exceeds SQLite's ordered integer range"
                        )
                    }
                    let ordinal = nextOrdinal[snapshotName, default: 0]
                    nextOrdinal[snapshotName] = ordinal + 1
                    sqlite3_reset(statement)
                    sqlite3_clear_bindings(statement)
                    try bindInt64(scanID, at: 1, statement: statement)
                    try bindText(snapshotName, at: 2, statement: statement)
                    try bindInt64(ordinal, at: 3, statement: statement)
                    try bindUInt64(
                        extent.device,
                        at: 4,
                        statement: statement
                    )
                    try bindUInt64(
                        extent.deviceOffset,
                        at: 5,
                        statement: statement
                    )
                    try bindUInt64(
                        extent.length,
                        at: 6,
                        statement: statement
                    )
                    try stepDone(statement, database: database)
                }
            try execute(database: database, sql: "COMMIT")
            truncateWriteAheadLog(database: database)
            return coverage
        } catch {
            try? execute(database: database, sql: "ROLLBACK")
            throw error
        }
    }

    public func reduceStagedFreeableAccounting(
        scanID: Int64,
        snapshotInventory: Measurement<[LocalSnapshot]>,
        snapshotCoverage: Measurement<[String]>,
        openFileIdentities: Measurement<Set<FileIdentity>>
    ) throws -> StagedFreeableAccountingSummary {
        guard let database = handle.pointer else {
            throw StorageIndexError.closed
        }
        let readiness = try stagedReferenceReadiness(
            database: database,
            scanID: scanID,
            snapshotInventory: snapshotInventory,
            snapshotCoverage: snapshotCoverage,
            openFileIdentities: openFileIdentities
        )
        switch readiness {
        case let .unavailable(reason):
            try markStagedFreeableNotPublished(
                database: database,
                scanID: scanID,
                reason: reason
            )
            return StagedFreeableAccountingSummary(
                scanID: scanID,
                freedIfDeleted: .notPublished(reason: reason)
            )
        case let .ready(openIdentities):
            try execute(database: database, sql: "BEGIN IMMEDIATE")
            do {
                try mergeStagedSnapshotExtents(
                    database: database,
                    scanID: scanID
                )
                try insertStagedOpenIdentities(
                    database: database,
                    scanID: scanID,
                    identities: openIdentities
                )
                try deleteStagedBlockedEntries(
                    database: database,
                    scanID: scanID
                )
                try populateStagedBlockedEntries(
                    database: database,
                    scanID: scanID
                )
                let rootFreeable = try computeAndStoreStagedFreeable(
                    database: database,
                    scanID: scanID
                )
                try execute(database: database, sql: "COMMIT")
                truncateWriteAheadLog(database: database)
                return StagedFreeableAccountingSummary(
                    scanID: scanID,
                    freedIfDeleted: .known(
                        rootFreeable,
                        source: .physicalReferenceAccounting
                    )
                )
            } catch {
                try? execute(database: database, sql: "ROLLBACK")
                throw error
            }
        }
    }

    public func stagedChildren(
        scanID: Int64,
        parentID: Int64
    ) throws -> [StagedStorageNodeSummary] {
        guard let database = handle.pointer else {
            throw StorageIndexError.closed
        }
        let statement = try prepare(
            database: database,
            sql: """
                SELECT
                    entries.id, entries.parent_id,
                    entries.component, entries.path, entries.kind,
                    totals.subtree_size, totals.raw_subtree_size,
                    totals.on_disk_complete,
                    totals.subtree_freeable,
                    totals.freeable_state,
                    totals.freeable_reason
                FROM staged_entries AS entries
                JOIN staged_node_totals AS totals
                  ON totals.scan_id = entries.scan_id
                 AND totals.node_id = entries.id
                WHERE entries.scan_id = ? AND entries.parent_id = ?
                ORDER BY entries.component COLLATE NOCASE, entries.id
                """
        )
        defer { sqlite3_finalize(statement) }
        try bindInt64(scanID, at: 1, statement: statement)
        try bindInt64(parentID, at: 2, statement: statement)

        var rows: [StagedStorageNodeSummary] = []
        while true {
            let code = sqlite3_step(statement)
            if code == SQLITE_DONE {
                break
            }
            guard
                code == SQLITE_ROW,
                let nameText = sqlite3_column_text(statement, 2),
                let pathText = sqlite3_column_text(statement, 3)
            else {
                throw sqliteError(database: database, code: code)
            }
            let explained = UInt64(
                bitPattern: sqlite3_column_int64(statement, 5)
            )
            let raw = UInt64(
                bitPattern: sqlite3_column_int64(statement, 6)
            )
            let onDisk: Measurement<UInt64>
            if sqlite3_column_int(statement, 7) != 0 {
                onDisk = .known(
                    explained,
                    source: .storageTreeAccounting
                )
            } else {
                onDisk = .notAttributable(
                    measured: raw,
                    explained: explained
                )
            }
            let freeable: Measurement<UInt64>
            switch sqlite3_column_int(statement, 9) {
            case 0:
                freeable = .known(
                    UInt64(
                        bitPattern: sqlite3_column_int64(statement, 8)
                    ),
                    source: .physicalReferenceAccounting
                )
            case 1:
                let reason = sqlite3_column_text(statement, 10).map {
                    String(cString: $0)
                } ?? "Physical references have not been reduced"
                freeable = .notPublished(reason: reason)
            default:
                freeable = .notPublished(
                    reason: "The index contains an invalid freeable state"
                )
            }
            rows.append(
                StagedStorageNodeSummary(
                    id: sqlite3_column_int64(statement, 0),
                    parentID: sqlite3_column_int64(statement, 1),
                    name: String(cString: nameText),
                    path: String(cString: pathText),
                    kind: try storageKind(
                        code: sqlite3_column_int(statement, 4)
                    ),
                    sizeOnDisk: onDisk,
                    freedIfDeleted: freeable
                )
            )
        }
        return rows
    }

    public func searchStagedEntries(
        scanID: Int64,
        query: StoragePaletteQuery,
        now: Date = Date(),
        limit: Int = 30
    ) throws -> Measurement<[StagedStorageNodeSummary]> {
        guard let database = handle.pointer else {
            throw StorageIndexError.closed
        }
        guard (1...100).contains(limit) else {
            throw StorageIndexError.invalidScan(
                reason: "Palette result limit must be between 1 and 100"
            )
        }

        let projection = """
            SELECT
                entries.id, entries.parent_id,
                entries.component, entries.path, entries.kind,
                totals.subtree_size, totals.raw_subtree_size,
                totals.on_disk_complete,
                totals.subtree_freeable,
                totals.freeable_state,
                totals.freeable_reason
            FROM staged_entries AS entries
            JOIN staged_node_totals AS totals
              ON totals.scan_id = entries.scan_id
             AND totals.node_id = entries.id
            """
        let sql: String
        var textBinding: String?
        var integerBinding: UInt64?
        var previousScanID: Int64?

        switch query {
        case let .text(text):
            let escaped = text.replacingOccurrences(of: "\"", with: "\"\"")
            textBinding = "\"\(escaped)\"*"
            sql = projection + """

                JOIN staged_path_fts AS search
                  ON search.scan_id = entries.scan_id
                 AND search.entry_id = entries.id
                WHERE entries.scan_id = ?
                  AND staged_path_fts MATCH ?
                ORDER BY rank, totals.subtree_size DESC, entries.id
                LIMIT ?
                """
        case let .minimumAllocatedBytes(bytes):
            integerBinding = bytes
            sql = projection + """

                WHERE entries.scan_id = ?
                  AND totals.subtree_size > ?
                ORDER BY totals.subtree_size DESC, entries.id
                LIMIT ?
                """
        case .clones:
            sql = projection + """

                WHERE entries.scan_id = ?
                  AND entries.clone_id IS NOT NULL
                  AND entries.clone_id != 0
                ORDER BY totals.subtree_size DESC, entries.id
                LIMIT ?
                """
        case .changedThisWeek:
            let previous = try precedingStagedScanID(
                database: database,
                before: scanID,
                earliest: now.addingTimeInterval(-7 * 24 * 60 * 60)
            )
            guard let previous else {
                return .notPublished(
                    reason: "A preceding scan from the last seven days is required"
                )
            }
            previousScanID = previous
            sql = projection + """

                JOIN staged_entries AS prior
                  ON prior.scan_id = ?
                 AND prior.path = entries.path
                JOIN staged_node_totals AS prior_totals
                  ON prior_totals.scan_id = prior.scan_id
                 AND prior_totals.node_id = prior.id
                WHERE entries.scan_id = ?
                  AND totals.subtree_size != prior_totals.subtree_size
                ORDER BY ABS(totals.subtree_size - prior_totals.subtree_size) DESC,
                         entries.id
                LIMIT ?
                """
        }

        let statement = try prepare(database: database, sql: sql)
        defer { sqlite3_finalize(statement) }
        var binding: Int32 = 1
        if let previousScanID {
            try bindInt64(previousScanID, at: binding, statement: statement)
            binding += 1
        }
        try bindInt64(scanID, at: binding, statement: statement)
        binding += 1
        if let textBinding {
            try bindText(textBinding, at: binding, statement: statement)
            binding += 1
        } else if let integerBinding {
            try bindUInt64(integerBinding, at: binding, statement: statement)
            binding += 1
        }
        try bindInt64(Int64(limit), at: binding, statement: statement)

        var rows: [StagedStorageNodeSummary] = []
        while true {
            let code = sqlite3_step(statement)
            if code == SQLITE_DONE { break }
            guard code == SQLITE_ROW else {
                throw sqliteError(database: database, code: code)
            }
            rows.append(try stagedSummary(statement: statement))
        }
        return .known(rows, source: .storageIndexFTS5)
    }

    public func directoryGrowthFindings(
        scanID: Int64,
        minimumGrowthBytes: UInt64 = 20_000_000_000,
        within interval: TimeInterval = 24 * 60 * 60,
        now: Date = Date()
    ) throws -> Measurement<[DirectoryGrowthFinding]> {
        guard let database = handle.pointer else {
            throw StorageIndexError.closed
        }
        guard minimumGrowthBytes <= UInt64(Int64.max), interval > 0 else {
            throw StorageIndexError.invalidScan(
                reason: "The directory growth threshold is invalid"
            )
        }
        guard let previousScanID = try precedingStagedScanID(
            database: database,
            before: scanID,
            earliest: now.addingTimeInterval(-interval)
        ) else {
            return .notPublished(
                reason: "Two completed scans no more than 24 hours apart are required"
            )
        }
        let statement = try prepare(
            database: database,
            sql: """
                SELECT entries.path,
                       totals.subtree_size - prior_totals.subtree_size
                FROM staged_entries AS entries
                JOIN staged_node_totals AS totals
                  ON totals.scan_id = entries.scan_id
                 AND totals.node_id = entries.id
                JOIN staged_entries AS prior
                  ON prior.scan_id = ?
                 AND prior.path = entries.path
                 AND prior.kind = 2
                JOIN staged_node_totals AS prior_totals
                  ON prior_totals.scan_id = prior.scan_id
                 AND prior_totals.node_id = prior.id
                WHERE entries.scan_id = ?
                  AND entries.kind = 2
                  AND totals.on_disk_complete = 1
                  AND prior_totals.on_disk_complete = 1
                  AND totals.subtree_size - prior_totals.subtree_size >= ?
                ORDER BY totals.subtree_size - prior_totals.subtree_size DESC,
                         entries.id
                """
        )
        defer { sqlite3_finalize(statement) }
        try bindInt64(previousScanID, at: 1, statement: statement)
        try bindInt64(scanID, at: 2, statement: statement)
        try bindInt64(
            Int64(minimumGrowthBytes),
            at: 3,
            statement: statement
        )
        var findings: [DirectoryGrowthFinding] = []
        while true {
            let code = sqlite3_step(statement)
            if code == SQLITE_DONE { break }
            guard code == SQLITE_ROW,
                  let pathText = sqlite3_column_text(statement, 0) else {
                throw sqliteError(database: database, code: code)
            }
            findings.append(
                DirectoryGrowthFinding(
                    path: String(cString: pathText),
                    growthBytes: UInt64(
                        sqlite3_column_int64(statement, 1)
                    )
                )
            )
        }
        return .known(findings, source: .persistedDirectoryGrowthDelta)
    }

    /// The sole scan-pair selector: `directoryGrowthFindings` and
    /// `searchStagedEntries(.changedThisWeek)` both come through here, and
    /// every other staged query takes an explicit scan id from a completed
    /// `StoragePresentation`.
    ///
    /// The `completed_at` filter is load-bearing. Now that the traversal
    /// commits in batches, an interrupted scan leaves committed entry rows
    /// but no `staged_node_totals` — and both callers join those totals, so
    /// choosing a partial scan as `previous` would return an empty result
    /// set. The product would then say *nothing changed* where it should say
    /// *not published*.
    private func precedingStagedScanID(
        database: OpaquePointer,
        before scanID: Int64,
        earliest: Date
    ) throws -> Int64? {
        let statement = try prepare(
            database: database,
            sql: """
                SELECT id FROM staged_scans
                WHERE id < ? AND started_at >= ?
                    AND completed_at IS NOT NULL
                ORDER BY id DESC LIMIT 1
                """
        )
        defer { sqlite3_finalize(statement) }
        try bindInt64(scanID, at: 1, statement: statement)
        try check(
            sqlite3_bind_double(statement, 2, earliest.timeIntervalSince1970),
            database: database
        )
        let code = sqlite3_step(statement)
        if code == SQLITE_DONE { return nil }
        guard code == SQLITE_ROW else {
            throw sqliteError(database: database, code: code)
        }
        return sqlite3_column_int64(statement, 0)
    }

    private func stagedSummary(
        statement: OpaquePointer
    ) throws -> StagedStorageNodeSummary {
        guard let nameText = sqlite3_column_text(statement, 2),
              let pathText = sqlite3_column_text(statement, 3) else {
            throw StorageIndexError.invalidScan(reason: "A palette row has no path")
        }
        let explained = UInt64(bitPattern: sqlite3_column_int64(statement, 5))
        let raw = UInt64(bitPattern: sqlite3_column_int64(statement, 6))
        let onDisk: Measurement<UInt64> = sqlite3_column_int(statement, 7) != 0
            ? .known(explained, source: .storageTreeAccounting)
            : .notAttributable(measured: raw, explained: explained)
        let freeable: Measurement<UInt64>
        if sqlite3_column_int(statement, 9) == 0 {
            freeable = .known(
                UInt64(bitPattern: sqlite3_column_int64(statement, 8)),
                source: .physicalReferenceAccounting
            )
        } else {
            let reason = sqlite3_column_text(statement, 10).map(String.init(cString:))
                ?? "Physical references have not been reduced"
            freeable = .notPublished(reason: reason)
        }
        return StagedStorageNodeSummary(
            id: sqlite3_column_int64(statement, 0),
            parentID: sqlite3_column_type(statement, 1) == SQLITE_NULL
                ? nil : sqlite3_column_int64(statement, 1),
            name: String(cString: nameText),
            path: String(cString: pathText),
            kind: try storageKind(code: sqlite3_column_int(statement, 4)),
            sizeOnDisk: onDisk,
            freedIfDeleted: freeable
        )
    }

    /// Rehydrates exact staged metadata and both rendered numbers for a
    /// reclaim dry run. Paths are matched exactly; prefix matching belongs to
    /// the validated recipe layer.
    public func stagedReclaimEntries(
        scanID: Int64,
        paths: [String]
    ) throws -> [StorageEntry] {
        guard let database = handle.pointer else {
            throw StorageIndexError.closed
        }
        let statement = try prepare(
            database: database,
            sql: """
                SELECT
                    entries.path, entries.kind,
                    entries.device, entries.inode,
                    entries.hard_link_count, entries.logical_size,
                    entries.allocated_size,
                    entries.modified_seconds, entries.modified_nanoseconds,
                    entries.is_dataless,
                    totals.subtree_size, totals.raw_subtree_size,
                    totals.on_disk_complete,
                    totals.subtree_freeable,
                    totals.freeable_state,
                    totals.freeable_reason
                FROM staged_entries AS entries
                JOIN staged_node_totals AS totals
                  ON totals.scan_id = entries.scan_id
                 AND totals.node_id = entries.id
                WHERE entries.scan_id = ? AND entries.path = ?
                """
        )
        defer { sqlite3_finalize(statement) }
        var entries: [StorageEntry] = []
        for path in paths {
            sqlite3_reset(statement)
            sqlite3_clear_bindings(statement)
            try bindInt64(scanID, at: 1, statement: statement)
            try bindText(path, at: 2, statement: statement)
            let code = sqlite3_step(statement)
            if code == SQLITE_DONE { continue }
            guard code == SQLITE_ROW,
                  let pathText = sqlite3_column_text(statement, 0) else {
                throw sqliteError(database: database, code: code)
            }
            let explained = UInt64(
                bitPattern: sqlite3_column_int64(statement, 10)
            )
            let raw = UInt64(
                bitPattern: sqlite3_column_int64(statement, 11)
            )
            let onDisk: Measurement<UInt64> =
                sqlite3_column_int(statement, 12) != 0
                ? .known(explained, source: .storageTreeAccounting)
                : .notAttributable(measured: raw, explained: explained)
            let freeable: Measurement<UInt64>
            if sqlite3_column_int(statement, 14) == 0 {
                freeable = .known(
                    UInt64(bitPattern: sqlite3_column_int64(statement, 13)),
                    source: .physicalReferenceAccounting
                )
            } else {
                let reason = sqlite3_column_text(statement, 15).map {
                    String(cString: $0)
                } ?? "Physical references have not been reduced"
                freeable = .notPublished(reason: reason)
            }
            entries.append(
                StorageEntry(
                    path: String(cString: pathText),
                    kind: try storageKind(
                        code: sqlite3_column_int(statement, 1)
                    ),
                    identity: FileIdentity(
                        device: UInt64(
                            bitPattern: sqlite3_column_int64(statement, 2)
                        ),
                        inode: UInt64(
                            bitPattern: sqlite3_column_int64(statement, 3)
                        )
                    ),
                    hardLinkCount: UInt64(
                        bitPattern: sqlite3_column_int64(statement, 4)
                    ),
                    isDataless: sqlite3_column_int(statement, 9) != 0,
                    logicalSize: .known(
                        UInt64(
                            bitPattern: sqlite3_column_int64(statement, 5)
                        ),
                        source: .statLogicalSize
                    ),
                    sizeOnDisk: onDisk,
                    modificationTime: .known(
                        FileTimestamp(
                            secondsSinceEpoch: sqlite3_column_int64(
                                statement,
                                7
                            ),
                            nanoseconds: Int32(
                                sqlite3_column_int(statement, 8)
                            )
                        ),
                        source: .statModificationTime
                    ),
                    freedIfDeleted: freeable
                )
            )
        }
        return entries
    }

    public func recordHistory(
        _ sample: StorageHistorySample,
        now: Date = Date(),
        coalescingWithin interval: TimeInterval? = nil
    ) throws {
        guard let database = handle.pointer else {
            throw StorageIndexError.closed
        }
        let data = try JSONEncoder().encode(sample)
        guard let payload = String(data: data, encoding: .utf8) else {
            throw StorageIndexError.invalidScan(
                reason: "A history sample could not be encoded"
            )
        }
        let recentID: Int64? = try interval.flatMap { interval in
            guard interval > 0 else { return nil }
            let statement = try prepare(
                database: database,
                sql: """
                    SELECT id, wall_timestamp FROM history_samples
                    WHERE volume_path = ?
                    ORDER BY wall_timestamp DESC, id DESC LIMIT 1
                    """
            )
            defer { sqlite3_finalize(statement) }
            try bindText(sample.volumePath, at: 1, statement: statement)
            let code = sqlite3_step(statement)
            if code == SQLITE_DONE { return nil }
            guard code == SQLITE_ROW else {
                throw sqliteError(database: database, code: code)
            }
            let timestamp = sqlite3_column_double(statement, 1)
            return sample.wallTimestamp.timeIntervalSince1970 - timestamp < interval
                ? sqlite3_column_int64(statement, 0)
                : nil
        }
        let insert: OpaquePointer
        if recentID == nil {
            insert = try prepare(
                database: database,
                sql: """
                    INSERT INTO history_samples(
                        wall_timestamp, monotonic_ticks, volume_path, payload
                    ) VALUES (?, ?, ?, ?)
                    """
            )
        } else {
            insert = try prepare(
                database: database,
                sql: """
                    UPDATE history_samples
                    SET wall_timestamp = ?, monotonic_ticks = ?,
                        volume_path = ?, payload = ?
                    WHERE id = ?
                    """
            )
        }
        defer { sqlite3_finalize(insert) }
        try check(
            sqlite3_bind_double(
                insert,
                1,
                sample.wallTimestamp.timeIntervalSince1970
            ),
            database: database
        )
        try bindInt64(
            Int64(bitPattern: sample.monotonicTicks),
            at: 2,
            statement: insert
        )
        try bindText(sample.volumePath, at: 3, statement: insert)
        try bindText(payload, at: 4, statement: insert)
        if let recentID {
            try bindInt64(recentID, at: 5, statement: insert)
        }
        try stepDone(insert, database: database)
        try compactHistory(database: database, now: now)
    }

    public func historySamples(
        volumePath: String
    ) throws -> [StorageHistorySample] {
        guard let database = handle.pointer else {
            throw StorageIndexError.closed
        }
        let statement = try prepare(
            database: database,
            sql: """
                SELECT payload FROM history_samples
                WHERE volume_path = ?
                ORDER BY wall_timestamp, id
                """
        )
        defer { sqlite3_finalize(statement) }
        try bindText(volumePath, at: 1, statement: statement)
        var samples: [StorageHistorySample] = []
        while true {
            let code = sqlite3_step(statement)
            if code == SQLITE_DONE { break }
            guard code == SQLITE_ROW,
                  let text = sqlite3_column_text(statement, 0) else {
                throw sqliteError(database: database, code: code)
            }
            samples.append(
                try JSONDecoder().decode(
                    StorageHistorySample.self,
                    from: Data(String(cString: text).utf8)
                )
            )
        }
        return samples
    }

    private func compactHistory(
        database: OpaquePointer,
        now: Date
    ) throws {
        let sevenDays = now.addingTimeInterval(-7 * 86_400)
            .timeIntervalSince1970
        let ninetyDays = now.addingTimeInterval(-90 * 86_400)
            .timeIntervalSince1970
        let statement = try prepare(
            database: database,
            sql: """
                DELETE FROM history_samples
                WHERE id NOT IN (
                    SELECT id FROM history_samples
                    WHERE wall_timestamp >= ?
                    UNION
                    SELECT MAX(id) FROM history_samples
                    WHERE wall_timestamp < ? AND wall_timestamp >= ?
                    GROUP BY volume_path,
                        strftime('%Y-%m-%dT%H', wall_timestamp, 'unixepoch')
                    UNION
                    SELECT MAX(id) FROM history_samples
                    WHERE wall_timestamp < ?
                    GROUP BY volume_path,
                        strftime('%Y-%m-%d', wall_timestamp, 'unixepoch')
                )
                """
        )
        defer { sqlite3_finalize(statement) }
        for (index, value) in [
            sevenDays,
            sevenDays,
            ninetyDays,
            ninetyDays
        ].enumerated() {
            try check(
                sqlite3_bind_double(statement, Int32(index + 1), value),
                database: database
            )
        }
        try stepDone(statement, database: database)
    }

    private static let schemaSQL = """
        CREATE TABLE IF NOT EXISTS scans (
            id INTEGER PRIMARY KEY,
            root_path TEXT NOT NULL,
            started_at REAL NOT NULL,
            complete INTEGER NOT NULL CHECK (complete IN (0, 1)),
            snapshot_state INTEGER NOT NULL,
            snapshot_reason TEXT
        );

        CREATE TABLE IF NOT EXISTS components (
            scan_id INTEGER NOT NULL REFERENCES scans(id) ON DELETE CASCADE,
            id INTEGER NOT NULL,
            value TEXT NOT NULL,
            PRIMARY KEY (scan_id, id)
        ) WITHOUT ROWID;

        CREATE TABLE IF NOT EXISTS nodes (
            scan_id INTEGER NOT NULL REFERENCES scans(id) ON DELETE CASCADE,
            id INTEGER NOT NULL,
            parent_id INTEGER,
            component_id INTEGER NOT NULL,
            kind INTEGER NOT NULL,
            device INTEGER NOT NULL,
            inode INTEGER NOT NULL,
            hard_link_count INTEGER NOT NULL,
            logical_size INTEGER NOT NULL,
            allocated_size INTEGER NOT NULL,
            exclusive_size INTEGER NOT NULL,
            subtree_size INTEGER NOT NULL,
            modified_seconds INTEGER NOT NULL,
            modified_nanoseconds INTEGER NOT NULL,
            is_dataless INTEGER NOT NULL CHECK (is_dataless IN (0, 1)),
            clone_id INTEGER,
            clone_reference_count INTEGER,
            PRIMARY KEY (scan_id, id),
            FOREIGN KEY (scan_id, parent_id)
                REFERENCES nodes(scan_id, id),
            FOREIGN KEY (scan_id, component_id)
                REFERENCES components(scan_id, id)
        ) WITHOUT ROWID;

        CREATE INDEX IF NOT EXISTS nodes_by_identity
            ON nodes(scan_id, device, inode);
        CREATE INDEX IF NOT EXISTS nodes_by_parent
            ON nodes(scan_id, parent_id);
        CREATE INDEX IF NOT EXISTS nodes_by_clone
            ON nodes(scan_id, clone_id)
            WHERE clone_id IS NOT NULL AND clone_id != 0;

        CREATE TABLE IF NOT EXISTS families (
            scan_id INTEGER NOT NULL REFERENCES scans(id) ON DELETE CASCADE,
            id INTEGER NOT NULL,
            credited_node_id INTEGER NOT NULL,
            size_on_disk INTEGER NOT NULL,
            outside_state INTEGER NOT NULL,
            outside_value INTEGER,
            freeable_state INTEGER NOT NULL,
            freeable_measured INTEGER,
            freeable_explained INTEGER,
            PRIMARY KEY (scan_id, id),
            FOREIGN KEY (scan_id, credited_node_id)
                REFERENCES nodes(scan_id, id)
        ) WITHOUT ROWID;

        CREATE TABLE IF NOT EXISTS family_members (
            scan_id INTEGER NOT NULL,
            family_id INTEGER NOT NULL,
            node_id INTEGER NOT NULL,
            PRIMARY KEY (scan_id, family_id, node_id),
            FOREIGN KEY (scan_id, family_id)
                REFERENCES families(scan_id, id) ON DELETE CASCADE,
            FOREIGN KEY (scan_id, node_id)
                REFERENCES nodes(scan_id, id)
        ) WITHOUT ROWID;

        CREATE TABLE IF NOT EXISTS snapshots (
            scan_id INTEGER NOT NULL REFERENCES scans(id) ON DELETE CASCADE,
            id INTEGER NOT NULL,
            name TEXT NOT NULL,
            PRIMARY KEY (scan_id, id)
        ) WITHOUT ROWID;

        CREATE TABLE IF NOT EXISTS snapshot_extents (
            scan_id INTEGER NOT NULL,
            snapshot_id INTEGER NOT NULL,
            ordinal INTEGER NOT NULL,
            device INTEGER NOT NULL,
            device_offset INTEGER NOT NULL,
            length INTEGER NOT NULL,
            PRIMARY KEY (scan_id, snapshot_id, ordinal),
            FOREIGN KEY (scan_id, snapshot_id)
                REFERENCES snapshots(scan_id, id) ON DELETE CASCADE
        ) WITHOUT ROWID;

        CREATE TABLE IF NOT EXISTS staged_scans (
            id INTEGER PRIMARY KEY,
            root_path TEXT NOT NULL,
            scope INTEGER NOT NULL CHECK (scope IN (0, 1)),
            started_at REAL NOT NULL,
            completed_at REAL
        );

        CREATE TABLE IF NOT EXISTS staged_entries (
            scan_id INTEGER NOT NULL
                REFERENCES staged_scans(id) ON DELETE CASCADE,
            id INTEGER NOT NULL,
            parent_id INTEGER,
            component TEXT NOT NULL,
            path TEXT NOT NULL,
            kind INTEGER NOT NULL,
            device INTEGER NOT NULL,
            inode INTEGER NOT NULL,
            hard_link_count INTEGER NOT NULL,
            logical_size INTEGER NOT NULL,
            allocated_size INTEGER NOT NULL,
            modified_seconds INTEGER NOT NULL,
            modified_nanoseconds INTEGER NOT NULL,
            is_dataless INTEGER NOT NULL CHECK (is_dataless IN (0, 1)),
            extent_state INTEGER NOT NULL,
            clone_id INTEGER,
            clone_reference_count INTEGER,
            allocation_block_size INTEGER,
            PRIMARY KEY (scan_id, id),
            UNIQUE (scan_id, path),
            FOREIGN KEY (scan_id, parent_id)
                REFERENCES staged_entries(scan_id, id)
        ) WITHOUT ROWID;

        CREATE INDEX IF NOT EXISTS staged_entries_by_kind
            ON staged_entries(scan_id, kind, id);
        CREATE INDEX IF NOT EXISTS staged_entries_by_identity
            ON staged_entries(scan_id, device, inode);

        CREATE VIRTUAL TABLE IF NOT EXISTS staged_path_fts USING fts5(
            scan_id UNINDEXED,
            entry_id UNINDEXED,
            component,
            path,
            tokenize = "unicode61 tokenchars '_-'"
        );

        CREATE TRIGGER IF NOT EXISTS staged_entries_search_delete
        AFTER DELETE ON staged_entries BEGIN
            DELETE FROM staged_path_fts
            WHERE scan_id = old.scan_id AND entry_id = old.id;
        END;

        CREATE TABLE IF NOT EXISTS staged_extents (
            scan_id INTEGER NOT NULL,
            entry_id INTEGER NOT NULL,
            ordinal INTEGER NOT NULL,
            logical_offset INTEGER NOT NULL,
            device_offset INTEGER NOT NULL,
            length INTEGER NOT NULL,
            PRIMARY KEY (scan_id, entry_id, ordinal),
            FOREIGN KEY (scan_id, entry_id)
                REFERENCES staged_entries(scan_id, id) ON DELETE CASCADE
        ) WITHOUT ROWID;

        CREATE INDEX IF NOT EXISTS staged_extents_by_device_offset
            ON staged_extents(scan_id, device_offset);

        CREATE TABLE IF NOT EXISTS staged_issues (
            scan_id INTEGER NOT NULL
                REFERENCES staged_scans(id) ON DELETE CASCADE,
            ordinal INTEGER NOT NULL,
            path TEXT NOT NULL,
            stage INTEGER NOT NULL,
            error_number INTEGER,
            reason TEXT NOT NULL,
            PRIMARY KEY (scan_id, ordinal)
        ) WITHOUT ROWID;

        CREATE TABLE IF NOT EXISTS staged_segments (
            scan_id INTEGER NOT NULL,
            id INTEGER NOT NULL,
            device INTEGER NOT NULL,
            device_offset INTEGER NOT NULL,
            length INTEGER NOT NULL,
            credited_node_id INTEGER NOT NULL,
            PRIMARY KEY (scan_id, id),
            FOREIGN KEY (scan_id, credited_node_id)
                REFERENCES staged_entries(scan_id, id)
        ) WITHOUT ROWID;

        CREATE TABLE IF NOT EXISTS staged_segment_owners (
            scan_id INTEGER NOT NULL,
            segment_id INTEGER NOT NULL,
            entry_id INTEGER NOT NULL,
            PRIMARY KEY (scan_id, segment_id, entry_id),
            FOREIGN KEY (scan_id, segment_id)
                REFERENCES staged_segments(scan_id, id) ON DELETE CASCADE,
            FOREIGN KEY (scan_id, entry_id)
                REFERENCES staged_entries(scan_id, id)
        ) WITHOUT ROWID;

        CREATE INDEX IF NOT EXISTS staged_segment_owners_by_entry
            ON staged_segment_owners(scan_id, entry_id, segment_id);

        CREATE TABLE IF NOT EXISTS staged_node_totals (
            scan_id INTEGER NOT NULL,
            node_id INTEGER NOT NULL,
            exclusive_size INTEGER NOT NULL,
            subtree_size INTEGER NOT NULL,
            raw_subtree_size INTEGER NOT NULL,
            on_disk_complete INTEGER NOT NULL
                CHECK (on_disk_complete IN (0, 1)),
            exclusive_freeable INTEGER,
            subtree_freeable INTEGER,
            freeable_state INTEGER NOT NULL DEFAULT 1,
            freeable_reason TEXT,
            PRIMARY KEY (scan_id, node_id),
            FOREIGN KEY (scan_id, node_id)
                REFERENCES staged_entries(scan_id, id) ON DELETE CASCADE
        ) WITHOUT ROWID;

        CREATE TABLE IF NOT EXISTS staged_snapshot_extents (
            scan_id INTEGER NOT NULL,
            snapshot_name TEXT NOT NULL,
            ordinal INTEGER NOT NULL,
            device INTEGER NOT NULL,
            device_offset INTEGER NOT NULL,
            length INTEGER NOT NULL,
            PRIMARY KEY (scan_id, snapshot_name, ordinal),
            FOREIGN KEY (scan_id)
                REFERENCES staged_scans(id) ON DELETE CASCADE
        ) WITHOUT ROWID;

        CREATE INDEX IF NOT EXISTS staged_snapshot_extents_by_device
            ON staged_snapshot_extents(scan_id, device, device_offset);

        CREATE TABLE IF NOT EXISTS staged_snapshot_segments (
            scan_id INTEGER NOT NULL,
            id INTEGER NOT NULL,
            device INTEGER NOT NULL,
            device_offset INTEGER NOT NULL,
            length INTEGER NOT NULL,
            PRIMARY KEY (scan_id, id),
            FOREIGN KEY (scan_id)
                REFERENCES staged_scans(id) ON DELETE CASCADE
        ) WITHOUT ROWID;

        CREATE TABLE IF NOT EXISTS staged_open_identities (
            scan_id INTEGER NOT NULL,
            device INTEGER NOT NULL,
            inode INTEGER NOT NULL,
            PRIMARY KEY (scan_id, device, inode),
            FOREIGN KEY (scan_id)
                REFERENCES staged_scans(id) ON DELETE CASCADE
        ) WITHOUT ROWID;

        CREATE TABLE IF NOT EXISTS staged_blocked_entries (
            scan_id INTEGER NOT NULL,
            entry_id INTEGER NOT NULL,
            reason INTEGER NOT NULL,
            PRIMARY KEY (scan_id, entry_id, reason),
            FOREIGN KEY (scan_id, entry_id)
                REFERENCES staged_entries(scan_id, id) ON DELETE CASCADE
        ) WITHOUT ROWID;

        CREATE TABLE IF NOT EXISTS history_samples (
            id INTEGER PRIMARY KEY,
            wall_timestamp REAL NOT NULL,
            monotonic_ticks INTEGER NOT NULL,
            volume_path TEXT NOT NULL,
            payload TEXT NOT NULL
        );

        CREATE INDEX IF NOT EXISTS history_samples_by_volume_time
            ON history_samples(volume_path, wall_timestamp, id);

        CREATE TABLE IF NOT EXISTS diagnostic_values (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL
        ) WITHOUT ROWID;
        """
}

private final class DatabaseHandle: @unchecked Sendable {
    var pointer: OpaquePointer?

    init(_ pointer: OpaquePointer) {
        self.pointer = pointer
    }

    /// An index dropped without `close()` must still truncate its log, or the
    /// whole reclaim depends on every caller remembering to close.
    deinit {
        if let pointer {
            try? execute(
                database: pointer,
                sql: "PRAGMA wal_checkpoint(TRUNCATE)"
            )
            sqlite3_close_v2(pointer)
        }
    }
}

private struct StagedRegularFileRecord: Sendable {
    let id: Int64
    let entry: StorageEntry
}

private enum StagedExtentOutcome: Sendable {
    case inspected(
        record: StagedRegularFileRecord,
        map: FileExtentMap
    )
    case failed(
        record: StagedRegularFileRecord,
        reason: String,
        changedDuringScan: Bool,
        refusedBySystem: Bool
    )

    var entryID: Int64 {
        switch self {
        case let .inspected(record, _), let .failed(record, _, _, _):
            return record.id
        }
    }
}

/// The vectors are `var` so the reduction can take ownership of one and drop
/// this struct's reference to it. Swift copies an array on write while two
/// references exist, so a plain `var mine = nodes.allocatedBytes` followed by a
/// mutation duplicates the whole vector. Emptying the original first leaves the
/// new binding uniquely referenced and the mutation happens in place.
private struct StagedNodeVectors {
    var parents: [Int64]
    var depths: [UInt32]
    var directCredits: [UInt64]
    var allocatedBytes: [UInt64]
    var unmappedRegularFiles: [Bool]
}

private enum StagedReferenceReadiness {
    case ready(
        manifests: [SnapshotExtentManifest],
        openIdentities: Set<FileIdentity>
    )
    case unavailable(reason: String)
}

private enum StagedCoverageReadiness {
    case ready(openIdentities: Set<FileIdentity>)
    case unavailable(reason: String)
}

private func stagedReferenceReadiness(
    database: OpaquePointer,
    scanID: Int64,
    snapshotInventory: Measurement<[LocalSnapshot]>,
    snapshotCoverage: Measurement<[String]>,
    openFileIdentities: Measurement<Set<FileIdentity>>
) throws -> StagedCoverageReadiness {
    let stateStatement = try prepare(
        database: database,
        sql: """
            SELECT
                scans.scope,
                (SELECT COUNT(*) FROM staged_issues WHERE scan_id = scans.id),
                (SELECT on_disk_complete
                   FROM staged_node_totals
                  WHERE scan_id = scans.id AND node_id = 0)
            FROM staged_scans AS scans
            WHERE scans.id = ?
            """
    )
    defer { sqlite3_finalize(stateStatement) }
    try bindInt64(scanID, at: 1, statement: stateStatement)
    let code = sqlite3_step(stateStatement)
    guard code == SQLITE_ROW else {
        throw StorageIndexError.invalidScan(
            reason: "The staged scan does not exist"
        )
    }
    guard sqlite3_column_type(stateStatement, 2) != SQLITE_NULL else {
        throw StorageIndexError.invalidScan(
            reason: "Staged on-disk accounting has not been reduced"
        )
    }
    guard sqlite3_column_int(stateStatement, 0) == 1 else {
        return .unavailable(
            reason: "A subtree scan cannot prove all physical references"
        )
    }
    guard
        sqlite3_column_int64(stateStatement, 1) == 0,
        sqlite3_column_int(stateStatement, 2) != 0
    else {
        return .unavailable(
            reason: "One or more filesystem entries could not be fully inspected"
        )
    }

    switch (snapshotInventory, snapshotCoverage) {
    case let (.known(snapshots, _), .known(names, _)):
        let inventoryNames = Set(snapshots.map(\.name))
        let coverageNames = Set(names)
        guard
            names.count == coverageNames.count,
            inventoryNames == coverageNames
        else {
            return .unavailable(
                reason: "Snapshot coverage does not match the current inventory"
            )
        }
    case let (.notPublished(reason), _),
         let (_, .notPublished(reason)):
        return .unavailable(reason: reason)
    case (.notAttributable, _), (_, .notAttributable):
        return .unavailable(
            reason: "Snapshot references are not fully attributable"
        )
    }

    switch openFileIdentities {
    case let .known(identities, _):
        return .ready(openIdentities: identities)
    case let .notPublished(reason):
        return .unavailable(reason: reason)
    case .notAttributable:
        return .unavailable(
            reason: "Open-file references are not fully attributable"
        )
    }
}

private func stagedReferenceReadiness(
    database: OpaquePointer,
    scanID: Int64,
    snapshotInventory: Measurement<[LocalSnapshot]>,
    snapshotManifests: Measurement<[SnapshotExtentManifest]>,
    openFileIdentities: Measurement<Set<FileIdentity>>
) throws -> StagedReferenceReadiness {
    let stateStatement = try prepare(
        database: database,
        sql: """
            SELECT
                scans.scope,
                (SELECT COUNT(*) FROM staged_issues WHERE scan_id = scans.id),
                (SELECT on_disk_complete
                   FROM staged_node_totals
                  WHERE scan_id = scans.id AND node_id = 0)
            FROM staged_scans AS scans
            WHERE scans.id = ?
            """
    )
    defer { sqlite3_finalize(stateStatement) }
    try bindInt64(scanID, at: 1, statement: stateStatement)
    let code = sqlite3_step(stateStatement)
    guard code == SQLITE_ROW else {
        throw StorageIndexError.invalidScan(
            reason: "The staged scan does not exist"
        )
    }
    guard sqlite3_column_type(stateStatement, 2) != SQLITE_NULL else {
        throw StorageIndexError.invalidScan(
            reason: "Staged on-disk accounting has not been reduced"
        )
    }
    guard sqlite3_column_int(stateStatement, 0) == 1 else {
        return .unavailable(
            reason: "A subtree scan cannot prove all physical references"
        )
    }
    guard
        sqlite3_column_int64(stateStatement, 1) == 0,
        sqlite3_column_int(stateStatement, 2) != 0
    else {
        return .unavailable(
            reason: "One or more filesystem entries could not be fully inspected"
        )
    }

    let manifests: [SnapshotExtentManifest]
    switch snapshotInventory {
    case let .known(snapshots, _):
        if snapshots.isEmpty {
            manifests = []
        } else {
            switch snapshotManifests {
            case let .known(values, _):
                let inventoryNames = Set(snapshots.map(\.name))
                let manifestNames = Set(values.map(\.snapshotName))
                guard
                    values.count == manifestNames.count,
                    inventoryNames == manifestNames
                else {
                    return .unavailable(
                        reason: "Snapshot manifests do not match the current inventory"
                    )
                }
                manifests = values
            case let .notPublished(reason):
                return .unavailable(reason: reason)
            case .notAttributable:
                return .unavailable(
                    reason: "Snapshot references are not fully attributable"
                )
            }
        }
    case let .notPublished(reason):
        return .unavailable(reason: reason)
    case .notAttributable:
        return .unavailable(
            reason: "Snapshot references are not fully attributable"
        )
    }

    switch openFileIdentities {
    case let .known(identities, _):
        return .ready(
            manifests: manifests,
            openIdentities: identities
        )
    case let .notPublished(reason):
        return .unavailable(reason: reason)
    case .notAttributable:
        return .unavailable(
            reason: "Open-file references are not fully attributable"
        )
    }
}

private func markStagedFreeableNotPublished(
    database: OpaquePointer,
    scanID: Int64,
    reason: String
) throws {
    let statement = try prepare(
        database: database,
        sql: """
            UPDATE staged_node_totals
            SET
                exclusive_freeable = NULL,
                subtree_freeable = NULL,
                freeable_state = 1,
                freeable_reason = ?
            WHERE scan_id = ?
            """
    )
    defer { sqlite3_finalize(statement) }
    try bindText(reason, at: 1, statement: statement)
    try bindInt64(scanID, at: 2, statement: statement)
    try stepDone(statement, database: database)
}

private func insertStagedSnapshotExtents(
    database: OpaquePointer,
    scanID: Int64,
    manifests: [SnapshotExtentManifest]
) throws {
    let statement = try prepare(
        database: database,
        sql: """
            INSERT INTO staged_snapshot_extents(
                scan_id, snapshot_name, ordinal,
                device, device_offset, length
            ) VALUES (?, ?, ?, ?, ?, ?)
            """
    )
    defer { sqlite3_finalize(statement) }
    for manifest in manifests {
        for (ordinal, extent) in manifest.physicalExtents.enumerated() {
            let (end, overflow) = extent.deviceOffset
                .addingReportingOverflow(extent.length)
            guard
                !overflow,
                extent.device <= UInt64(Int64.max),
                extent.deviceOffset <= UInt64(Int64.max),
                extent.length <= UInt64(Int64.max),
                end <= UInt64(Int64.max)
            else {
                throw StorageIndexError.invalidScan(
                    reason: "A snapshot extent exceeds SQLite's ordered integer range"
                )
            }
            sqlite3_reset(statement)
            sqlite3_clear_bindings(statement)
            try bindInt64(scanID, at: 1, statement: statement)
            try bindText(
                manifest.snapshotName,
                at: 2,
                statement: statement
            )
            try bindInt64(
                Int64(ordinal),
                at: 3,
                statement: statement
            )
            try bindUInt64(extent.device, at: 4, statement: statement)
            try bindUInt64(
                extent.deviceOffset,
                at: 5,
                statement: statement
            )
            try bindUInt64(extent.length, at: 6, statement: statement)
            try stepDone(statement, database: database)
        }
    }
}

private func deleteStagedSnapshotReferences(
    database: OpaquePointer,
    scanID: Int64
) throws {
    for table in [
        "staged_snapshot_segments",
        "staged_snapshot_extents",
    ] {
        let statement = try prepare(
            database: database,
            sql: "DELETE FROM \(table) WHERE scan_id = ?"
        )
        defer { sqlite3_finalize(statement) }
        try bindInt64(scanID, at: 1, statement: statement)
        try stepDone(statement, database: database)
    }
}

private func mergeStagedSnapshotExtents(
    database: OpaquePointer,
    scanID: Int64
) throws {
    let deleteStatement = try prepare(
        database: database,
        sql: "DELETE FROM staged_snapshot_segments WHERE scan_id = ?"
    )
    defer { sqlite3_finalize(deleteStatement) }
    try bindInt64(scanID, at: 1, statement: deleteStatement)
    try stepDone(deleteStatement, database: database)

    let readStatement = try prepare(
        database: database,
        sql: """
            SELECT device, device_offset, length
            FROM staged_snapshot_extents
            WHERE scan_id = ?
            ORDER BY device, device_offset, length
            """
    )
    defer { sqlite3_finalize(readStatement) }
    try bindInt64(scanID, at: 1, statement: readStatement)
    let insertStatement = try prepare(
        database: database,
        sql: """
            INSERT INTO staged_snapshot_segments(
                scan_id, id, device, device_offset, length
            ) VALUES (?, ?, ?, ?, ?)
            """
    )
    defer { sqlite3_finalize(insertStatement) }

    var activeDevice: Int64?
    var activeStart: Int64 = 0
    var activeEnd: Int64 = 0
    var nextID: Int64 = 0

    func emitActive() throws {
        guard let activeDevice else {
            return
        }
        sqlite3_reset(insertStatement)
        sqlite3_clear_bindings(insertStatement)
        try bindInt64(scanID, at: 1, statement: insertStatement)
        try bindInt64(nextID, at: 2, statement: insertStatement)
        try bindInt64(activeDevice, at: 3, statement: insertStatement)
        try bindInt64(activeStart, at: 4, statement: insertStatement)
        try bindInt64(activeEnd - activeStart, at: 5, statement: insertStatement)
        try stepDone(insertStatement, database: database)
        nextID += 1
    }

    while true {
        let code = sqlite3_step(readStatement)
        if code == SQLITE_DONE {
            break
        }
        guard code == SQLITE_ROW else {
            throw sqliteError(database: database, code: code)
        }
        let device = sqlite3_column_int64(readStatement, 0)
        let start = sqlite3_column_int64(readStatement, 1)
        let length = sqlite3_column_int64(readStatement, 2)
        let (end, overflow) = start.addingReportingOverflow(length)
        guard
            start >= 0,
            length >= 0,
            !overflow
        else {
            throw StorageIndexError.invalidScan(
                reason: "A staged snapshot extent is invalid"
            )
        }
        if activeDevice == nil {
            activeDevice = device
            activeStart = start
            activeEnd = end
        } else if activeDevice == device, start <= activeEnd {
            activeEnd = max(activeEnd, end)
        } else {
            try emitActive()
            activeDevice = device
            activeStart = start
            activeEnd = end
        }
    }
    try emitActive()
}

private func insertStagedOpenIdentities(
    database: OpaquePointer,
    scanID: Int64,
    identities: Set<FileIdentity>
) throws {
    let deleteStatement = try prepare(
        database: database,
        sql: "DELETE FROM staged_open_identities WHERE scan_id = ?"
    )
    defer { sqlite3_finalize(deleteStatement) }
    try bindInt64(scanID, at: 1, statement: deleteStatement)
    try stepDone(deleteStatement, database: database)

    let statement = try prepare(
        database: database,
        sql: """
            INSERT INTO staged_open_identities(scan_id, device, inode)
            VALUES (?, ?, ?)
            """
    )
    defer { sqlite3_finalize(statement) }
    for identity in identities {
        sqlite3_reset(statement)
        sqlite3_clear_bindings(statement)
        try bindInt64(scanID, at: 1, statement: statement)
        try bindUInt64(identity.device, at: 2, statement: statement)
        try bindUInt64(identity.inode, at: 3, statement: statement)
        try stepDone(statement, database: database)
    }
}

private func populateStagedBlockedEntries(
    database: OpaquePointer,
    scanID: Int64
) throws {
    try execute(
        database: database,
        sql: """
            INSERT OR IGNORE INTO staged_blocked_entries(
                scan_id, entry_id, reason
            )
            WITH observed AS (
                SELECT device, inode, COUNT(*) AS observed_count
                FROM staged_entries
                WHERE scan_id = \(scanID)
                GROUP BY device, inode
            )
            SELECT entries.scan_id, entries.id, 1
            FROM staged_entries AS entries
            JOIN observed
              ON observed.device = entries.device
             AND observed.inode = entries.inode
            WHERE entries.scan_id = \(scanID)
              AND entries.kind = 1
              AND entries.hard_link_count > observed.observed_count
            """
    )
    try execute(
        database: database,
        sql: """
            INSERT OR IGNORE INTO staged_blocked_entries(
                scan_id, entry_id, reason
            )
            WITH clone_identities AS (
                SELECT DISTINCT
                    device, clone_id, inode, clone_reference_count
                FROM staged_entries
                WHERE scan_id = \(scanID)
                  AND clone_id IS NOT NULL
                  AND clone_id != 0
            ),
            clone_counts AS (
                SELECT
                    device, clone_id,
                    COUNT(*) AS observed_count,
                    MAX(clone_reference_count) AS published_count
                FROM clone_identities
                GROUP BY device, clone_id
            )
            SELECT entries.scan_id, entries.id, 2
            FROM staged_entries AS entries
            JOIN clone_counts
              ON clone_counts.device = entries.device
             AND clone_counts.clone_id = entries.clone_id
            WHERE entries.scan_id = \(scanID)
              AND clone_counts.published_count >
                  clone_counts.observed_count
            """
    )
    try execute(
        database: database,
        sql: """
            INSERT OR IGNORE INTO staged_blocked_entries(
                scan_id, entry_id, reason
            )
            SELECT entries.scan_id, entries.id, 3
            FROM staged_entries AS entries
            JOIN staged_open_identities AS open
              ON open.scan_id = entries.scan_id
             AND open.device = entries.device
             AND open.inode = entries.inode
            WHERE entries.scan_id = \(scanID)
            """
    )
}

private func deleteStagedBlockedEntries(
    database: OpaquePointer,
    scanID: Int64
) throws {
    let statement = try prepare(
        database: database,
        sql: "DELETE FROM staged_blocked_entries WHERE scan_id = ?"
    )
    defer { sqlite3_finalize(statement) }
    try bindInt64(scanID, at: 1, statement: statement)
    try stepDone(statement, database: database)
}

private final class SnapshotSegmentCursor {
    private let database: OpaquePointer
    private let statement: OpaquePointer
    private var current: (device: Int64, start: Int64, end: Int64)?

    init(database: OpaquePointer, scanID: Int64) throws {
        self.database = database
        statement = try prepare(
            database: database,
            sql: """
                SELECT device, device_offset, length
                FROM staged_snapshot_segments
                WHERE scan_id = ?
                ORDER BY device, device_offset
                """
        )
        try bindInt64(scanID, at: 1, statement: statement)
        try advance()
    }

    deinit {
        sqlite3_finalize(statement)
    }

    func unheldLength(
        device: Int64,
        start: Int64,
        length: Int64
    ) throws -> UInt64 {
        let (end, overflow) = start.addingReportingOverflow(length)
        guard start >= 0, length >= 0, !overflow else {
            throw StorageIndexError.invalidScan(
                reason: "A live physical segment is invalid"
            )
        }

        while let value = current {
            if value.device < device ||
                (value.device == device && value.end <= start)
            {
                try advance()
            } else {
                break
            }
        }

        var held: UInt64 = 0
        while let value = current {
            guard value.device == device, value.start < end else {
                break
            }
            let overlapStart = max(start, value.start)
            let overlapEnd = min(end, value.end)
            if overlapEnd > overlapStart {
                let overlap = UInt64(overlapEnd - overlapStart)
                let (sum, heldOverflow) = held.addingReportingOverflow(
                    overlap
                )
                guard !heldOverflow else {
                    throw StorageIndexError.invalidScan(
                        reason: "Snapshot-held bytes overflowed"
                    )
                }
                held = sum
            }
            if value.end <= end {
                try advance()
            } else {
                break
            }
        }
        let liveLength = UInt64(length)
        guard held <= liveLength else {
            throw StorageIndexError.invalidScan(
                reason: "Snapshot-held bytes exceed their live segment"
            )
        }
        return liveLength - held
    }

    private func advance() throws {
        let code = sqlite3_step(statement)
        if code == SQLITE_DONE {
            current = nil
            return
        }
        guard code == SQLITE_ROW else {
            throw sqliteError(database: database, code: code)
        }
        let device = sqlite3_column_int64(statement, 0)
        let start = sqlite3_column_int64(statement, 1)
        let length = sqlite3_column_int64(statement, 2)
        let (end, overflow) = start.addingReportingOverflow(length)
        guard start >= 0, length >= 0, !overflow else {
            throw StorageIndexError.invalidScan(
                reason: "A snapshot physical segment is invalid"
            )
        }
        current = (device: device, start: start, end: end)
    }
}

private func computeAndStoreStagedFreeable(
    database: OpaquePointer,
    scanID: Int64
) throws -> UInt64 {
    let nodes = try loadStagedNodeVectors(
        database: database,
        scanID: scanID
    )
    var exclusiveFreeable = Array(
        repeating: UInt64(0),
        count: nodes.parents.count
    )

    let directStatement = try prepare(
        database: database,
        sql: """
            SELECT
                entries.id,
                entries.allocated_size,
                EXISTS(
                    SELECT 1
                    FROM staged_blocked_entries AS blocked
                    WHERE blocked.scan_id = entries.scan_id
                      AND blocked.entry_id = entries.id
                )
            FROM staged_entries AS entries
            WHERE entries.scan_id = ? AND entries.kind != 1
            ORDER BY entries.id
            """
    )
    try bindInt64(scanID, at: 1, statement: directStatement)
    while true {
        let code = sqlite3_step(directStatement)
        if code == SQLITE_DONE {
            break
        }
        guard code == SQLITE_ROW else {
            sqlite3_finalize(directStatement)
            throw sqliteError(database: database, code: code)
        }
        let id = sqlite3_column_int64(directStatement, 0)
        guard id >= 0, id < Int64(exclusiveFreeable.count) else {
            sqlite3_finalize(directStatement)
            throw StorageIndexError.invalidScan(
                reason: "A direct freeable node identifier is invalid"
            )
        }
        if sqlite3_column_int(directStatement, 2) == 0 {
            exclusiveFreeable[Int(id)] = UInt64(
                bitPattern: sqlite3_column_int64(directStatement, 1)
            )
        }
    }
    sqlite3_finalize(directStatement)

    let snapshotCursor = try SnapshotSegmentCursor(
        database: database,
        scanID: scanID
    )
    let segmentStatement = try prepare(
        database: database,
        sql: """
            SELECT
                segments.id,
                segments.device,
                segments.device_offset,
                segments.length,
                segments.credited_node_id,
                owners.entry_id,
                EXISTS(
                    SELECT 1
                    FROM staged_blocked_entries AS blocked
                    WHERE blocked.scan_id = owners.scan_id
                      AND blocked.entry_id = owners.entry_id
                )
            FROM staged_segments AS segments
            JOIN staged_segment_owners AS owners
              ON owners.scan_id = segments.scan_id
             AND owners.segment_id = segments.id
            WHERE segments.scan_id = ?
            ORDER BY segments.id, owners.entry_id
            """
    )
    defer { sqlite3_finalize(segmentStatement) }
    try bindInt64(scanID, at: 1, statement: segmentStatement)

    var activeSegment:
        (
            id: Int64,
            device: Int64,
            start: Int64,
            length: Int64,
            creditedNode: Int64,
            isBlocked: Bool
        )?

    func creditActiveSegment() throws {
        guard let segment = activeSegment, !segment.isBlocked else {
            return
        }
        guard
            segment.creditedNode >= 0,
            segment.creditedNode < Int64(exclusiveFreeable.count)
        else {
            throw StorageIndexError.invalidScan(
                reason: "A freeable segment credit node is invalid"
            )
        }
        let freeable = try snapshotCursor.unheldLength(
            device: segment.device,
            start: segment.start,
            length: segment.length
        )
        let index = Int(segment.creditedNode)
        let (sum, overflow) = exclusiveFreeable[index]
            .addingReportingOverflow(freeable)
        guard !overflow else {
            throw StorageIndexError.invalidScan(
                reason: "A staged freeable credit overflowed"
            )
        }
        exclusiveFreeable[index] = sum
    }

    while true {
        let code = sqlite3_step(segmentStatement)
        if code == SQLITE_DONE {
            break
        }
        guard code == SQLITE_ROW else {
            throw sqliteError(database: database, code: code)
        }
        let segmentID = sqlite3_column_int64(segmentStatement, 0)
        if let currentSegment = activeSegment,
            currentSegment.id != segmentID
        {
            try creditActiveSegment()
            activeSegment = nil
        }
        if activeSegment == nil {
            activeSegment = (
                id: segmentID,
                device: sqlite3_column_int64(segmentStatement, 1),
                start: sqlite3_column_int64(segmentStatement, 2),
                length: sqlite3_column_int64(segmentStatement, 3),
                creditedNode: sqlite3_column_int64(segmentStatement, 4),
                isBlocked: false
            )
        }
        if sqlite3_column_int(segmentStatement, 6) != 0 {
            activeSegment?.isBlocked = true
        }
    }
    try creditActiveSegment()

    var subtreeFreeable = exclusiveFreeable
    if subtreeFreeable.count > 1 {
        for index in stride(
            from: subtreeFreeable.count - 1,
            through: 1,
            by: -1
        ) {
            let parent = nodes.parents[index]
            guard parent >= 0, parent < Int64(subtreeFreeable.count) else {
                throw StorageIndexError.invalidScan(
                    reason: "A freeable subtree parent is invalid"
                )
            }
            let parentIndex = Int(parent)
            let (sum, overflow) = subtreeFreeable[parentIndex]
                .addingReportingOverflow(subtreeFreeable[index])
            guard !overflow else {
                throw StorageIndexError.invalidScan(
                    reason: "A staged freeable subtree overflowed"
                )
            }
            subtreeFreeable[parentIndex] = sum
        }
    }

    let updateStatement = try prepare(
        database: database,
        sql: """
            UPDATE staged_node_totals
            SET
                exclusive_freeable = ?,
                subtree_freeable = ?,
                freeable_state = 0,
                freeable_reason = NULL
            WHERE scan_id = ? AND node_id = ?
            """
    )
    defer { sqlite3_finalize(updateStatement) }
    for index in exclusiveFreeable.indices {
        sqlite3_reset(updateStatement)
        sqlite3_clear_bindings(updateStatement)
        try bindUInt64(
            exclusiveFreeable[index],
            at: 1,
            statement: updateStatement
        )
        try bindUInt64(
            subtreeFreeable[index],
            at: 2,
            statement: updateStatement
        )
        try bindInt64(scanID, at: 3, statement: updateStatement)
        try bindInt64(Int64(index), at: 4, statement: updateStatement)
        try stepDone(updateStatement, database: database)
    }
    return subtreeFreeable.first ?? 0
}

private func stagedReductionRowCount(
    database: OpaquePointer,
    scanID: Int64
) throws -> Int64 {
    let statement = try prepare(
        database: database,
        sql: """
            SELECT COUNT(*)
            FROM staged_node_totals
            WHERE scan_id = ?
            """
    )
    defer { sqlite3_finalize(statement) }
    try bindInt64(scanID, at: 1, statement: statement)
    let code = sqlite3_step(statement)
    guard code == SQLITE_ROW else {
        throw sqliteError(database: database, code: code)
    }
    return sqlite3_column_int64(statement, 0)
}

private func stagedRootPath(
    database: OpaquePointer,
    scanID: Int64
) throws -> String {
    let statement = try prepare(
        database: database,
        sql: "SELECT root_path FROM staged_scans WHERE id = ?"
    )
    defer { sqlite3_finalize(statement) }
    try bindInt64(scanID, at: 1, statement: statement)
    let code = sqlite3_step(statement)
    guard code == SQLITE_ROW,
          let text = sqlite3_column_text(statement, 0) else {
        throw StorageIndexError.invalidScan(
            reason: "The staged scan does not exist"
        )
    }
    return String(cString: text)
}

private func nextStagedEntryID(
    database: OpaquePointer,
    scanID: Int64
) throws -> Int64 {
    let statement = try prepare(
        database: database,
        sql: "SELECT COALESCE(MAX(id) + 1, 0) FROM staged_entries WHERE scan_id = ?"
    )
    defer { sqlite3_finalize(statement) }
    try bindInt64(scanID, at: 1, statement: statement)
    let code = sqlite3_step(statement)
    guard code == SQLITE_ROW else {
        throw sqliteError(database: database, code: code)
    }
    return sqlite3_column_int64(statement, 0)
}

private func stagedEntryID(
    database: OpaquePointer,
    scanID: Int64,
    path: String
) throws -> Int64? {
    let statement = try prepare(
        database: database,
        sql: "SELECT id FROM staged_entries WHERE scan_id = ? AND path = ?"
    )
    defer { sqlite3_finalize(statement) }
    try bindInt64(scanID, at: 1, statement: statement)
    try bindText(path, at: 2, statement: statement)
    let code = sqlite3_step(statement)
    if code == SQLITE_DONE { return nil }
    guard code == SQLITE_ROW else {
        throw sqliteError(database: database, code: code)
    }
    return sqlite3_column_int64(statement, 0)
}

private func clearStagedDerivedAccounting(
    database: OpaquePointer,
    scanID: Int64
) throws {
    for table in [
        "staged_blocked_entries",
        "staged_open_identities",
        "staged_segment_owners",
        "staged_segments",
        "staged_node_totals"
    ] {
        let statement = try prepare(
            database: database,
            sql: "DELETE FROM \(table) WHERE scan_id = ?"
        )
        try bindInt64(scanID, at: 1, statement: statement)
        do {
            try stepDone(statement, database: database)
            sqlite3_finalize(statement)
        } catch {
            sqlite3_finalize(statement)
            throw error
        }
    }
}

private func removeStagedSubtree(
    database: OpaquePointer,
    scanID: Int64,
    rootPath: String
) throws {
    let select = try prepare(
        database: database,
        sql: """
            SELECT id FROM staged_entries
            WHERE scan_id = ? AND (
                path = ? OR substr(path, 1, length(?) + 1) = ? || '/'
            )
            ORDER BY length(path) DESC, id DESC
            """
    )
    defer { sqlite3_finalize(select) }
    try bindInt64(scanID, at: 1, statement: select)
    try bindText(rootPath, at: 2, statement: select)
    try bindText(rootPath, at: 3, statement: select)
    try bindText(rootPath, at: 4, statement: select)
    var ids: [Int64] = []
    while true {
        let code = sqlite3_step(select)
        if code == SQLITE_DONE { break }
        guard code == SQLITE_ROW else {
            throw sqliteError(database: database, code: code)
        }
        ids.append(sqlite3_column_int64(select, 0))
    }
    let delete = try prepare(
        database: database,
        sql: "DELETE FROM staged_entries WHERE scan_id = ? AND id = ?"
    )
    defer { sqlite3_finalize(delete) }
    for id in ids {
        sqlite3_reset(delete)
        sqlite3_clear_bindings(delete)
        try bindInt64(scanID, at: 1, statement: delete)
        try bindInt64(id, at: 2, statement: delete)
        try stepDone(delete, database: database)
    }
    let deleteIssues = try prepare(
        database: database,
        sql: """
            DELETE FROM staged_issues
            WHERE scan_id = ? AND (
                path = ? OR substr(path, 1, length(?) + 1) = ? || '/'
            )
            """
    )
    defer { sqlite3_finalize(deleteIssues) }
    try bindInt64(scanID, at: 1, statement: deleteIssues)
    try bindText(rootPath, at: 2, statement: deleteIssues)
    try bindText(rootPath, at: 3, statement: deleteIssues)
    try bindText(rootPath, at: 4, statement: deleteIssues)
    try stepDone(deleteIssues, database: database)
}

private func insertStagedSubtree(
    database: OpaquePointer,
    scanID: Int64,
    rootURL: URL,
    externalParentID: Int64?,
    nextID: inout Int64
) throws -> [StorageScanIssue] {
    let entryStatement = try prepare(
        database: database,
        sql: """
            INSERT INTO staged_entries(
                scan_id, id, parent_id, component, path, kind,
                device, inode, hard_link_count,
                logical_size, allocated_size,
                modified_seconds, modified_nanoseconds,
                is_dataless, extent_state
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0)
            """
    )
    defer { sqlite3_finalize(entryStatement) }
    let searchStatement = try prepare(
        database: database,
        sql: """
            INSERT INTO staged_path_fts(
                scan_id, entry_id, component, path
            ) VALUES (?, ?, ?, ?)
            """
    )
    defer { sqlite3_finalize(searchStatement) }
    var directoryStack: [(depth: UInt64, id: Int64)] = []
    var localNextID = nextID
    let summary = try StorageScanner().walk(at: rootURL) { entry in
        guard let location = entry.traversalLocation,
              case let .known(logicalSize, _) = entry.logicalSize,
              case let .known(allocatedSize, _) = entry.sizeOnDisk,
              case let .known(modified, _) = entry.modificationTime else {
            throw StorageIndexError.invalidScan(
                reason: "An incremental traversal record is incomplete"
            )
        }
        while let last = directoryStack.last,
              last.depth >= location.depth {
            directoryStack.removeLast()
        }
        let parentID = location.depth == 0
            ? externalParentID
            : directoryStack.last?.id
        guard location.depth == 0 || parentID != nil else {
            throw StorageIndexError.invalidScan(
                reason: "An incremental traversal record has no parent"
            )
        }
        let id = localNextID
        localNextID += 1
        sqlite3_reset(entryStatement)
        sqlite3_clear_bindings(entryStatement)
        try bindInt64(scanID, at: 1, statement: entryStatement)
        try bindInt64(id, at: 2, statement: entryStatement)
        if let parentID {
            try bindInt64(parentID, at: 3, statement: entryStatement)
        } else {
            try bindNull(at: 3, statement: entryStatement)
        }
        try bindText(location.name, at: 4, statement: entryStatement)
        try bindText(entry.path, at: 5, statement: entryStatement)
        try bindInt64(
            Int64(storageKindCode(entry.kind)),
            at: 6,
            statement: entryStatement
        )
        try bindUInt64(entry.identity.device, at: 7, statement: entryStatement)
        try bindUInt64(entry.identity.inode, at: 8, statement: entryStatement)
        try bindUInt64(entry.hardLinkCount, at: 9, statement: entryStatement)
        try bindUInt64(logicalSize, at: 10, statement: entryStatement)
        try bindUInt64(allocatedSize, at: 11, statement: entryStatement)
        try bindInt64(modified.secondsSinceEpoch, at: 12, statement: entryStatement)
        try bindInt64(Int64(modified.nanoseconds), at: 13, statement: entryStatement)
        try bindInt64(entry.isDataless ? 1 : 0, at: 14, statement: entryStatement)
        try stepDone(entryStatement, database: database)

        sqlite3_reset(searchStatement)
        sqlite3_clear_bindings(searchStatement)
        try bindInt64(scanID, at: 1, statement: searchStatement)
        try bindInt64(id, at: 2, statement: searchStatement)
        try bindText(location.name, at: 3, statement: searchStatement)
        try bindText(entry.path, at: 4, statement: searchStatement)
        try stepDone(searchStatement, database: database)
        if entry.kind == .directory {
            directoryStack.append((location.depth, id))
        }
    }
    nextID = localNextID
    return summary.issues
}

private func renumberStagedEntries(
    database: OpaquePointer,
    scanID: Int64
) throws {
    let select = try prepare(
        database: database,
        sql: """
            SELECT id, parent_id
            FROM staged_entries
            WHERE scan_id = ?
            ORDER BY length(path), path COLLATE BINARY, id
            """
    )
    defer { sqlite3_finalize(select) }
    try bindInt64(scanID, at: 1, statement: select)
    var mapping: [(old: Int64, parent: Int64?, new: Int64)] = []
    var newByOld: [Int64: Int64] = [:]
    while true {
        let code = sqlite3_step(select)
        if code == SQLITE_DONE { break }
        guard code == SQLITE_ROW else {
            throw sqliteError(database: database, code: code)
        }
        let old = sqlite3_column_int64(select, 0)
        let parent = sqlite3_column_type(select, 1) == SQLITE_NULL
            ? nil
            : sqlite3_column_int64(select, 1)
        let new = Int64(mapping.count)
        mapping.append((old, parent, new))
        newByOld[old] = new
    }
    guard !mapping.isEmpty else {
        throw StorageIndexError.invalidScan(
            reason: "An incremental refresh removed the scan root"
        )
    }
    try execute(database: database, sql: "PRAGMA defer_foreign_keys = ON")
    try execute(
        database: database,
        sql: "UPDATE staged_extents SET entry_id = -entry_id - 1 WHERE scan_id = \(scanID)"
    )
    try execute(
        database: database,
        sql: """
            UPDATE staged_entries
            SET id = -id - 1,
                parent_id = CASE
                    WHEN parent_id IS NULL THEN NULL
                    ELSE -parent_id - 1
                END
            WHERE scan_id = \(scanID)
            """
    )
    let updateEntry = try prepare(
        database: database,
        sql: """
            UPDATE staged_entries SET id = ?, parent_id = ?
            WHERE scan_id = ? AND id = ?
            """
    )
    defer { sqlite3_finalize(updateEntry) }
    let updateExtent = try prepare(
        database: database,
        sql: """
            UPDATE staged_extents SET entry_id = ?
            WHERE scan_id = ? AND entry_id = ?
            """
    )
    defer { sqlite3_finalize(updateExtent) }
    for item in mapping {
        sqlite3_reset(updateEntry)
        sqlite3_clear_bindings(updateEntry)
        try bindInt64(item.new, at: 1, statement: updateEntry)
        if let parent = item.parent, let newParent = newByOld[parent] {
            try bindInt64(newParent, at: 2, statement: updateEntry)
        } else if item.parent == nil {
            try bindNull(at: 2, statement: updateEntry)
        } else {
            throw StorageIndexError.invalidScan(
                reason: "An incremental parent disappeared during renumbering"
            )
        }
        try bindInt64(scanID, at: 3, statement: updateEntry)
        try bindInt64(-item.old - 1, at: 4, statement: updateEntry)
        try stepDone(updateEntry, database: database)

        sqlite3_reset(updateExtent)
        sqlite3_clear_bindings(updateExtent)
        try bindInt64(item.new, at: 1, statement: updateExtent)
        try bindInt64(scanID, at: 2, statement: updateExtent)
        try bindInt64(-item.old - 1, at: 3, statement: updateExtent)
        try stepDone(updateExtent, database: database)
    }
    let deleteSearch = try prepare(
        database: database,
        sql: "DELETE FROM staged_path_fts WHERE scan_id = ?"
    )
    defer { sqlite3_finalize(deleteSearch) }
    try bindInt64(scanID, at: 1, statement: deleteSearch)
    try stepDone(deleteSearch, database: database)
    try execute(
        database: database,
        sql: """
            INSERT INTO staged_path_fts(scan_id, entry_id, component, path)
            SELECT scan_id, id, component, path
            FROM staged_entries WHERE scan_id = \(scanID)
            """
    )
}

private func appendTraversalIssues(
    database: OpaquePointer,
    scanID: Int64,
    issues: [StorageScanIssue]
) throws {
    guard !issues.isEmpty else { return }
    var ordinal = try nextStagedIssueOrdinal(
        database: database,
        scanID: scanID
    )
    let statement = try prepare(
        database: database,
        sql: """
            INSERT INTO staged_issues(
                scan_id, ordinal, path, stage, error_number, reason
            ) VALUES (?, ?, ?, 0, ?, ?)
            """
    )
    defer { sqlite3_finalize(statement) }
    for issue in issues {
        sqlite3_reset(statement)
        sqlite3_clear_bindings(statement)
        try bindInt64(scanID, at: 1, statement: statement)
        try bindInt64(ordinal, at: 2, statement: statement)
        try bindText(issue.path, at: 3, statement: statement)
        try bindInt64(Int64(issue.errorNumber), at: 4, statement: statement)
        try bindText("FTS could not read this entry", at: 5, statement: statement)
        try stepDone(statement, database: database)
        ordinal += 1
    }
}

/// The number of staged nodes, for reserving the vectors that hold them.
///
/// A count that does not fit an `Int` cannot be reserved anyway, so it is
/// clamped rather than trapped: the vectors then grow as they used to, which is
/// slower but still correct.
private func stagedNodeCount(
    database: OpaquePointer,
    scanID: Int64
) throws -> Int {
    let statement = try prepare(
        database: database,
        sql: "SELECT COUNT(*) FROM staged_entries WHERE scan_id = ?"
    )
    defer { sqlite3_finalize(statement) }
    try bindInt64(scanID, at: 1, statement: statement)
    let code = sqlite3_step(statement)
    guard code == SQLITE_ROW else {
        throw sqliteError(database: database, code: code)
    }
    let count = sqlite3_column_int64(statement, 0)
    guard count > 0, count <= Int64(Int.max) else {
        return 0
    }
    return Int(count)
}

private func loadStagedNodeVectors(
    database: OpaquePointer,
    scanID: Int64
) throws -> StagedNodeVectors {
    let statement = try prepare(
        database: database,
        sql: """
            SELECT id, parent_id, kind, allocated_size, extent_state
            FROM staged_entries
            WHERE scan_id = ?
            ORDER BY id
            """
    )
    defer { sqlite3_finalize(statement) }
    try bindInt64(scanID, at: 1, statement: statement)

    // Reserve the exact row count before reading a single row.
    //
    // These five vectors hold 29 bytes per node between them, and appending to
    // them unreserved cost 118 — Swift grows an array by doubling, so each one
    // carried up to twice the capacity it needed and paid a full copy at every
    // growth, five times over and unsynchronised. On a 3.77 million entry
    // volume that was the difference between about 110 MB and about 445 MB, and
    // it is the whole reason the RELEASE-GATES gate 1 run peaked at 483 MB
    // against a 300 MB budget: RSS sat flat at 50 MB through the traversal and
    // the extent inspection, then climbed here in a third of a second.
    //
    // The count is a covering scan of the `(scan_id, id)` primary key, so it
    // costs one index range rather than a table read.
    let nodeCount = try stagedNodeCount(database: database, scanID: scanID)
    var parents: [Int64] = []
    var depths: [UInt32] = []
    var directCredits: [UInt64] = []
    var allocatedBytes: [UInt64] = []
    var unmappedRegularFiles: [Bool] = []
    parents.reserveCapacity(nodeCount)
    depths.reserveCapacity(nodeCount)
    directCredits.reserveCapacity(nodeCount)
    allocatedBytes.reserveCapacity(nodeCount)
    unmappedRegularFiles.reserveCapacity(nodeCount)
    while true {
        let code = sqlite3_step(statement)
        if code == SQLITE_DONE {
            break
        }
        guard code == SQLITE_ROW else {
            throw sqliteError(database: database, code: code)
        }
        let id = sqlite3_column_int64(statement, 0)
        guard id == Int64(parents.count) else {
            throw StorageIndexError.invalidScan(
                reason: "Staged node identifiers are not contiguous"
            )
        }

        let parent: Int64
        if sqlite3_column_type(statement, 1) == SQLITE_NULL {
            parent = -1
        } else {
            parent = sqlite3_column_int64(statement, 1)
        }
        let depth: UInt32
        if parent < 0 {
            guard parents.isEmpty else {
                throw StorageIndexError.invalidScan(
                    reason: "A staged scan contains more than one root"
                )
            }
            depth = 0
        } else {
            guard parent < Int64(depths.count) else {
                throw StorageIndexError.invalidScan(
                    reason: "A staged parent does not precede its child"
                )
            }
            let (childDepth, overflow) = depths[Int(parent)]
                .addingReportingOverflow(1)
            guard !overflow else {
                throw StorageIndexError.invalidScan(
                    reason: "A staged path depth overflowed"
                )
            }
            depth = childDepth
        }

        let kind = sqlite3_column_int(statement, 2)
        let allocated = UInt64(
            bitPattern: sqlite3_column_int64(statement, 3)
        )
        let extentState = sqlite3_column_int(statement, 4)
        let directCredit: UInt64
        let isUnmappedRegularFile: Bool
        if kind == 1 {
            if extentState == 1 {
                directCredit = 0
                isUnmappedRegularFile = false
            } else {
                directCredit = allocated
                isUnmappedRegularFile = true
            }
        } else {
            directCredit = allocated
            isUnmappedRegularFile = false
        }
        parents.append(parent)
        depths.append(depth)
        directCredits.append(directCredit)
        allocatedBytes.append(allocated)
        unmappedRegularFiles.append(isUnmappedRegularFile)
    }
    return StagedNodeVectors(
        parents: parents,
        depths: depths,
        directCredits: directCredits,
        allocatedBytes: allocatedBytes,
        unmappedRegularFiles: unmappedRegularFiles
    )
}

private func reduceStagedExtentEvents(
    database: OpaquePointer,
    scanID: Int64,
    parents: [Int64],
    depths: [UInt32],
    exclusive: inout [UInt64]
) throws -> UInt64 {
    let eventStatement = try prepare(
        database: database,
        sql: """
            SELECT device, position, entry_id, delta
            FROM (
                SELECT
                    entries.device AS device,
                    extents.device_offset AS position,
                    extents.entry_id AS entry_id,
                    1 AS delta
                FROM staged_extents AS extents
                JOIN staged_entries AS entries
                  ON entries.scan_id = extents.scan_id
                 AND entries.id = extents.entry_id
                WHERE extents.scan_id = ?
                UNION ALL
                SELECT
                    entries.device AS device,
                    extents.device_offset + extents.length AS position,
                    extents.entry_id AS entry_id,
                    -1 AS delta
                FROM staged_extents AS extents
                JOIN staged_entries AS entries
                  ON entries.scan_id = extents.scan_id
                 AND entries.id = extents.entry_id
                WHERE extents.scan_id = ?
            )
            ORDER BY device, position, delta, entry_id
            """
    )
    defer { sqlite3_finalize(eventStatement) }
    try bindInt64(scanID, at: 1, statement: eventStatement)
    try bindInt64(scanID, at: 2, statement: eventStatement)

    let segmentStatement = try prepare(
        database: database,
        sql: """
            INSERT INTO staged_segments(
                scan_id, id, device, device_offset, length,
                credited_node_id
            ) VALUES (?, ?, ?, ?, ?, ?)
            """
    )
    defer { sqlite3_finalize(segmentStatement) }
    let ownerStatement = try prepare(
        database: database,
        sql: """
            INSERT INTO staged_segment_owners(
                scan_id, segment_id, entry_id
            ) VALUES (?, ?, ?)
            """
    )
    defer { sqlite3_finalize(ownerStatement) }

    var activeCounts: [Int64: Int32] = [:]
    var previousDevice: Int64?
    var previousPosition: Int64?
    var nextSegmentID: Int64 = 0
    var eventCount: UInt64 = 0

    while true {
        let code = sqlite3_step(eventStatement)
        if code == SQLITE_DONE {
            break
        }
        guard code == SQLITE_ROW else {
            throw sqliteError(database: database, code: code)
        }
        let device = sqlite3_column_int64(eventStatement, 0)
        let position = sqlite3_column_int64(eventStatement, 1)
        let entryID = sqlite3_column_int64(eventStatement, 2)
        let delta = sqlite3_column_int(eventStatement, 3)
        guard position >= 0 else {
            throw StorageIndexError.invalidScan(
                reason: "A staged physical offset exceeds SQLite's range"
            )
        }

        if
            let priorDevice = previousDevice,
            let priorPosition = previousPosition,
            device != priorDevice || position != priorPosition
        {
            if device != priorDevice {
                guard activeCounts.isEmpty else {
                    throw StorageIndexError.invalidScan(
                        reason: "Physical extent events crossed devices"
                    )
            }
            } else if !activeCounts.isEmpty {
                guard position > priorPosition else {
                    throw StorageIndexError.invalidScan(
                        reason: "Physical extent events are not ordered"
                    )
                }
                let length = UInt64(position - priorPosition)
                let owners = activeCounts.keys.sorted()
                let creditedNode = try lowestCommonAncestor(
                    owners: owners,
                    parents: parents,
                    depths: depths
                )
                let creditIndex = Int(creditedNode)
                let (credit, overflow) = exclusive[creditIndex]
                    .addingReportingOverflow(length)
                guard !overflow else {
                    throw StorageIndexError.invalidScan(
                        reason: "A staged physical credit overflowed"
                    )
                }
                exclusive[creditIndex] = credit

                sqlite3_reset(segmentStatement)
                sqlite3_clear_bindings(segmentStatement)
                try bindInt64(scanID, at: 1, statement: segmentStatement)
                try bindInt64(
                    nextSegmentID,
                    at: 2,
                    statement: segmentStatement
                )
                try bindInt64(
                    priorDevice,
                    at: 3,
                    statement: segmentStatement
                )
                try bindInt64(
                    priorPosition,
                    at: 4,
                    statement: segmentStatement
                )
                try bindUInt64(
                    length,
                    at: 5,
                    statement: segmentStatement
                )
                try bindInt64(
                    creditedNode,
                    at: 6,
                    statement: segmentStatement
                )
                try stepDone(segmentStatement, database: database)

                for owner in owners {
                    sqlite3_reset(ownerStatement)
                    sqlite3_clear_bindings(ownerStatement)
                    try bindInt64(scanID, at: 1, statement: ownerStatement)
                    try bindInt64(
                        nextSegmentID,
                        at: 2,
                        statement: ownerStatement
                    )
                    try bindInt64(owner, at: 3, statement: ownerStatement)
                    try stepDone(ownerStatement, database: database)
                }
                nextSegmentID += 1
            }
            if device != priorDevice {
                previousDevice = device
            }
            previousPosition = position
        } else if previousDevice == nil {
            previousDevice = device
            previousPosition = position
        }

        let nextCount = activeCounts[entryID, default: 0] + delta
        guard nextCount >= 0 else {
            throw StorageIndexError.invalidScan(
                reason: "A staged extent ended before it began"
            )
        }
        if nextCount == 0 {
            activeCounts.removeValue(forKey: entryID)
        } else {
            activeCounts[entryID] = nextCount
        }
        eventCount += 1
        if eventCount.isMultiple(of: 4_096) {
            try Task.checkCancellation()
        }
    }
    guard activeCounts.isEmpty else {
        throw StorageIndexError.invalidScan(
            reason: "A staged extent has no closing event"
        )
    }
    return UInt64(nextSegmentID)
}

private func lowestCommonAncestor(
    owners: [Int64],
    parents: [Int64],
    depths: [UInt32]
) throws -> Int64 {
    guard var ancestor = owners.first else {
        throw StorageIndexError.invalidScan(
            reason: "A physical segment has no owner"
        )
    }
    guard ancestor >= 0, ancestor < Int64(parents.count) else {
        throw StorageIndexError.invalidScan(
            reason: "A physical segment owner is invalid"
        )
    }

    for owner in owners.dropFirst() {
        guard owner >= 0, owner < Int64(parents.count) else {
            throw StorageIndexError.invalidScan(
                reason: "A physical segment owner is invalid"
            )
        }
        var right = owner
        while depths[Int(ancestor)] > depths[Int(right)] {
            ancestor = parents[Int(ancestor)]
        }
        while depths[Int(right)] > depths[Int(ancestor)] {
            right = parents[Int(right)]
        }
        while ancestor != right {
            ancestor = parents[Int(ancestor)]
            right = parents[Int(right)]
            guard ancestor >= 0, right >= 0 else {
                throw StorageIndexError.invalidScan(
                    reason: "Physical segment owners have no common root"
                )
            }
        }
    }
    return ancestor
}

private func storeStagedNodeTotals(
    database: OpaquePointer,
    scanID: Int64,
    exclusive: [UInt64],
    subtree: [UInt64],
    rawSubtree: [UInt64],
    incompleteSubtree: [Bool]
) throws {
    guard
        exclusive.count == subtree.count,
        exclusive.count == rawSubtree.count,
        exclusive.count == incompleteSubtree.count
    else {
        throw StorageIndexError.invalidScan(
            reason: "Staged node total vectors have different lengths"
        )
    }
    let statement = try prepare(
        database: database,
        sql: """
            INSERT INTO staged_node_totals(
                scan_id, node_id, exclusive_size, subtree_size,
                raw_subtree_size, on_disk_complete
            ) VALUES (?, ?, ?, ?, ?, ?)
            """
    )
    defer { sqlite3_finalize(statement) }
    for index in exclusive.indices {
        sqlite3_reset(statement)
        sqlite3_clear_bindings(statement)
        try bindInt64(scanID, at: 1, statement: statement)
        try bindInt64(Int64(index), at: 2, statement: statement)
        try bindUInt64(exclusive[index], at: 3, statement: statement)
        try bindUInt64(subtree[index], at: 4, statement: statement)
        try bindUInt64(rawSubtree[index], at: 5, statement: statement)
        try bindInt64(
            incompleteSubtree[index] ? 0 : 1,
            at: 6,
            statement: statement
        )
        try stepDone(statement, database: database)
    }
}

private func loadStagedRegularFiles(
    database: OpaquePointer,
    scanID: Int64,
    after entryID: Int64,
    limit: Int
) throws -> [StagedRegularFileRecord] {
    let statement = try prepare(
        database: database,
        sql: """
            SELECT
                id, path, device, inode, hard_link_count,
                logical_size, allocated_size,
                modified_seconds, modified_nanoseconds, is_dataless
            FROM staged_entries
            WHERE scan_id = ? AND kind = 1 AND extent_state = 0 AND id > ?
            ORDER BY id
            LIMIT ?
            """
    )
    defer { sqlite3_finalize(statement) }
    try bindInt64(scanID, at: 1, statement: statement)
    try bindInt64(entryID, at: 2, statement: statement)
    try bindInt64(Int64(limit), at: 3, statement: statement)

    var records: [StagedRegularFileRecord] = []
    records.reserveCapacity(limit)
    while true {
        let code = sqlite3_step(statement)
        if code == SQLITE_DONE {
            break
        }
        guard
            code == SQLITE_ROW,
            let pathText = sqlite3_column_text(statement, 1)
        else {
            throw sqliteError(database: database, code: code)
        }
        let path = String(cString: pathText)
        let entry = StorageEntry(
            path: path,
            kind: .regularFile,
            identity: FileIdentity(
                device: UInt64(
                    bitPattern: sqlite3_column_int64(statement, 2)
                ),
                inode: UInt64(
                    bitPattern: sqlite3_column_int64(statement, 3)
                )
            ),
            hardLinkCount: UInt64(
                bitPattern: sqlite3_column_int64(statement, 4)
            ),
            isDataless: sqlite3_column_int(statement, 9) != 0,
            logicalSize: .known(
                UInt64(bitPattern: sqlite3_column_int64(statement, 5)),
                source: .statLogicalSize
            ),
            sizeOnDisk: .known(
                UInt64(bitPattern: sqlite3_column_int64(statement, 6)),
                source: .statAllocatedBlocks
            ),
            modificationTime: .known(
                FileTimestamp(
                    secondsSinceEpoch: sqlite3_column_int64(statement, 7),
                    nanoseconds: sqlite3_column_int(statement, 8)
                ),
                source: .statModificationTime
            ),
            freedIfDeleted: .notPublished(
                reason: "Staged physical references have not been reduced"
            )
        )
        records.append(
            StagedRegularFileRecord(
                id: sqlite3_column_int64(statement, 0),
                entry: entry
            )
        )
    }
    return records
}

private func nextStagedIssueOrdinal(
    database: OpaquePointer,
    scanID: Int64
) throws -> Int64 {
    let statement = try prepare(
        database: database,
        sql: """
            SELECT COALESCE(MAX(ordinal) + 1, 0)
            FROM staged_issues
            WHERE scan_id = ?
            """
    )
    defer { sqlite3_finalize(statement) }
    try bindInt64(scanID, at: 1, statement: statement)
    let code = sqlite3_step(statement)
    guard code == SQLITE_ROW else {
        throw sqliteError(database: database, code: code)
    }
    return sqlite3_column_int64(statement, 0)
}

/// Returns true when the physical map was publishable.
private func storeStagedExtentMap(
    database: OpaquePointer,
    scanID: Int64,
    record: StagedRegularFileRecord,
    map: FileExtentMap,
    issueOrdinal: inout Int64
) throws -> Bool {
    let physicalExtents: [PhysicalFileExtent]
    switch map.physicalExtents {
    case let .known(extents, _):
        physicalExtents = extents
    case let .notPublished(reason):
        try markStagedExtentFailure(
            database: database,
            scanID: scanID,
            record: record,
            reason: reason,
            issueOrdinal: &issueOrdinal
        )
        return false
    case .notAttributable:
        try markStagedExtentFailure(
            database: database,
            scanID: scanID,
            record: record,
            reason: "Physical extents do not reconcile with allocated bytes",
            issueOrdinal: &issueOrdinal
        )
        return false
    }

    for extent in physicalExtents {
        let (end, overflow) = extent.deviceOffset
            .addingReportingOverflow(extent.length)
        guard
            !overflow,
            extent.logicalOffset <= UInt64(Int64.max),
            extent.deviceOffset <= UInt64(Int64.max),
            extent.length <= UInt64(Int64.max),
            end <= UInt64(Int64.max)
        else {
            try markStagedExtentFailure(
                database: database,
                scanID: scanID,
                record: record,
                reason: "A physical extent exceeds SQLite's ordered integer range",
                issueOrdinal: &issueOrdinal
            )
            return false
        }
    }

    let extentStatement = try prepare(
        database: database,
        sql: """
            INSERT INTO staged_extents(
                scan_id, entry_id, ordinal,
                logical_offset, device_offset, length
            ) VALUES (?, ?, ?, ?, ?, ?)
            """
    )
    defer { sqlite3_finalize(extentStatement) }
    for (ordinal, extent) in physicalExtents.enumerated() {
        sqlite3_reset(extentStatement)
        sqlite3_clear_bindings(extentStatement)
        try bindInt64(scanID, at: 1, statement: extentStatement)
        try bindInt64(record.id, at: 2, statement: extentStatement)
        try bindInt64(
            Int64(ordinal),
            at: 3,
            statement: extentStatement
        )
        try bindUInt64(
            extent.logicalOffset,
            at: 4,
            statement: extentStatement
        )
        try bindUInt64(
            extent.deviceOffset,
            at: 5,
            statement: extentStatement
        )
        try bindUInt64(
            extent.length,
            at: 6,
            statement: extentStatement
        )
        try stepDone(extentStatement, database: database)
    }

    let updateStatement = try prepare(
        database: database,
        sql: """
            UPDATE staged_entries
            SET
                extent_state = 1,
                clone_id = ?,
                clone_reference_count = ?,
                allocation_block_size = ?
            WHERE scan_id = ? AND id = ?
            """
    )
    defer { sqlite3_finalize(updateStatement) }
    switch map.cloneMetadata {
    case let .known(metadata, _):
        try bindUInt64(
            metadata.identifier,
            at: 1,
            statement: updateStatement
        )
        try bindInt64(
            Int64(metadata.referenceCount),
            at: 2,
            statement: updateStatement
        )
    case .notPublished, .notAttributable:
        try bindNull(at: 1, statement: updateStatement)
        try bindNull(at: 2, statement: updateStatement)
    }
    switch map.allocationBlockSize {
    case let .known(size, _):
        try bindUInt64(size, at: 3, statement: updateStatement)
    case .notPublished, .notAttributable:
        try bindNull(at: 3, statement: updateStatement)
    }
    try bindInt64(scanID, at: 4, statement: updateStatement)
    try bindInt64(record.id, at: 5, statement: updateStatement)
    try stepDone(updateStatement, database: database)
    return true
}

private func markStagedExtentFailure(
    database: OpaquePointer,
    scanID: Int64,
    record: StagedRegularFileRecord,
    reason: String,
    issueOrdinal: inout Int64
) throws {
    let updateStatement = try prepare(
        database: database,
        sql: """
            UPDATE staged_entries
            SET extent_state = 2
            WHERE scan_id = ? AND id = ?
            """
    )
    defer { sqlite3_finalize(updateStatement) }
    try bindInt64(scanID, at: 1, statement: updateStatement)
    try bindInt64(record.id, at: 2, statement: updateStatement)
    try stepDone(updateStatement, database: database)

    let issueStatement = try prepare(
        database: database,
        sql: """
            INSERT INTO staged_issues(
                scan_id, ordinal, path, stage, error_number, reason
            ) VALUES (?, ?, ?, 1, NULL, ?)
            """
    )
    defer { sqlite3_finalize(issueStatement) }
    try bindInt64(scanID, at: 1, statement: issueStatement)
    try bindInt64(issueOrdinal, at: 2, statement: issueStatement)
    try bindText(record.entry.path, at: 3, statement: issueStatement)
    try bindText(reason, at: 4, statement: issueStatement)
    try stepDone(issueStatement, database: database)
    issueOrdinal += 1
}

private func insertScan(
    database: OpaquePointer,
    result: StorageEngineResult,
    startedAt: Date
) throws -> Int64 {
    let statement = try prepare(
        database: database,
        sql: """
            INSERT INTO scans(
                root_path, started_at, complete,
                snapshot_state, snapshot_reason
            )
            VALUES (?, ?, ?, ?, ?)
            """
    )
    defer { sqlite3_finalize(statement) }
    try bindText(result.rootURL.path, at: 1, statement: statement)
    try check(
        sqlite3_bind_double(
            statement,
            2,
            startedAt.timeIntervalSince1970
        ),
        database: database
    )
    try bindInt64(result.isComplete ? 1 : 0, at: 3, statement: statement)
    let snapshotState: Int64
    let snapshotReason: String?
    switch result.snapshotInventory {
    case .known:
        snapshotState = 0
        snapshotReason = nil
    case let .notPublished(reason):
        snapshotState = 1
        snapshotReason = reason
    case .notAttributable:
        snapshotState = 2
        snapshotReason = nil
    }
    try bindInt64(snapshotState, at: 4, statement: statement)
    if let snapshotReason {
        try bindText(snapshotReason, at: 5, statement: statement)
    } else {
        try bindNull(at: 5, statement: statement)
    }
    try stepDone(statement, database: database)
    return sqlite3_last_insert_rowid(database)
}

private func insertSnapshots(
    database: OpaquePointer,
    scanID: Int64,
    inventory: Measurement<[LocalSnapshot]>,
    manifests: Measurement<[SnapshotExtentManifest]>
) throws {
    guard case let .known(snapshots, _) = inventory else {
        return
    }
    let statement = try prepare(
        database: database,
        sql: "INSERT INTO snapshots(scan_id, id, name) VALUES (?, ?, ?)"
    )
    defer { sqlite3_finalize(statement) }
    for (index, snapshot) in snapshots.enumerated() {
        sqlite3_reset(statement)
        sqlite3_clear_bindings(statement)
        try bindInt64(scanID, at: 1, statement: statement)
        try bindInt64(Int64(index), at: 2, statement: statement)
        try bindText(snapshot.name, at: 3, statement: statement)
        try stepDone(statement, database: database)
    }

    guard case let .known(snapshotManifests, _) = manifests else {
        return
    }
    let identifiers = Dictionary(
        uniqueKeysWithValues: snapshots.enumerated().map {
            ($0.element.name, $0.offset)
        }
    )
    let extentStatement = try prepare(
        database: database,
        sql: """
            INSERT INTO snapshot_extents(
                scan_id, snapshot_id, ordinal,
                device, device_offset, length
            ) VALUES (?, ?, ?, ?, ?, ?)
            """
    )
    defer { sqlite3_finalize(extentStatement) }
    for manifest in snapshotManifests {
        guard let snapshotID = identifiers[manifest.snapshotName] else {
            throw StorageIndexError.invalidScan(
                reason: "A snapshot manifest is absent from the inventory"
            )
        }
        for (ordinal, extent) in manifest.physicalExtents.enumerated() {
            sqlite3_reset(extentStatement)
            sqlite3_clear_bindings(extentStatement)
            try bindInt64(scanID, at: 1, statement: extentStatement)
            try bindInt64(
                Int64(snapshotID),
                at: 2,
                statement: extentStatement
            )
            try bindInt64(
                Int64(ordinal),
                at: 3,
                statement: extentStatement
            )
            try bindUInt64(
                extent.device,
                at: 4,
                statement: extentStatement
            )
            try bindUInt64(
                extent.deviceOffset,
                at: 5,
                statement: extentStatement
            )
            try bindUInt64(
                extent.length,
                at: 6,
                statement: extentStatement
            )
            try stepDone(extentStatement, database: database)
        }
    }
}

private func insertComponents(
    database: OpaquePointer,
    scanID: Int64,
    accounting: StorageAccountingSnapshot
) throws {
    let statement = try prepare(
        database: database,
        sql: "INSERT INTO components(scan_id, id, value) VALUES (?, ?, ?)"
    )
    defer { sqlite3_finalize(statement) }
    for (index, component) in accounting.pathComponents.enumerated() {
        sqlite3_reset(statement)
        sqlite3_clear_bindings(statement)
        try bindInt64(scanID, at: 1, statement: statement)
        try bindInt64(Int64(index), at: 2, statement: statement)
        try bindText(component, at: 3, statement: statement)
        try stepDone(statement, database: database)
    }
}

private func insertNodes(
    database: OpaquePointer,
    scanID: Int64,
    result: StorageEngineResult,
    accounting: StorageAccountingSnapshot
) throws {
    let entries = result.entries.sorted { $0.path < $1.path }
    guard entries.count == accounting.nodes.count else {
        throw StorageIndexError.invalidScan(
            reason: "The accounting tree and entry list have different sizes"
        )
    }

    let inspectedByPath = Dictionary(
        uniqueKeysWithValues: result.inspectedFiles.map {
            ($0.entry.path, $0)
        }
    )
    let statement = try prepare(
        database: database,
        sql: """
            INSERT INTO nodes(
                scan_id, id, parent_id, component_id, kind,
                device, inode, hard_link_count,
                logical_size, allocated_size, exclusive_size, subtree_size,
                modified_seconds, modified_nanoseconds, is_dataless,
                clone_id, clone_reference_count
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """
    )
    defer { sqlite3_finalize(statement) }

    for (index, entry) in entries.enumerated() {
        let node = accounting.nodes[index]
        guard node.id.rawValue == UInt32(index) else {
            throw StorageIndexError.invalidScan(
                reason: "Accounting node identifiers are not contiguous"
            )
        }
        let logicalSize = try known(entry.logicalSize, name: "logical size")
        let allocatedSize = try known(
            entry.sizeOnDisk,
            name: "allocated size"
        )
        let exclusiveSize = try known(
            node.exclusiveSizeOnDisk,
            name: "exclusive size"
        )
        let subtreeSize = try known(
            node.subtreeSizeOnDisk,
            name: "subtree size"
        )
        let modified = try known(
            entry.modificationTime,
            name: "modification time"
        )

        sqlite3_reset(statement)
        sqlite3_clear_bindings(statement)
        try bindInt64(scanID, at: 1, statement: statement)
        try bindInt64(Int64(index), at: 2, statement: statement)
        if let parentID = node.parentID {
            try bindInt64(
                Int64(parentID.rawValue),
                at: 3,
                statement: statement
            )
        } else {
            try bindNull(at: 3, statement: statement)
        }
        try bindInt64(
            Int64(node.componentID.rawValue),
            at: 4,
            statement: statement
        )
        try bindInt64(
            Int64(storageKindCode(entry.kind)),
            at: 5,
            statement: statement
        )
        try bindUInt64(entry.identity.device, at: 6, statement: statement)
        try bindUInt64(entry.identity.inode, at: 7, statement: statement)
        try bindUInt64(entry.hardLinkCount, at: 8, statement: statement)
        try bindUInt64(logicalSize, at: 9, statement: statement)
        try bindUInt64(allocatedSize, at: 10, statement: statement)
        try bindUInt64(exclusiveSize, at: 11, statement: statement)
        try bindUInt64(subtreeSize, at: 12, statement: statement)
        try bindInt64(
            modified.secondsSinceEpoch,
            at: 13,
            statement: statement
        )
        try bindInt64(
            Int64(modified.nanoseconds),
            at: 14,
            statement: statement
        )
        try bindInt64(entry.isDataless ? 1 : 0, at: 15, statement: statement)

        if
            let inspected = inspectedByPath[entry.path],
            case let .known(metadata, _) = inspected.extents.cloneMetadata
        {
            try bindUInt64(metadata.identifier, at: 16, statement: statement)
            try bindInt64(
                Int64(metadata.referenceCount),
                at: 17,
                statement: statement
            )
        } else {
            try bindNull(at: 16, statement: statement)
            try bindNull(at: 17, statement: statement)
        }
        try stepDone(statement, database: database)
    }
}

private func insertFamilies(
    database: OpaquePointer,
    scanID: Int64,
    accounting: StorageAccountingSnapshot
) throws {
    var nodeIDByPath: [String: StorageNodeID] = [:]
    for node in accounting.nodes {
        guard let path = accounting.path(for: node.id) else {
            throw StorageIndexError.invalidScan(
                reason: "An accounting node path cannot be reconstructed"
            )
        }
        nodeIDByPath[path] = node.id
    }

    let familyStatement = try prepare(
        database: database,
        sql: """
            INSERT INTO families(
                scan_id, id, credited_node_id, size_on_disk,
                outside_state, outside_value,
                freeable_state, freeable_measured, freeable_explained
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            """
    )
    defer { sqlite3_finalize(familyStatement) }
    let memberStatement = try prepare(
        database: database,
        sql: """
            INSERT INTO family_members(scan_id, family_id, node_id)
            VALUES (?, ?, ?)
            """
    )
    defer { sqlite3_finalize(memberStatement) }

    for (familyIndex, family) in accounting.cloneFamilies.enumerated() {
        guard
            let creditedNodeID = nodeIDByPath[family.creditedAtPath]
        else {
            throw StorageIndexError.invalidScan(
                reason: "A family credit path is missing from the node index"
            )
        }
        let size = try known(family.sizeOnDisk, name: "family size")
        let outside = encodeBoolMeasurement(family.hasMemberOutsideScan)
        let freeable = encodeUIntMeasurement(
            family.freedIfDeletingTogether
        )

        sqlite3_reset(familyStatement)
        sqlite3_clear_bindings(familyStatement)
        try bindInt64(scanID, at: 1, statement: familyStatement)
        try bindInt64(
            Int64(familyIndex),
            at: 2,
            statement: familyStatement
        )
        try bindInt64(
            Int64(creditedNodeID.rawValue),
            at: 3,
            statement: familyStatement
        )
        try bindUInt64(size, at: 4, statement: familyStatement)
        try bindInt64(
            Int64(outside.state),
            at: 5,
            statement: familyStatement
        )
        try bindOptionalInt64(
            outside.value,
            at: 6,
            statement: familyStatement
        )
        try bindInt64(
            Int64(freeable.state),
            at: 7,
            statement: familyStatement
        )
        try bindOptionalUInt64(
            freeable.measured,
            at: 8,
            statement: familyStatement
        )
        try bindOptionalUInt64(
            freeable.explained,
            at: 9,
            statement: familyStatement
        )
        try stepDone(familyStatement, database: database)

        for memberPath in family.memberPaths {
            guard let memberID = nodeIDByPath[memberPath] else {
                throw StorageIndexError.invalidScan(
                    reason: "A family member is missing from the node index"
                )
            }
            sqlite3_reset(memberStatement)
            sqlite3_clear_bindings(memberStatement)
            try bindInt64(scanID, at: 1, statement: memberStatement)
            try bindInt64(
                Int64(familyIndex),
                at: 2,
                statement: memberStatement
            )
            try bindInt64(
                Int64(memberID.rawValue),
                at: 3,
                statement: memberStatement
            )
            try stepDone(memberStatement, database: database)
        }
    }
}

private func currentSchemaVersion(database: OpaquePointer) throws -> Int32 {
    try scalarInt32(database: database, sql: "PRAGMA user_version")
}

private func scalarInt32(
    database: OpaquePointer,
    sql: String
) throws -> Int32 {
    let statement = try prepare(database: database, sql: sql)
    defer { sqlite3_finalize(statement) }
    let stepCode = sqlite3_step(statement)
    guard stepCode == SQLITE_ROW else {
        throw sqliteError(database: database, code: stepCode)
    }
    return sqlite3_column_int(statement, 0)
}

private func storageKindCode(_ kind: StorageEntryKind) -> Int32 {
    switch kind {
    case .regularFile:
        return 1
    case .directory:
        return 2
    case .symbolicLink:
        return 3
    case .other:
        return 4
    }
}

private func storageKind(code: Int32) throws -> StorageEntryKind {
    switch code {
    case 1:
        return .regularFile
    case 2:
        return .directory
    case 3:
        return .symbolicLink
    case 4:
        return .other
    default:
        throw StorageIndexError.invalidScan(
            reason: "The index contains an invalid storage kind"
        )
    }
}

private struct EncodedBoolMeasurement {
    let state: Int32
    let value: Int64?
}

private func encodeBoolMeasurement(
    _ measurement: Measurement<Bool>
) -> EncodedBoolMeasurement {
    switch measurement {
    case let .known(value, _):
        return EncodedBoolMeasurement(state: 0, value: value ? 1 : 0)
    case .notPublished:
        return EncodedBoolMeasurement(state: 1, value: nil)
    case let .notAttributable(measured, explained):
        return EncodedBoolMeasurement(
            state: 2,
            value: measured == explained ? 1 : 0
        )
    }
}

private struct EncodedUIntMeasurement {
    let state: Int32
    let measured: UInt64?
    let explained: UInt64?
}

private func encodeUIntMeasurement(
    _ measurement: Measurement<UInt64>
) -> EncodedUIntMeasurement {
    switch measurement {
    case let .known(value, _):
        return EncodedUIntMeasurement(
            state: 0,
            measured: value,
            explained: nil
        )
    case .notPublished:
        return EncodedUIntMeasurement(
            state: 1,
            measured: nil,
            explained: nil
        )
    case let .notAttributable(measured, explained):
        return EncodedUIntMeasurement(
            state: 2,
            measured: measured,
            explained: explained
        )
    }
}

private func known<Value: Sendable>(
    _ measurement: Measurement<Value>,
    name: String
) throws -> Value {
    guard case let .known(value, _) = measurement else {
        throw StorageIndexError.invalidScan(
            reason: "The \(name) is not known"
        )
    }
    return value
}

private func execute(database: OpaquePointer, sql: String) throws {
    var errorMessage: UnsafeMutablePointer<CChar>?
    let code = sqlite3_exec(database, sql, nil, nil, &errorMessage)
    guard code == SQLITE_OK else {
        let message = errorMessage.map { String(cString: $0) } ??
            sqliteMessage(from: database)
        sqlite3_free(errorMessage)
        throw StorageIndexError.sqlite(code: code, message: message)
    }
}

private func ensureColumn(
    database: OpaquePointer,
    table: String,
    name: String,
    definition: String
) throws {
    let statement = try prepare(
        database: database,
        sql: "PRAGMA table_info(\(table))"
    )
    defer { sqlite3_finalize(statement) }
    var exists = false
    while true {
        let code = sqlite3_step(statement)
        if code == SQLITE_DONE {
            break
        }
        guard code == SQLITE_ROW else {
            throw sqliteError(database: database, code: code)
        }
        guard let columnName = sqlite3_column_text(statement, 1) else {
            continue
        }
        if String(cString: columnName) == name {
            exists = true
            break
        }
    }
    if !exists {
        try execute(
            database: database,
            sql: "ALTER TABLE \(table) ADD COLUMN \(name) \(definition)"
        )
    }
}

private func prepare(
    database: OpaquePointer,
    sql: String
) throws -> OpaquePointer {
    var statement: OpaquePointer?
    let code = sqlite3_prepare_v2(database, sql, -1, &statement, nil)
    guard code == SQLITE_OK, let statement else {
        throw sqliteError(database: database, code: code)
    }
    return statement
}

private func bindText(
    _ value: String,
    at index: Int32,
    statement: OpaquePointer
) throws {
    let transient = unsafeBitCast(
        -1,
        to: sqlite3_destructor_type.self
    )
    let code = value.withCString {
        sqlite3_bind_text(statement, index, $0, -1, transient)
    }
    guard code == SQLITE_OK else {
        throw StorageIndexError.sqlite(
            code: code,
            message: "Could not bind text parameter \(index)"
        )
    }
}

private func bindInt64(
    _ value: Int64,
    at index: Int32,
    statement: OpaquePointer
) throws {
    let code = sqlite3_bind_int64(statement, index, value)
    guard code == SQLITE_OK else {
        throw StorageIndexError.sqlite(
            code: code,
            message: "Could not bind integer parameter \(index)"
        )
    }
}

private func bindUInt64(
    _ value: UInt64,
    at index: Int32,
    statement: OpaquePointer
) throws {
    try bindInt64(
        Int64(bitPattern: value),
        at: index,
        statement: statement
    )
}

private func bindNull(
    at index: Int32,
    statement: OpaquePointer
) throws {
    let code = sqlite3_bind_null(statement, index)
    guard code == SQLITE_OK else {
        throw StorageIndexError.sqlite(
            code: code,
            message: "Could not bind null parameter \(index)"
        )
    }
}

private func bindOptionalInt64(
    _ value: Int64?,
    at index: Int32,
    statement: OpaquePointer
) throws {
    if let value {
        try bindInt64(value, at: index, statement: statement)
    } else {
        try bindNull(at: index, statement: statement)
    }
}

private func bindOptionalUInt64(
    _ value: UInt64?,
    at index: Int32,
    statement: OpaquePointer
) throws {
    if let value {
        try bindUInt64(value, at: index, statement: statement)
    } else {
        try bindNull(at: index, statement: statement)
    }
}

private func check(
    _ code: Int32,
    database: OpaquePointer
) throws {
    guard code == SQLITE_OK else {
        throw sqliteError(database: database, code: code)
    }
}

private func stepDone(
    _ statement: OpaquePointer,
    database: OpaquePointer
) throws {
    let code = sqlite3_step(statement)
    guard code == SQLITE_DONE else {
        throw sqliteError(database: database, code: code)
    }
}

private func sqliteError(
    database: OpaquePointer,
    code: Int32
) -> StorageIndexError {
    StorageIndexError.sqlite(
        code: code,
        message: sqliteMessage(from: database)
    )
}

private func sqliteMessage(from database: OpaquePointer?) -> String {
    guard let database, let message = sqlite3_errmsg(database) else {
        return "SQLite did not publish an error message"
    }
    return String(cString: message)
}
