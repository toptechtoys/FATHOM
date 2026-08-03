import Combine
import FathomKit
import Foundation

@MainActor
final class CommandPaletteModel: ObservableObject {
    enum State {
        case idle
        case loading
        case result(FathomKit.Measurement<[StagedStorageNodeSummary]>)
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    private var task: Task<Void, Never>?

    func search(_ input: String, storage: StoragePresentation?) {
        task?.cancel()
        guard let query = StoragePaletteQuery.parse(input) else {
            state = .idle
            return
        }
        guard let storage else {
            state = .result(.notPublished(reason: "Complete a scan to search files"))
            return
        }
        state = .loading
        task = Task {
            do {
                try await Task.sleep(for: .milliseconds(120))
                let index = try StorageIndex(url: storage.indexURL)
                let results = try await index.searchStagedEntries(
                    scanID: storage.scanID,
                    query: query
                )
                await index.close()
                guard !Task.isCancelled else { return }
                state = .result(results)
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                state = .failed(String(describing: error))
            }
        }
    }
}

extension Notification.Name {
    static let fathomShowCommandPalette = Notification.Name(
        "com.exhibinaut.fathom.show-command-palette"
    )
    static let fathomStorageContinuityRescan = Notification.Name(
        "com.exhibinaut.fathom.storage-continuity-rescan"
    )
}
