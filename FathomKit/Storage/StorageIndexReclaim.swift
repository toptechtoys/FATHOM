import CSQLite
import Darwin
import Foundation

public struct StorageIndexReclamation: Sendable, Equatable {
    public let beforeBytes: UInt64
    public let afterBytes: UInt64

    public var reclaimedBytes: UInt64 {
        beforeBytes >= afterBytes ? beforeBytes - afterBytes : 0
    }

    public init(beforeBytes: UInt64, afterBytes: UInt64) {
        self.beforeBytes = beforeBytes
        self.afterBytes = afterBytes
    }
}

/// Reclaims the write-ahead log an interrupted scan leaves behind.
///
/// **Never remove or truncate a `-wal` file directly.** It holds committed
/// frames the database file does not have yet — on the owner's machine it
/// held the entire schema beside a 4,096-byte database — so deleting it
/// destroys the database. The only safe reclaim is to open the database and
/// let SQLite checkpoint the log back into it, which is all this does.
///
/// It exists because opening alone does not reclaim anything: measured on a
/// byte-identical copy, `open` → `read` left the log at 3,841,203,752 bytes
/// and only `close` brought the file set down to 159,744. A SIGKILL skips
/// that close, and nothing on the next launch opened the index at all — every
/// other opener needs a `StoragePresentation`, which needs a completed scan.
/// So the bytes survived until the user happened to finish another scan.
public enum StorageIndexReclaim {
    /// Every byte the index occupies: the database and the SQLite sidecars.
    ///
    /// Measured live rather than read out of the index, because during a walk
    /// the scanner reads the `-wal` it is at that moment writing, so the
    /// indexed row for that file is a stale instant.
    public static func footprintBytes(indexURL: URL) -> Measurement<UInt64> {
        guard allocatedBytes(atPath: indexURL.path) != nil else {
            return .notPublished(
                reason: "No index has been written on this Mac yet"
            )
        }
        var total: UInt64 = 0
        for path in sidecarPaths(indexURL: indexURL) {
            total &+= allocatedBytes(atPath: path) ?? 0
        }
        return .known(total, source: .statAllocatedBlocks)
    }

    /// Checkpoints a log left behind by an interrupted scan.
    ///
    /// Deliberately opened without `SQLITE_OPEN_CREATE` and without the
    /// schema DDL: this is a pure reclaim, not a migration, and it must not
    /// bring an index into existence on a Mac that has never scanned.
    public static func reclaim(indexURL: URL) throws
        -> StorageIndexReclamation
    {
        guard allocatedBytes(atPath: indexURL.path) != nil else {
            return StorageIndexReclamation(beforeBytes: 0, afterBytes: 0)
        }
        let before = totalBytes(indexURL: indexURL)

        var database: OpaquePointer?
        let code = sqlite3_open_v2(
            indexURL.path,
            &database,
            SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX,
            nil
        )
        guard code == SQLITE_OK, let database else {
            let message = database.map {
                String(cString: sqlite3_errmsg($0))
            } ?? "SQLite could not open the index"
            if let database { sqlite3_close_v2(database) }
            throw StorageIndexError.cannotOpen(
                path: indexURL.path,
                code: code,
                message: message
            )
        }
        // Not retried on busy. A busy checkpoint means another connection
        // holds the log — another FATHOM instance, or a scan this launch has
        // already started — and the right answer is to leave it alone.
        sqlite3_exec(database, "PRAGMA wal_checkpoint(TRUNCATE)", nil, nil, nil)
        sqlite3_close_v2(database)

        return StorageIndexReclamation(
            beforeBytes: before,
            afterBytes: totalBytes(indexURL: indexURL)
        )
    }

    private static func sidecarPaths(indexURL: URL) -> [String] {
        [
            indexURL.path,
            indexURL.path + "-wal",
            indexURL.path + "-shm",
            indexURL.appendingPathExtension("reserve").path
        ]
    }

    private static func totalBytes(indexURL: URL) -> UInt64 {
        sidecarPaths(indexURL: indexURL).reduce(into: UInt64(0)) {
            $0 &+= allocatedBytes(atPath: $1) ?? 0
        }
    }

    /// Allocated blocks, not `st_size`: the honest cost of a file on this
    /// volume, and the same figure every other size in this app is measured
    /// with.
    private static func allocatedBytes(atPath path: String) -> UInt64? {
        var status = stat()
        guard lstat(path, &status) == 0 else { return nil }
        return UInt64(bitPattern: Int64(status.st_blocks)) &* 512
    }
}
