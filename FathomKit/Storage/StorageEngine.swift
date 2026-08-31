import Foundation

public struct StorageEngineConfiguration: Sendable, Equatable {
    public let maximumConcurrentExtentReads: Int
    public let snapshotMountPointURL: URL?

    public init(
        maximumConcurrentExtentReads: Int = 4,
        snapshotMountPointURL: URL? = nil
    ) {
        precondition(
            maximumConcurrentExtentReads > 0,
            "At least one extent reader is required"
        )
        self.maximumConcurrentExtentReads = maximumConcurrentExtentReads
        self.snapshotMountPointURL = snapshotMountPointURL
    }
}

public enum StorageEngineIssueStage: Sendable, Equatable {
    case traversal
    case extentInspection
    case snapshotInventory
    case openFileReferences
}

public struct StorageEngineIssue: Sendable, Equatable {
    public let path: String
    public let stage: StorageEngineIssueStage
    public let errorNumber: Int32?
    public let reason: String

    public init(
        path: String,
        stage: StorageEngineIssueStage,
        errorNumber: Int32?,
        reason: String
    ) {
        self.path = path
        self.stage = stage
        self.errorNumber = errorNumber
        self.reason = reason
    }
}

public struct StorageEngineResult: Sendable, Equatable {
    public let rootURL: URL
    public let scope: ScanScope
    public let entries: [StorageEntry]
    public let inspectedFiles: [InspectedFile]
    public let cloneFamilies: Measurement<[CloneFamily]>
    public let snapshotInventory: Measurement<[LocalSnapshot]>
    public let snapshotManifests: Measurement<[SnapshotExtentManifest]>
    public let openFileReferences: OpenFileReferenceInventory
    public let issues: [StorageEngineIssue]

    /// False means the result is useful but must never be presented as a total.
    public let isComplete: Bool

    public init(
        rootURL: URL,
        scope: ScanScope,
        entries: [StorageEntry],
        inspectedFiles: [InspectedFile],
        cloneFamilies: Measurement<[CloneFamily]>,
        snapshotInventory: Measurement<[LocalSnapshot]>,
        snapshotManifests: Measurement<[SnapshotExtentManifest]>,
        openFileReferences: OpenFileReferenceInventory,
        issues: [StorageEngineIssue],
        isComplete: Bool
    ) {
        self.rootURL = rootURL
        self.scope = scope
        self.entries = entries
        self.inspectedFiles = inspectedFiles
        self.cloneFamilies = cloneFamilies
        self.snapshotInventory = snapshotInventory
        self.snapshotManifests = snapshotManifests
        self.openFileReferences = openFileReferences
        self.issues = issues
        self.isComplete = isComplete
    }

    public func estimateDeletion(
        of paths: Set<String>
    ) -> DeletionEstimate {
        DeletionAccountant().estimate(
            deletingPaths: paths,
            from: inspectedFiles,
            context: DeletionAccountingContext(
                scanScope: scope,
                snapshotInventory: snapshotInventory,
                snapshotManifests: snapshotManifests,
                openFileIdentities: openFileReferences.completeIdentities
            )
        )
    }
}

/// Runs traversal and extent inspection as one bounded pipeline.
///
/// The number of simultaneously open regular files never exceeds
/// `maximumConcurrentExtentReads`. A per-file failure is retained as an issue;
/// it does not erase metadata already gathered for the rest of the tree.
public struct StorageEngine: Sendable {
    public let configuration: StorageEngineConfiguration

    public init(configuration: StorageEngineConfiguration = .init()) {
        self.configuration = configuration
    }

