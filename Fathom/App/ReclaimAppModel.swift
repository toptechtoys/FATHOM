import Combine
import FathomKit
import Foundation

struct ReclaimGroupPresentation: Sendable, Identifiable {
    let recipe: ReclaimDetectionRecipe
    let entries: [StorageEntry]
    let sizeOnDisk: FathomKit.Measurement<UInt64>
    let freedIfDeleted: FathomKit.Measurement<UInt64>

    var id: String { recipe.identifier }
}

@MainActor
final class ReclaimAppModel: ObservableObject {
    enum State {
        case idle
        case loading
        case result([ReclaimGroupPresentation])
        case review(ReclaimDryRun)
        case executing(ReclaimDryRun)
        case report(ReclaimExecutionReport)
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var recovery:
        FathomKit.Measurement<[InterruptedReclaimIntent]>

    init() {
        recovery = ReclaimJournalRecoveryReader.read(
            at: Self.journalURL
        )
    }

    func load(from storage: StoragePresentation) {
        guard case .idle = state else { return }
        state = .loading
        Task {
            do {
                state = .result(try await Self.groups(from: storage))
            } catch {
                state = .failed("Reclaim recipes are not published: \(error)")
            }
        }
    }

    func prepare(_ group: ReclaimGroupPresentation) {
        do {
            let recipe = try group.recipe.actionRecipe()
            state = .review(
                ReclaimEngine().dryRun(
                    entries: group.entries,
                    recipe: recipe
                )
            )
        } catch {
            state = .failed("Dry run failed: \(error)")
        }
    }

    func execute(_ dryRun: ReclaimDryRun) {
        state = .executing(dryRun)
        Task {
            do {
                let report = try await Task.detached(priority: .userInitiated) {
                    return try ReclaimEngine().execute(
                        dryRun.manifest,
                        journalURL: Self.journalURL
                    )
                }.value
                recovery = ReclaimJournalRecoveryReader.read(
                    at: Self.journalURL
                )
                state = .report(report)
            } catch {
                state = .failed("Nothing was moved: \(error)")
            }
        }
    }

    func reset() {
        state = .idle
    }

    func refreshRecovery() {
        recovery = ReclaimJournalRecoveryReader.read(at: Self.journalURL)
    }

    private nonisolated static var journalURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Application Support/FATHOM")
            .appending(path: "reclaim-journal.jsonl")
    }

    private nonisolated static func groups(
        from storage: StoragePresentation
    ) async throws -> [ReclaimGroupPresentation] {
        try await Task.detached(priority: .utility) {
            let catalog = try ReclaimRecipeCatalog.bundled()
            let matches = try catalog.recipes.map { recipe in
                try catalog.match(recipe)
            }
            let paths = matches.flatMap { $0.paths.map(\.path) }
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
            return matches.map { match in
                let candidates = match.paths.compactMap { byPath[$0.path] }
                return ReclaimGroupPresentation(
                    recipe: match.recipe,
                    entries: candidates,
                    sizeOnDisk: sum(candidates.map(\.sizeOnDisk)),
                    freedIfDeleted: sum(candidates.map(\.freedIfDeleted))
                )
            }
        }.value
    }

    private nonisolated static func sum(
        _ values: [FathomKit.Measurement<UInt64>]
    ) -> FathomKit.Measurement<UInt64> {
        var total: UInt64 = 0
        for value in values {
            switch value {
            case let .known(bytes, _):
                let (next, overflow) = total.addingReportingOverflow(bytes)
                guard !overflow else {
                    return .notPublished(reason: "The byte total overflowed")
                }
                total = next
            case let .notPublished(reason):
                return .notPublished(reason: reason)
            case let .notAttributable(measured, explained):
                return .notAttributable(
                    measured: measured,
                    explained: explained
                )
            }
        }
        return .known(total, source: .storageTreeAccounting)
    }
}
