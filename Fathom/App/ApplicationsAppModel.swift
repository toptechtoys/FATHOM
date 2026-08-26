import Combine
import FathomKit
import Foundation

struct ApplicationPresentation: Sendable, Identifiable {
    let record: ApplicationCatalogRecord
    let sizeOnDisk: FathomKit.Measurement<UInt64>
    let freedIfDeleted: FathomKit.Measurement<UInt64>
    let leftoverSizeOnDisk: FathomKit.Measurement<UInt64>
    let leftoverFreedIfDeleted: FathomKit.Measurement<UInt64>

    var id: String { record.id }
}

@MainActor
final class ApplicationsAppModel: ObservableObject {
    enum State {
        case idle
        case loading
        case result([ApplicationPresentation])
        case failed(String)
    }

    @Published private(set) var state: State = .idle

    func load(from storage: StoragePresentation) {
        guard case .idle = state else { return }
        state = .loading
        Task {
            do {
                state = .result(try await Self.read(storage))
            } catch {
                state = .failed("Application accounting is not published: \(error)")
            }
        }
    }

    private nonisolated static func read(
        _ storage: StoragePresentation
    ) async throws -> [ApplicationPresentation] {
        try await Task.detached(priority: .utility) {
            guard case let .known(records, _) = ApplicationCatalogReader().read()
            else { return [] }
            let paths = records.flatMap { record -> [String] in
                var paths = [record.url.path]
                if case let .known(leftovers, _) = record.exactLeftoverURLs {
                    paths += leftovers.map(\.path)
                }
                return paths
            }
            let index = try StorageIndex(url: storage.indexURL)
            let entries: [StorageEntry]
            do {
                entries = try await index.stagedReclaimEntries(
                    scanID: storage.scanID,
                    paths: paths
                )
                await index.close()
            } catch {
                // close() is what checkpoints the write-ahead log, so a throw
                // between open and close used to leave the log to
                // non-deterministic ARC release.
                await index.close()
                throw error
            }
            let byPath = Dictionary(uniqueKeysWithValues: entries.map {
                ($0.path, $0)
            })
            return records.map { record in
                let app = byPath[record.url.path]
                let leftoverSize: FathomKit.Measurement<UInt64>
                let leftoverFreed: FathomKit.Measurement<UInt64>
                switch record.exactLeftoverURLs {
                case let .known(urls, _):
                    leftoverSize = leftoverSum(urls, byPath) { $0.sizeOnDisk }
                    leftoverFreed = leftoverSum(urls, byPath) {
                        $0.freedIfDeleted
                    }
                case let .notPublished(reason):
                    // No bundle identifier means the leftovers cannot be
                    // matched at all — which is not the same claim as zero
                    // leftovers, and used to be rendered as one.
                    leftoverSize = .notPublished(reason: reason)
                    leftoverFreed = .notPublished(reason: reason)
                case .notAttributable:
                    leftoverSize = .notPublished(
                        reason: "The leftover locations were only partly "
                            + "attributable."
                    )
                    leftoverFreed = .notPublished(
                        reason: "The leftover locations were only partly "
                            + "attributable."
                    )
                }
                return ApplicationPresentation(
                    record: record,
                    sizeOnDisk: app?.sizeOnDisk ?? .notPublished(
                        reason: "The app path was absent from the completed scan"
                    ),
                    freedIfDeleted: app?.freedIfDeleted ?? .notPublished(
                        reason: "The app path was absent from the completed scan"
                    ),
                    leftoverSizeOnDisk: leftoverSize,
                    leftoverFreedIfDeleted: leftoverFreed
                )
            }
        }.value
    }

    /// A leftover location the completed scan did not cover is a gap, not a
    /// zero. The `compactMap` this replaces dropped it silently, so the
    /// leftover figure rendered as known while quietly missing a place the
    /// catalog had just confirmed exists on disk.
    private nonisolated static func leftoverSum(
        _ urls: [URL],
        _ byPath: [String: StorageEntry],
        _ value: (StorageEntry) -> FathomKit.Measurement<UInt64>
    ) -> FathomKit.Measurement<UInt64> {
        FathomKit.Measurement.sum(
            urls.map { url in
                byPath[url.path].map(value) ?? .notPublished(
                    reason: "\(url.path) was not sized by the completed scan."
                )
            },
            source: .storageTreeAccounting
        ) { missing, count in
            "\(missing) of \(count) leftover locations were not sized by "
                + "the completed scan. Run the Deep Scan again to size them."
        }
    }
}