    public func scan(
        at rootURL: URL,
        scope: ScanScope
    ) async throws -> StorageEngineResult {
        try Task.checkCancellation()

        var entries: [StorageEntry] = []
        let traversal = try StorageScanner().walk(at: rootURL) { entry in
            if Task.isCancelled {
                throw CancellationError()
            }
            entries.append(entry)
        }
        entries.sort { $0.path < $1.path }

        var issues = traversal.issues.map {
            StorageEngineIssue(
                path: $0.path,
                stage: .traversal,
                errorNumber: $0.errorNumber,
                reason: "FTS could not read this entry"
            )
        }
        let regularFiles = entries.enumerated().filter {
            $0.element.kind == .regularFile
        }

        var inspectedByEntryIndex: [Int: InspectedFile] = [:]
        await withTaskGroup(of: ExtentOutcome.self) { group in
            var iterator = regularFiles.makeIterator()
            var activeTasks = 0

            func submitNext() {
                guard
                    !Task.isCancelled,
                    let (index, entry) = iterator.next()
                else {
                    return
                }
                activeTasks += 1
                group.addTask {
                    if Task.isCancelled {
                        return .cancelled
                    }
                    do {
                        let extents = try FileExtentReader().inspect(entry)
                        return .inspected(
                            index: index,
                            file: InspectedFile(
                                entry: entry,
                                extents: extents
                            )
                        )
                    } catch let error as FileExtentError {
                        return .failed(
                            extentIssue(for: entry.path, error: error)
                        )
                    } catch {
                        return .failed(
                            StorageEngineIssue(
                                path: entry.path,
                                stage: .extentInspection,
                                errorNumber: nil,
                                reason: String(describing: error)
                            )
                        )
                    }
                }
            }

            for _ in 0..<min(
                configuration.maximumConcurrentExtentReads,
                regularFiles.count
            ) {
                submitNext()
            }

            while activeTasks > 0, let outcome = await group.next() {
                activeTasks -= 1
                switch outcome {
                case let .inspected(index, file):
                    inspectedByEntryIndex[index] = file
                case let .failed(issue):
                    issues.append(issue)
                case .cancelled:
                    group.cancelAll()
                }
                submitNext()
            }
        }

        try Task.checkCancellation()

        let inspectedFiles = inspectedByEntryIndex
            .sorted { $0.key < $1.key }
            .map(\.value)
        let cloneFamilies: Measurement<[CloneFamily]>
        if inspectedFiles.count == regularFiles.count {
            cloneFamilies = CloneFamilyAnalyzer().analyze(
                inspectedFiles,
                scope: scope
            )
        } else {
            cloneFamilies = .notPublished(
                reason: "One or more files could not be inspected for shared extents"
            )
        }

        let snapshotInventory: Measurement<[LocalSnapshot]>
        var containingVolumeURL: URL?
        do {
            let values = try rootURL.resourceValues(
                forKeys: [.volumeURLKey]
            )
            if let volumeURL = values.volume {
                containingVolumeURL = volumeURL
                snapshotInventory = try SnapshotInventoryReader().inventory(
                    forVolumeAt: volumeURL
                )
            } else {
                snapshotInventory = .notPublished(
                    reason: "Foundation did not publish the containing volume URL"
                )
                issues.append(
                    StorageEngineIssue(
                        path: rootURL.path,
                        stage: .snapshotInventory,
                        errorNumber: nil,
                        reason: "The containing volume URL is unavailable"
                    )
                )
            }
        } catch let error as SnapshotInventoryError {
            let errorNumber: Int32
            switch error {
            case let .cannotEnumerate(_, number):
                errorNumber = number
            }
            snapshotInventory = .notPublished(
                reason: "Snapshot inventory failed with errno \(errorNumber)"
            )
            issues.append(
                StorageEngineIssue(
                    path: rootURL.path,
                    stage: .snapshotInventory,
                    errorNumber: errorNumber,
                    reason: "Snapshot inventory failed"
                )
            )
        } catch {
            snapshotInventory = .notPublished(
                reason: "The containing volume URL could not be resolved"
            )
            issues.append(
                StorageEngineIssue(
                    path: rootURL.path,
                    stage: .snapshotInventory,
                    errorNumber: nil,
                    reason: String(describing: error)
                )
            )
        }

        let snapshotManifests: Measurement<[SnapshotExtentManifest]>
        switch snapshotInventory {
        case let .known(snapshots, _):
            if snapshots.isEmpty {
                snapshotManifests = .known(
                    [],
                    source: .snapshotManifestDiff
                )
            } else if
                let containingVolumeURL,
                let mountPointURL = configuration.snapshotMountPointURL
            {
                do {
                    snapshotManifests = try SnapshotManifestReader()
                        .manifests(
                            forVolumeAt: containingVolumeURL,
                            snapshots: snapshots,
                            mountPointURL: mountPointURL
                        )
                } catch let error as SnapshotManifestError {
                    snapshotManifests = .notPublished(
                        reason: snapshotManifestReason(error)
                    )
                } catch {
                    snapshotManifests = .notPublished(
                        reason: String(describing: error)
                    )
                }
            } else {
                snapshotManifests = .notPublished(
                    reason: "No read-only snapshot mount point is configured"
                )
            }
        case let .notPublished(reason):
            snapshotManifests = .notPublished(reason: reason)
        case .notAttributable:
            snapshotManifests = .notPublished(
                reason: "Snapshot inventory is not fully attributable"
            )
        }

        let openFileReferences: OpenFileReferenceInventory
        do {
            openFileReferences = try OpenFileReferenceReader().inventory()
        } catch let error as OpenFileReferenceError {
            let errorNumber: Int32
            switch error {
            case let .cannotEnumerate(number):
                errorNumber = number
            }
            openFileReferences = OpenFileReferenceInventory(
                observedIdentities: [],
                completeIdentities: .notPublished(
                    reason: "Open-file enumeration failed with errno \(errorNumber)"
                ),
                inaccessibleProcessCount: 0
            )
            issues.append(
                StorageEngineIssue(
                    path: rootURL.path,
                    stage: .openFileReferences,
                    errorNumber: errorNumber,
                    reason: "Open-file enumeration failed"
                )
            )
        } catch {
            openFileReferences = OpenFileReferenceInventory(
                observedIdentities: [],
                completeIdentities: .notPublished(
                    reason: "Open-file enumeration failed"
                ),
                inaccessibleProcessCount: 0
            )
            issues.append(
                StorageEngineIssue(
                    path: rootURL.path,
                    stage: .openFileReferences,
                    errorNumber: nil,
                    reason: String(describing: error)
                )
            )
        }

        issues.sort {
            if $0.path == $1.path {
                return String(describing: $0.stage) <
                    String(describing: $1.stage)
            }
            return $0.path < $1.path
        }
        let hasCompleteFamilyAccounting: Bool
        if case .known = cloneFamilies {
            hasCompleteFamilyAccounting = true
        } else {
            hasCompleteFamilyAccounting = false
        }
        return StorageEngineResult(
            rootURL: rootURL,
            scope: scope,
            entries: entries,
            inspectedFiles: inspectedFiles,
            cloneFamilies: cloneFamilies,
            snapshotInventory: snapshotInventory,
            snapshotManifests: snapshotManifests,
            openFileReferences: openFileReferences,
            issues: issues,
            isComplete: issues.isEmpty && hasCompleteFamilyAccounting
        )
    }
}

