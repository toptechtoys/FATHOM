import Combine
import FathomKit
import Foundation

@MainActor
final class StorageAppModel: ObservableObject {
    enum State {
        case idle
        case scanning
        case result(StoragePresentation)
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var childrenByParent:
        [Int64: [ExplorePresentationRow]] = [:]
    @Published private(set) var expandedDirectoryIDs: Set<Int64> = []
    @Published private(set) var loadingDirectoryIDs: Set<Int64> = []
    @Published private(set) var childLoadFailures: [Int64: String] = [:]
    @Published private(set) var scanProgressMessage =
        "Preparing the volume walk…"
    /// When the running scan started — the one number every scanning screen
    /// can always show while the walk itself has nothing to report yet.
    @Published private(set) var scanStartedAt: Date?
    @Published private(set) var changeMonitoring:
        FathomKit.Measurement<String> = .notPublished(
            reason: "A completed scan is required before live updates start"
        )
    /// What FATHOM's own index costs on the volume FATHOM is measuring. It is
    /// already inside the on-disk total — the walk has no exclusion list —
    /// and this names it rather than leaving gigabytes anonymous under
    /// Application Support.
    @Published private(set) var indexFootprint:
        FathomKit.Measurement<UInt64> = .notPublished(
            reason: "The index has not been measured yet"
        )
    private var continuityRescanPending = false
    private let changeRecorder = FSEventRecorder()
    private var pendingChangePaths: Set<String> = []
    private var changeCoalescingTask: Task<Void, Never>?
    private var incrementalUpdateRunning = false
    private var changeRecording = false
    private var referencePollingTask: Task<Void, Never>?

    /// The one definition of where the index lives. It used to be built
    /// inline inside `performScan`, which meant nothing outside a scan could
    /// name the file — including the reclaim below.
    nonisolated static var indexURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library")
            .appending(path: "Application Support")
            .appending(path: "FATHOM")
            .appending(path: "storage.sqlite")
    }

    /// Reclaims a write-ahead log a killed scan left behind, at launch.
    ///
    /// This is the only place that helps a user who interrupts a scan and
    /// never completes another one: every other opener of the index takes a
    /// `StoragePresentation`, which only exists after a scan finishes, so
    /// before this the bytes simply stayed. On the owner's machine that was
    /// 3.6 GB, of which 3.48 GiB SQLite could never read again.
    ///
    /// Gated on `.idle` so it can never contend with a scan the user has
    /// already started in the first seconds after launch.
    func reclaimInterruptedIndexAtLaunch() {
        guard case .idle = state else { return }
        Task {
            let url = Self.indexURL
            _ = await Task.detached(priority: .utility) {
                try? StorageIndexReclaim.reclaim(indexURL: url)
            }.value
            indexFootprint = StorageIndexReclaim.footprintBytes(
                indexURL: url
            )
        }
    }

    func scanSelectedVolume() {
        if case .scanning = state {
            return
        }
        stopChangeMonitoring()
        childrenByParent = [:]
        expandedDirectoryIDs = []
        loadingDirectoryIDs = []
        childLoadFailures = [:]
        scanProgressMessage = "Walking directory entries and recording allocated sizes…"
        scanStartedAt = Date()
        state = .scanning
        startChangeMonitoring(allowDuringScan: true)
        Task {
            do {
                let presentation = try await Self.performScan { [weak self] message in
                    await self?.setScanProgress(message)
                }
                let historyIndex = try StorageIndex(
                    url: presentation.indexURL
                )
                do {
                    try await historyIndex.recordHistory(
                        StorageHistorySample(
                            volumePath: presentation.volumePath,
                            actuallyFree: presentation.actuallyFree,
                            sizeOnDisk: presentation.sizeOnDisk,
                            freedIfDeleted: presentation.freedIfDeleted,
                            purgeable: presentation.purgeable,
                            topLevel: presentation.historyNodes
                        )
                    )
                    await historyIndex.close()
                } catch {
                    // close() is what checkpoints the log, so it has to run
                    // on the failure path too or a throw here strands the
                    // whole scan's write-ahead log on disk.
                    await historyIndex.close()
                    throw error
                }
                state = .result(presentation)
                indexFootprint = StorageIndexReclaim.footprintBytes(
                    indexURL: presentation.indexURL
                )
                startChangeMonitoring()
                if UserDefaults.standard.bool(
                    forKey: ConsequenceAlertScheduler.directoryPreferenceKey
                ) {
                    _ = await ConsequenceAlertScheduler
                        .evaluateDirectoryGrowth(presentation: presentation)
                }
                if continuityRescanPending {
                    continuityRescanPending = false
                    scanSelectedVolume()
                }
            } catch {
                stopChangeMonitoring()
                state = .failed(String(describing: error))
            }
        }
    }

