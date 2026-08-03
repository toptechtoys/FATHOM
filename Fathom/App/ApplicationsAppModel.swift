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
            let entries = try await index.stagedReclaimEntries(
                scanID: storage.scanID,
                paths: paths
            )
            await index.close()
            let byPath = Dictionary(uniqueKeysWithValues: entries.map {
                ($0.path, $0)
            })
            return records.map { record in
                let app = byPath[record.url.path]
                let leftovers: [StorageEntry]
                if case let .known(urls, _) = record.exactLeftoverURLs {
                    leftovers = urls.compactMap { byPath[$0.path] }
                } else {
                    leftovers = []
                }
                return ApplicationPresentation(
                    record: record,
                    sizeOnDisk: app?.sizeOnDisk ?? .notPublished(
                        reason: "The app path was absent from the completed scan"
                    ),
                    freedIfDeleted: app?.freedIfDeleted ?? .notPublished(
                        reason: "The app path was absent from the completed scan"
                    ),
                    leftoverSizeOnDisk: sum(leftovers.map(\.sizeOnDisk)),
                    leftoverFreedIfDeleted: sum(
                        leftovers.map(\.freedIfDeleted)
                    )
                )
            }
        }.value
    }

    private nonisolated static func sum(
        _ values: [FathomKit.Measurement<UInt64>]
    ) -> FathomKit.Measurement<UInt64> {
        var result: UInt64 = 0
        for value in values {
            switch value {
            case let .known(bytes, _):
                let (next, overflow) = result.addingReportingOverflow(bytes)
                if overflow { return .notPublished(reason: "Size overflow") }
                result = next
            case let .notPublished(reason):
                return .notPublished(reason: reason)
            case let .notAttributable(measured, explained):
                return .notAttributable(measured: measured, explained: explained)
            }
        }
        return .known(result, source: .storageTreeAccounting)
    }
}
