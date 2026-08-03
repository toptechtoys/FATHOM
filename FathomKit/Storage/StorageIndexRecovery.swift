import CSQLite
import Foundation

public struct StorageIndexQuarantine: Sendable, Equatable {
    public let directoryURL: URL
    public let preservedURLs: [URL]

    public init(directoryURL: URL, preservedURLs: [URL]) {
        self.directoryURL = directoryURL
        self.preservedURLs = preservedURLs
    }
}

public enum StorageIndexRecovery {
    public static func isCorruption(_ error: Error) -> Bool {
        switch error {
        case StorageIndexError.integrityFailure:
            return true
        case let StorageIndexError.cannotOpen(_, code, _),
             let StorageIndexError.sqlite(code, _):
            let primaryCode = code & 0xFF
            return primaryCode == SQLITE_CORRUPT ||
                primaryCode == SQLITE_NOTADB
        default:
            return false
        }
    }

    /// Moves the regenerable index and its SQLite sidecars into a unique
    /// sibling directory. Nothing is deleted and unrelated files—including
    /// the reclaim journal—are never considered.
    public static func quarantine(indexURL: URL) throws
        -> StorageIndexQuarantine
    {
        let parent = indexURL.deletingLastPathComponent()
        let quarantine = parent.appending(
            path: "Corrupt Index \(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(
            at: quarantine,
            withIntermediateDirectories: false
        )
        let candidates = [
            indexURL,
            URL(fileURLWithPath: indexURL.path + "-wal"),
            URL(fileURLWithPath: indexURL.path + "-shm"),
        ]
        var preserved: [URL] = []
        do {
            for source in candidates where FileManager.default.fileExists(
                atPath: source.path
            ) {
                let destination = quarantine.appending(
                    path: source.lastPathComponent
                )
                try FileManager.default.moveItem(
                    at: source,
                    to: destination
                )
                preserved.append(destination)
            }
        } catch {
            // Best-effort rollback keeps the operation recoverable.
            for destination in preserved.reversed() {
                try? FileManager.default.moveItem(
                    at: destination,
                    to: parent.appending(path: destination.lastPathComponent)
                )
            }
            throw error
        }
        return StorageIndexQuarantine(
            directoryURL: quarantine,
            preservedURLs: preserved
        )
    }
}