    func reset() {
        stopChangeMonitoring()
        childrenByParent = [:]
        expandedDirectoryIDs = []
        loadingDirectoryIDs = []
        childLoadFailures = [:]
        scanProgressMessage = "Preparing the volume walk…"
        state = .idle
    }

    func requestContinuityRescan(reason: String) {
        if case .scanning = state {
            continuityRescanPending = true
            return
        }
        scanProgressMessage = reason
        scanSelectedVolume()
    }

    private func setScanProgress(_ message: String) {
        scanProgressMessage = message
    }

    private func startChangeMonitoring(allowDuringScan: Bool = false) {
        if changeRecording {
            scheduleIncrementalRefreshIfNeeded()
            startIndependentPollingIfNeeded()
            return
        }
        if !allowDuringScan {
            guard case .result = state else { return }
        }
        let home = FileManager.default.homeDirectoryForCurrentUser
        let paths = FSEventRecorder.recommendedStoragePaths(home: home)
        guard !paths.isEmpty else {
            changeMonitoring = .notPublished(
                reason: "No curated storage roots exist on this Mac"
            )
            return
        }
        changeRecorder.setEventHandler { [weak self] measurement in
            Task { @MainActor [weak self] in
                self?.receiveStorageChanges(measurement)
            }
        }
        do {
            try changeRecorder.start(paths: paths)
            changeRecording = true
            changeMonitoring = .known(
                "Watching \(paths.count) curated roots",
                source: .fseventsCausalWindow
            )
            startIndependentPollingIfNeeded()
        } catch {
            changeRecorder.setEventHandler(nil)
            changeMonitoring = .notPublished(
                reason: "FSEvents live updates could not start: \(error)"
            )
        }
    }

    private func stopChangeMonitoring() {
        changeCoalescingTask?.cancel()
        changeCoalescingTask = nil
        pendingChangePaths.removeAll()
        incrementalUpdateRunning = false
        referencePollingTask?.cancel()
        referencePollingTask = nil
        changeRecorder.setEventHandler(nil)
        changeRecorder.stop()
        changeRecording = false
    }

