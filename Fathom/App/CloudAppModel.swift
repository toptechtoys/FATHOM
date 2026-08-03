import Combine
import FathomKit
import Foundation

@MainActor
final class CloudAppModel: ObservableObject {
    enum State {
        case idle
        case scanning
        case result([CloudItemRecord])
        case review(CloudEvictionPlan)
        case executing
        case report([CloudEvictionOutcome])
        case failed(String)
    }

    @Published private(set) var state: State = .idle

    func scan() {
        guard case .idle = state else { return }
        state = .scanning
        Task {
            let measurement = await Task.detached(priority: .utility) {
                CloudItemReader().read()
            }.value
            switch measurement {
            case let .known(records, _): state = .result(records)
            case let .notPublished(reason): state = .failed(reason)
            case .notAttributable:
                state = .failed("Cloud inventory is not attributable")
            }
        }
    }

    func prepare(_ records: [CloudItemRecord]) {
        state = .review(CloudEvictionEngine().dryRun(records))
    }

    func execute(_ plan: CloudEvictionPlan) {
        state = .executing
        Task {
            let outcomes = await Task.detached(priority: .userInitiated) {
                let journal = FileManager.default.homeDirectoryForCurrentUser
                    .appending(path: "Library/Application Support/FATHOM")
                    .appending(path: "cloud-eviction-journal.jsonl")
                return CloudEvictionEngine().execute(
                    plan,
                    journalURL: journal
                )
            }.value
            state = .report(outcomes)
        }
    }

    func reset() { state = .idle }
}