private func snapshotManifestReason(
    _ error: SnapshotManifestError
) -> String {
    switch error {
    case let .cannotMount(snapshot, errorNumber):
        return "Snapshot \(snapshot) cannot be mounted read-only (errno \(errorNumber))"
    case let .cannotUnmount(snapshot, errorNumber):
        return "Snapshot \(snapshot) could not be unmounted (errno \(errorNumber))"
    case let .mountPointNotEmpty(path):
        return "The snapshot mount point is not empty: \(path)"
    case let .cannotTraverse(snapshot, reason):
        return "Snapshot \(snapshot) could not be traversed: \(reason)"
    case let .cannotInspect(snapshot, path, reason):
        return "Snapshot \(snapshot) extent inspection failed at \(path): \(reason)"
    case let .extentOverflow(snapshot):
        return "Snapshot \(snapshot) published an overflowing extent"
    }
}

private enum ExtentOutcome: Sendable {
    case inspected(index: Int, file: InspectedFile)
    case failed(StorageEngineIssue)
    case cancelled
}

private func extentIssue(
    for path: String,
    error: FileExtentError
) -> StorageEngineIssue {
    switch error {
    case .notARegularFile:
        return StorageEngineIssue(
            path: path,
            stage: .extentInspection,
            errorNumber: EINVAL,
            reason: "The entry changed type during the scan"
        )
    case let .cannotInspect(_, errorNumber):
        return StorageEngineIssue(
            path: path,
            stage: .extentInspection,
            errorNumber: errorNumber,
            reason: "Extent inspection failed"
        )
    case .allocationChanged:
        return StorageEngineIssue(
            path: path,
            stage: .extentInspection,
            errorNumber: ESTALE,
            reason: "The entry's allocation changed during the scan"
        )
    case .identityChanged:
        return StorageEngineIssue(
            path: path,
            stage: .extentInspection,
            errorNumber: ESTALE,
            reason: "The entry identity changed during the scan"
        )
    }
}