    private func startIndependentPollingIfNeeded() {
        guard referencePollingTask == nil,
              case .result = state else { return }
        referencePollingTask = Task { [weak self] in
            var capacityPolls = 0
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(10))
                } catch {
                    return
                }
                guard let self else { return }
                guard !self.incrementalUpdateRunning else { continue }
                guard case let .result(current) = self.state else { return }
                let volumeURL = URL(fileURLWithPath: current.volumePath)
                let capacity = await Task.detached(priority: .utility) {
                    VolumeCapacityReader().read(volumeURL: volumeURL)
                }.value
                guard case let .result(latest) = self.state,
                      !self.incrementalUpdateRunning,
                      latest.scanID == current.scanID else { continue }
                self.state = .result(
                    latest.replacingCapacity(with: capacity)
                )
                capacityPolls += 1
                guard capacityPolls.isMultiple(of: 6),
                      case let .result(referenceBase) = self.state,
                      !self.incrementalUpdateRunning else {
                    continue
                }
                self.incrementalUpdateRunning = true
                do {
                    self.state = .result(
                        try await Self.performReferenceRefresh(
                            presentation: referenceBase
                        )
                    )
                } catch {
                    let reason = "Snapshot and open-file references could not be refreshed: \(error)"
                    if case let .result(stale) = self.state {
                        self.state = .result(
                            stale.invalidatingFreeable(reason: reason)
                        )
                    }
                }
                self.incrementalUpdateRunning = false
                self.scheduleIncrementalRefreshIfNeeded()
            }
        }
    }

    private func receiveStorageChanges(
        _ measurement: FathomKit.Measurement<[FathomFileSystemEvent]>
    ) {
        switch measurement {
        case let .known(events, _):
            let home = FileManager.default.homeDirectoryForCurrentUser
            let roots = events.compactMap { event -> String? in
                guard !FSEventRecorder.isFathomPrivatePath(
                    event.path,
                    home: home
                ) else { return nil }
                let url = URL(fileURLWithPath: event.path)
                    .standardizedFileURL
                var isDirectory: ObjCBool = false
                let exists = FileManager.default.fileExists(
                    atPath: url.path,
                    isDirectory: &isDirectory
                )
                return exists && isDirectory.boolValue
                    ? url.path
                    : url.deletingLastPathComponent().path
            }
            pendingChangePaths.formUnion(roots)
            scheduleIncrementalRefreshIfNeeded()
        case let .notPublished(reason):
            changeRecorder.stop()
            changeRecording = false
            changeMonitoring = .notPublished(reason: reason)
            requestContinuityRescan(reason: reason)
        case .notAttributable:
            let reason = "FSEvents paths are not attributable"
            changeRecorder.stop()
            changeRecording = false
            changeMonitoring = .notPublished(reason: reason)
            requestContinuityRescan(reason: reason)
        }
    }

    private func scheduleIncrementalRefreshIfNeeded() {
        guard !pendingChangePaths.isEmpty,
              changeCoalescingTask == nil,
              !incrementalUpdateRunning,
              case .result = state else { return }
        changeCoalescingTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(2))
            } catch {
                return
            }
            guard let self else { return }
            self.changeCoalescingTask = nil
            await self.applyPendingStorageChanges()
        }
    }

    private func applyPendingStorageChanges() async {
        guard !incrementalUpdateRunning,
              case let .result(presentation) = state,
              !pendingChangePaths.isEmpty else { return }
        incrementalUpdateRunning = true
        let paths = pendingChangePaths
        pendingChangePaths.removeAll()
        changeMonitoring = .known(
            "Refreshing \(paths.count) changed subtree\(paths.count == 1 ? "" : "s")",
            source: .fseventsCausalWindow
        )
        do {
            let refreshed = try await Self.performIncrementalRefresh(
                presentation: presentation,
                roots: paths.map(URL.init(fileURLWithPath:))
            )
            childrenByParent = [:]
            expandedDirectoryIDs = []
            loadingDirectoryIDs = []
            childLoadFailures = [:]
            state = .result(refreshed)
            indexFootprint = StorageIndexReclaim.footprintBytes(
                indexURL: refreshed.indexURL
            )
            changeMonitoring = .known(
                "Up to date after \(paths.count) changed subtree\(paths.count == 1 ? "" : "s")",
                source: .fseventsCausalWindow
            )
        } catch {
            let reason = "Incremental evidence refresh failed: \(error)"
            changeMonitoring = .notPublished(reason: reason)
            incrementalUpdateRunning = false
            requestContinuityRescan(reason: reason)
            return
        }
        incrementalUpdateRunning = false
        scheduleIncrementalRefreshIfNeeded()
    }

    private nonisolated static func performIncrementalRefresh(
        presentation: StoragePresentation,
        roots: [URL]
    ) async throws -> StoragePresentation {
        try await Task.detached(priority: .utility) {
            let index = try StorageIndex(url: presentation.indexURL)
            do {
                _ = try await index.refreshStagedSubtrees(
                    scanID: presentation.scanID,
                    roots: roots
                )
                _ = try await index.inspectStagedExtents(
                    scanID: presentation.scanID
                )
                let accounting = try await index.reduceStagedAccounting(
                    scanID: presentation.scanID
                )
                let volumeURL = URL(fileURLWithPath: presentation.volumePath)
                let capacity = VolumeCapacityReader().read(
                    volumeURL: volumeURL
                )
                let snapshotInventory = try SnapshotInventoryReader()
                    .inventory(forVolumeAt: volumeURL)
                let snapshotCoverage:
                    FathomKit.Measurement<[String]>
                switch snapshotInventory {
                case let .known(snapshots, _):
                    do {
                        snapshotCoverage = try await index
                            .stageSnapshotReferences(
                                scanID: presentation.scanID,
                                volumeURL: volumeURL,
                                snapshots: snapshots,
                                mountPointURL: presentation.indexURL
                                    .deletingLastPathComponent()
                                    .appending(path: "SnapshotMount")
                            )
                    } catch {
                        snapshotCoverage = .notPublished(
                            reason: "Read-only snapshot manifest inspection failed: \(error)"
                        )
                    }
                case let .notPublished(reason):
                    snapshotCoverage = .notPublished(reason: reason)
                case .notAttributable:
                    snapshotCoverage = .notPublished(
                        reason: "Snapshot inventory is not fully attributable"
                    )
                }
                let openFiles = try OpenFileReferenceReader().inventory()
                let freeable = try await index
                    .reduceStagedFreeableAccounting(
                        scanID: presentation.scanID,
                        snapshotInventory: snapshotInventory,
                        snapshotCoverage: snapshotCoverage,
                        openFileIdentities: openFiles.completeIdentities
                    )
                let stagedRows = try await index.stagedChildren(
                    scanID: presentation.scanID,
                    parentID: 0
                )
                let issueCount = try await index.stagedIssueCount(
                    scanID: presentation.scanID
                )
                let refreshed = StoragePresentation(
                    scanID: presentation.scanID,
                    indexURL: presentation.indexURL,
                    volumePath: presentation.volumePath,
                    actuallyFree: capacity.actuallyFree,
                    finderAvailable: capacity.finderAvailable,
                    purgeable: capacity.purgeable,
                    sizeOnDisk: accounting.sizeOnDisk,
                    freedIfDeleted: freeable.freedIfDeleted,
                    snapshotInventory: snapshotInventory,
                    snapshotCoverage: snapshotCoverage,
                    rows: presentationRows(stagedRows),
                    issueCount: Int(issueCount),
                    scanDuration: presentation.scanDuration
                )
                try await index.recordHistory(
                    StorageHistorySample(
                        volumePath: refreshed.volumePath,
                        actuallyFree: refreshed.actuallyFree,
                        sizeOnDisk: refreshed.sizeOnDisk,
                        freedIfDeleted: refreshed.freedIfDeleted,
                        purgeable: refreshed.purgeable,
                        topLevel: refreshed.historyNodes
                    ),
                    coalescingWithin: 3_600
                )
                await index.close()
                return refreshed
            } catch {
                await index.close()
                throw error
            }
        }.value
    }

    private nonisolated static func performReferenceRefresh(
        presentation: StoragePresentation
    ) async throws -> StoragePresentation {
        try await Task.detached(priority: .utility) {
            let index = try StorageIndex(url: presentation.indexURL)
            do {
                let volumeURL = URL(fileURLWithPath: presentation.volumePath)
                let snapshotInventory = try SnapshotInventoryReader()
                    .inventory(forVolumeAt: volumeURL)
                let snapshotCoverage:
                    FathomKit.Measurement<[String]>
                switch snapshotInventory {
                case let .known(snapshots, _):
                    do {
                        snapshotCoverage = try await index
                            .stageSnapshotReferences(
                                scanID: presentation.scanID,
                                volumeURL: volumeURL,
                                snapshots: snapshots,
                                mountPointURL: presentation.indexURL
                                    .deletingLastPathComponent()
                                    .appending(path: "SnapshotMount")
                            )
                    } catch {
                        snapshotCoverage = .notPublished(
                            reason: "Read-only snapshot manifest inspection failed: \(error)"
                        )
                    }
                case let .notPublished(reason):
                    snapshotCoverage = .notPublished(reason: reason)
                case .notAttributable:
                    snapshotCoverage = .notPublished(
                        reason: "Snapshot inventory is not fully attributable"
                    )
                }
                let openFiles = try OpenFileReferenceReader().inventory()
                let freeable = try await index
                    .reduceStagedFreeableAccounting(
                        scanID: presentation.scanID,
                        snapshotInventory: snapshotInventory,
                        snapshotCoverage: snapshotCoverage,
                        openFileIdentities: openFiles.completeIdentities
                    )
                let stagedRows = try await index.stagedChildren(
                    scanID: presentation.scanID,
                    parentID: 0
                )
                await index.close()
                return StoragePresentation(
                    scanID: presentation.scanID,
                    indexURL: presentation.indexURL,
                    volumePath: presentation.volumePath,
                    actuallyFree: presentation.actuallyFree,
                    finderAvailable: presentation.finderAvailable,
                    purgeable: presentation.purgeable,
                    sizeOnDisk: presentation.sizeOnDisk,
                    freedIfDeleted: freeable.freedIfDeleted,
                    snapshotInventory: snapshotInventory,
                    snapshotCoverage: snapshotCoverage,
                    rows: presentationRows(stagedRows),
                    issueCount: presentation.issueCount,
                    scanDuration: presentation.scanDuration
                )
            } catch {
                await index.close()
                throw error
            }
        }.value
    }

    func toggleDirectory(_ row: ExplorePresentationRow) {
        guard row.kind == .directory else {
            return
        }
        if expandedDirectoryIDs.remove(row.id) != nil {
            return
        }
        expandedDirectoryIDs.insert(row.id)
        childLoadFailures[row.id] = nil
        guard childrenByParent[row.id] == nil else {
            return
        }
        guard case let .result(presentation) = state else {
            return
        }
        loadingDirectoryIDs.insert(row.id)
        Task {
            do {
                let index = try StorageIndex(url: presentation.indexURL)
                let stagedRows: [StagedStorageNodeSummary]
                do {
                    stagedRows = try await index.stagedChildren(
                        scanID: presentation.scanID,
                        parentID: row.id
                    )
                    await index.close()
                } catch {
                    await index.close()
                    throw error
                }
                childrenByParent[row.id] = Self.presentationRows(
                    stagedRows
                )
            } catch {
                childrenByParent[row.id] = []
                childLoadFailures[row.id] =
                    "Contents not published: \(error)"
            }
            loadingDirectoryIDs.remove(row.id)
        }
    }

    private nonisolated static func performScan(
        progress: @escaping @Sendable (String) async -> Void
    ) async throws
        -> StoragePresentation
    {
        let homeURL = FileManager.default.homeDirectoryForCurrentUser
        let values = try homeURL.resourceValues(forKeys: [.volumeURLKey])
        guard let volumeURL = values.volume else {
            throw StoragePresentationError.volumeNotPublished
        }

        return try await Task.detached(priority: .userInitiated) {
            let scanStarted = ContinuousClock.now
            let indexURL = Self.indexURL
            let snapshotMountPoint = homeURL
                .appending(path: "Library")
                .appending(path: "Application Support")
                .appending(path: "FATHOM")
                .appending(path: "SnapshotMount")
            let resilientIndex = ResilientStorageIndex(
                configuration: StorageIndexPersistenceConfiguration(
                    primaryURL: indexURL
                )
            )
            switch resilientIndex.reserveInitialBudget() {
            case .reserved:
                break
            case let .notReserved(reason):
                throw StoragePresentationError.indexUnavailable(reason)
            }
            if let reason =
                resilientIndex.releaseInitialBudgetForStagedScan()
            {
                throw StoragePresentationError.indexUnavailable(reason)
            }
            let index: StorageIndex
            do {
                let candidate = try StorageIndex(url: indexURL)
                let integrity = try await candidate.integrityCheck()
                guard integrity == "ok" else {
                    await candidate.close()
                    throw StorageIndexError.integrityFailure(
                        message: integrity
                    )
                }
                index = candidate
            } catch {
                guard StorageIndexRecovery.isCorruption(error) else {
                    throw error
                }
                _ = try StorageIndexRecovery.quarantine(indexURL: indexURL)
                await progress(
                    "Index was corrupt. Its files and history were preserved in quarantine; rebuilding from this scan…"
                )
                index = try StorageIndex(url: indexURL)
            }
            do {
                let traversal = try await index.stageTraversal(
                    at: volumeURL,
                    scope: .wholeVolume
                )
                await progress(
                    "Found \(traversal.entryCount.formatted()) entries; mapping sparse and shared physical extents…"
                )
                let extentSummary = try await index.inspectStagedExtents(
                    scanID: traversal.scanID
                )
                await progress(
                    "Mapped \(extentSummary.inspectedFileCount.formatted()) files; reducing clone and hard-link families…"
                )
                let accounting = try await index.reduceStagedAccounting(
                    scanID: traversal.scanID
                )
                let capacity = VolumeCapacityReader().read(
                    volumeURL: volumeURL
                )

                let snapshotInventory =
                    try SnapshotInventoryReader().inventory(
                        forVolumeAt: volumeURL
                    )
                await progress(
                    "Physical totals are exact; checking snapshot-held ranges…"
                )
                let snapshotCoverage:
                    FathomKit.Measurement<[String]>
                switch snapshotInventory {
                case let .known(snapshots, _):
                    do {
                        snapshotCoverage =
                            try await index.stageSnapshotReferences(
                                scanID: traversal.scanID,
                                volumeURL: volumeURL,
                                snapshots: snapshots,
                                mountPointURL: snapshotMountPoint
                            )
                    } catch {
                        snapshotCoverage = .notPublished(
                            reason: "Read-only snapshot manifest inspection failed: \(error)"
                        )
                    }
                case let .notPublished(reason):
                    snapshotCoverage = .notPublished(reason: reason)
                case .notAttributable:
                    snapshotCoverage = .notPublished(
                        reason: "Snapshot inventory is not fully attributable"
                    )
                }

                let openFileReferences =
                    try OpenFileReferenceReader().inventory()
                await progress(
                    "Checking live file descriptors before publishing freeable bytes…"
                )
                let freeable = try await index
                    .reduceStagedFreeableAccounting(
                        scanID: traversal.scanID,
                        snapshotInventory: snapshotInventory,
                        snapshotCoverage: snapshotCoverage,
                        openFileIdentities:
                            openFileReferences.completeIdentities
                    )
                let stagedRows = try await index.stagedChildren(
                    scanID: traversal.scanID,
                    parentID: 0
                )
                let rows = presentationRows(stagedRows)
                await progress("Writing the completed evidence set…")
                let elapsed = scanStarted.duration(to: .now).components
                let seconds = Double(elapsed.seconds) +
                    Double(elapsed.attoseconds) / 1_000_000_000_000_000_000
                try await index.setDiagnosticValue(
                    String(format: "%.6f", seconds),
                    forKey: "last_scan_duration_seconds"
                )
                await index.close()
                return StoragePresentation(
                    scanID: traversal.scanID,
                    indexURL: indexURL,
                    volumePath: volumeURL.path,
                    actuallyFree: capacity.actuallyFree,
                    finderAvailable: capacity.finderAvailable,
                    purgeable: capacity.purgeable,
                    sizeOnDisk: accounting.sizeOnDisk,
                    freedIfDeleted: freeable.freedIfDeleted,
                    snapshotInventory: snapshotInventory,
                    snapshotCoverage: snapshotCoverage,
                    rows: rows,
                    issueCount: traversal.issues.count +
                        Int(extentSummary.failedFileCount),
                    scanDuration: .seconds(seconds)
                )
            } catch {
                await index.close()
                throw error
            }
        }.value
    }

    private nonisolated static func presentationRows(
        _ rows: [StagedStorageNodeSummary]
    ) -> [ExplorePresentationRow] {
        rows.map {
            ExplorePresentationRow(
                id: $0.id,
                name: $0.name,
                path: $0.path,
                kind: $0.kind,
                sizeOnDisk: $0.sizeOnDisk,
                freedIfDeleted: $0.freedIfDeleted
            )
        }
        .sorted {
            compareStorageMeasurements(
                $0.freedIfDeleted,
                $1.freedIfDeleted,
                leftName: $0.name,
                rightName: $1.name
            )
        }
    }
}

