import Combine
import FathomKit
import Foundation

struct WeeklyDigestPresentation: Sendable {
    let changeInFreeBytes: FathomKit.Measurement<Int64>
    let start: Date?
    let end: Date?
}

@MainActor
final class HistoryAppModel: ObservableObject {
    enum State {
        case idle
        case loading
        case result(
            samples: [StorageHistorySample],
            digest: WeeklyDigestPresentation
        )
        case failed(String)
    }

    @Published private(set) var state: State = .idle

    func load(from storage: StoragePresentation) {
        guard case .idle = state else { return }
        state = .loading
        Task {
            do {
                let samples = try await Task.detached(priority: .utility) {
                    let index = try StorageIndex(url: storage.indexURL)
                    let rows = try await index.historySamples(
                        volumePath: storage.volumePath
                    )
                    await index.close()
                    return rows
                }.value
                state = .result(
                    samples: samples,
                    digest: Self.digest(samples)
                )
            } catch {
                state = .failed("History is not published: \(error)")
            }
        }
    }

    func reset() { state = .idle }

    private nonisolated static func digest(
        _ samples: [StorageHistorySample]
    ) -> WeeklyDigestPresentation {
        guard let first = samples.first, let last = samples.last,
              first.id != last.id else {
            return WeeklyDigestPresentation(
                changeInFreeBytes: .notPublished(
                    reason: "Two completed scans are required"
                ),
                start: samples.first?.wallTimestamp,
                end: samples.last?.wallTimestamp
            )
        }
        let delta: FathomKit.Measurement<Int64>
        switch (first.actuallyFree, last.actuallyFree) {
        case let (.known(start, _), .known(end, _)):
            guard start <= UInt64(Int64.max), end <= UInt64(Int64.max) else {
                delta = .notPublished(reason: "The capacity delta exceeds Int64")
                break
            }
            delta = .known(
                Int64(end) - Int64(start),
                source: .persistedStorageHistoryDelta
            )
        case let (.notPublished(reason), _),
             let (_, .notPublished(reason)):
            delta = .notPublished(reason: reason)
        case (.notAttributable, _), (_, .notAttributable):
            delta = .notPublished(
                reason: "One capacity sample is not attributable"
            )
        }
        return WeeklyDigestPresentation(
            changeInFreeBytes: delta,
            start: first.wallTimestamp,
            end: last.wallTimestamp
        )
    }
}