struct StoragePresentation: Sendable {
    let scanID: Int64
    let indexURL: URL
    let volumePath: String
    let actuallyFree: FathomKit.Measurement<UInt64>
    let finderAvailable: FathomKit.Measurement<UInt64>
    let purgeable: FathomKit.Measurement<UInt64>
    let sizeOnDisk: FathomKit.Measurement<UInt64>
    let freedIfDeleted: FathomKit.Measurement<UInt64>
    let snapshotInventory: FathomKit.Measurement<[LocalSnapshot]>
    let snapshotCoverage: FathomKit.Measurement<[String]>
    let rows: [ExplorePresentationRow]
    let issueCount: Int
    /// How long the scan that produced this actually took.
    ///
    /// Rule 5 says an action states its cost before it runs, and "Scan again"
    /// discards this result to re-read every file. The honest cost is the time
    /// it took last time, measured — not an estimate, and not silence.
    let scanDuration: Duration

    var historyNodes: [StorageHistoryNode] {
        rows.map {
            StorageHistoryNode(
                path: $0.path,
                name: $0.name,
                sizeOnDisk: $0.sizeOnDisk,
                freedIfDeleted: $0.freedIfDeleted
            )
        }
    }

    func replacingCapacity(
        with capacity: VolumeCapacitySnapshot
    ) -> StoragePresentation {
        StoragePresentation(
            scanID: scanID,
            indexURL: indexURL,
            volumePath: volumePath,
            actuallyFree: capacity.actuallyFree,
            finderAvailable: capacity.finderAvailable,
            purgeable: capacity.purgeable,
            sizeOnDisk: sizeOnDisk,
            freedIfDeleted: freedIfDeleted,
            snapshotInventory: snapshotInventory,
            snapshotCoverage: snapshotCoverage,
            rows: rows,
            issueCount: issueCount,
            scanDuration: scanDuration
        )
    }

    func invalidatingFreeable(reason: String) -> StoragePresentation {
        StoragePresentation(
            scanID: scanID,
            indexURL: indexURL,
            volumePath: volumePath,
            actuallyFree: actuallyFree,
            finderAvailable: finderAvailable,
            purgeable: purgeable,
            sizeOnDisk: sizeOnDisk,
            freedIfDeleted: .notPublished(reason: reason),
            snapshotInventory: .notPublished(reason: reason),
            snapshotCoverage: .notPublished(reason: reason),
            rows: rows.map {
                ExplorePresentationRow(
                    id: $0.id,
                    name: $0.name,
                    path: $0.path,
                    kind: $0.kind,
                    sizeOnDisk: $0.sizeOnDisk,
                    freedIfDeleted: .notPublished(reason: reason)
                )
            },
            issueCount: issueCount,
            scanDuration: scanDuration
        )
    }
}

struct ExplorePresentationRow: Identifiable, Sendable {
    let id: Int64
    let name: String
    let path: String
    let kind: StorageEntryKind
    let sizeOnDisk: FathomKit.Measurement<UInt64>
    let freedIfDeleted: FathomKit.Measurement<UInt64>
}

private enum StoragePresentationError: Error {
    case volumeNotPublished
    case indexUnavailable(String)
}

private func compareStorageMeasurements(
    _ left: FathomKit.Measurement<UInt64>,
    _ right: FathomKit.Measurement<UInt64>,
    leftName: String,
    rightName: String
) -> Bool {
    switch (left, right) {
    case let (.known(leftValue, _), .known(rightValue, _)):
        if leftValue != rightValue {
            return leftValue > rightValue
        }
    case (.known, _):
        return true
    case (_, .known):
        return false
    case (.notAttributable, .notPublished):
        return true
    case (.notPublished, .notAttributable):
        return false
    case (.notAttributable, .notAttributable),
         (.notPublished, .notPublished):
        break
    }
    return leftName.localizedStandardCompare(rightName) == .orderedAscending
}
