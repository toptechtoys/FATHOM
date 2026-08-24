import FathomKit
import SwiftUI

struct StorageView: View {
    @EnvironmentObject private var model: StorageAppModel
    let openExplore: () -> Void

    var body: some View {
        Group {
            switch model.state {
            case .idle:
                FathomEmptySection(
                    title: "Storage",
                    subtitle: "The tree has not been indexed",
                    headline: "Finder counts space it may not be able to release.",
                    detail: "Until the first scan finishes, the only honest numbers are the volume totals. A scan maps physical extents, clone families and snapshot-held ranges, which is what makes the second number possible.",
                    actionTitle: "Run the first Deep Scan",
                    actionCost: "Reads every volume once. Changes nothing.",
                    action: model.scanSelectedVolume
                )
            case .scanning:
                FathomEmptySection(
                    title: "Storage",
                    subtitle: "Scanning",
                    headline: "Mapping what the volume is actually carrying.",
                    detail: model.scanProgressMessage,
                    actionTitle: "Scanning…",
                    isBusy: true,
                    action: {}
                )
            case let .failed(reason):
                FathomEmptySection(
                    title: "Storage",
                    subtitle: "The scan did not complete",
                    headline: "The scan stopped before it could claim anything.",
                    detail: reason,
                    actionTitle: "Try again",
                    action: model.reset
                )
            case let .result(presentation):
                result(presentation)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func result(_ presentation: StoragePresentation) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                FathomSectionHeader(
                    title: "Storage",
                    subtitle: presentation.volumePath,
                    isLive: false
                )

                FathomReadoutGrid {
                    FathomMeasurementReadout(
                        label: "Actually free",
                        measurement: presentation.actuallyFree,
                        note: "The true number, right now",
                        format: bytes
                    )
                    FathomMeasurementReadout(
                        label: "Finder says",
                        measurement: presentation.finderAvailable,
                        note: finderNote(presentation),
                        format: bytes
                    )
                    FathomMeasurementReadout(
                        label: "Reclaimable",
                        measurement: presentation.freedIfDeleted,
                        note: "What deletion would actually return",
                        format: bytes
                    )
                    FathomMeasurementReadout(
                        label: "Purgeable",
                        measurement: presentation.purgeable,
                        note: "Counted by Finder, not guaranteed to a write",
                        format: bytes
                    )
                }
                .padding(.bottom, 22)

                FathomPanel(label: "Where the volume sits — area is size on disk") {
                    treemap(presentation)
                }

                FathomPanel(label: "Live disk throughput") {
                    DiskThroughputPanel()
                }

                FathomPanel(label: "Snapshots and change monitoring") {
                    VStack(spacing: 3) {
                        snapshotRow(
                            presentation.snapshotInventory,
                            coverage: presentation.snapshotCoverage
                        )
                        stringRow("Change monitoring", model.changeMonitoring)
                        if presentation.issueCount > 0 {
                            FathomDataRow.simple(
                                "Items that could not be inspected",
                                value: presentation.issueCount.formatted(),
                                valueColor: FathomSemantic.caution,
                                annotation: "This result is partial and says so rather than rounding up.",
                                isEmphasised: true
                            )
                        }
                    }
                }

                FathomNote(
                    headline: headline(presentation),
                    detail: "Finder counts purgeable space it may not be able to release. We show the number a write would actually see, and everything below is reported with both figures."
                )
                .padding(.bottom, 22)

                HStack(spacing: 14) {
                    FathomAction(title: "Explore the tree", action: openExplore)
                    FathomAction(
                        title: "Scan again",
                        cost: rescanCost(presentation),
                        isProminent: false,
                        action: model.reset
                    )
                }
            }
            .padding(EdgeInsets(top: 22, leading: 28, bottom: 40, trailing: 28))
        }
    }

    /// The largest top-level regions, by what they occupy.
    ///
    /// The remainder is drawn and named rather than being absorbed by the
    /// largest tiles: area is the whole claim this panel makes.
    @ViewBuilder
    private func treemap(_ presentation: StoragePresentation) -> some View {
        let regions = regions(presentation)
        if regions.isEmpty {
            FathomPanelUnavailable(
                reason: "No top-level region published a size on disk."
            )
        } else {
            FathomTreemap(regions: regions)
        }
    }

    /// The eight largest top-level regions, plus the remainder.
    ///
    /// The remainder is drawn and named rather than absorbed by the largest
    /// tiles: area is the whole claim this panel makes, and a treemap that
    /// silently drops the tail overstates everything it kept.
    private func regions(
        _ presentation: StoragePresentation
    ) -> [FathomTreemap.Region] {
        let ranked = presentation.rows
            .map { row in (row, known(row.sizeOnDisk)) }
            .sorted { $0.1 > $1.1 }
        let top = Array(ranked.prefix(8))
        let shown = top.reduce(UInt64(0)) { $0 + $1.1 }
        guard shown > 0 else { return [] }

        let total = ranked.reduce(UInt64(0)) { $0 + $1.1 }
        var result = top.map { row, size in
            FathomTreemap.Region(
                name: row.name,
                detail: bytes(size) + freeableSuffix(row),
                fraction: Double(size)
            )
        }
        if total > shown {
            result.append(
                FathomTreemap.Region(
                    name: "Everything else",
                    detail: bytes(total - shown),
                    fraction: Double(total - shown)
                )
            )
        }
        return result
    }

    private func freeableSuffix(_ row: ExplorePresentationRow) -> String {
        let freed = known(row.freedIfDeleted)
        return freed == 0 ? " · frees nothing" : " · \(bytes(freed)) frees"
    }

    private func snapshotRow(
        _ inventory: FathomKit.Measurement<[LocalSnapshot]>,
        coverage: FathomKit.Measurement<[String]>
    ) -> some View {
        switch inventory {
        case let .known(snapshots, _):
            if snapshots.isEmpty {
                FathomDataRow.simple(
                    "Local snapshots",
                    value: "none",
                    annotation: "No local snapshots currently hold old extents."
                )
            } else {
                FathomDataRow.simple(
                    "Local snapshots",
                    value: snapshots.count.formatted(),
                    valueColor: FathomSemantic.caution,
                    annotation: coverageNote(coverage),
                    isEmphasised: true
                )
            }
        case let .notPublished(reason):
            FathomDataRow.simple(
                "Local snapshots",
                value: "not published",
                valueColor: .white.opacity(FathomSurface.minimumTextOpacity),
                annotation: reason
            )
        case .notAttributable:
            FathomDataRow.simple(
                "Local snapshots",
                value: "not attributable",
                valueColor: FathomSemantic.caution,
                isEmphasised: true
            )
        }
    }

    private func coverageNote(
        _ coverage: FathomKit.Measurement<[String]>
    ) -> String {
        switch coverage {
        case .known:
            "Mapped. Freeable values exclude every extent they still reference."
        case let .notPublished(reason):
            "Their held extents are not published. \(reason)"
        case .notAttributable:
            "Their held extents are not attributable."
        }
    }

    private func stringRow(
        _ label: String,
        _ measurement: FathomKit.Measurement<String>
    ) -> some View {
        switch measurement {
        case let .known(value, source):
            FathomDataRow.simple(label, value: value, annotation: source.rawValue)
        case let .notPublished(reason):
            FathomDataRow.simple(
                label,
                value: "not published",
                valueColor: .white.opacity(FathomSurface.minimumTextOpacity),
                annotation: reason
            )
        case .notAttributable:
            FathomDataRow.simple(
                label,
                value: "not attributable",
                valueColor: FathomSemantic.caution,
                isEmphasised: true
            )
        }
    }

    private func headline(_ presentation: StoragePresentation) -> String {
        guard case let .known(actual, _) = presentation.actuallyFree,
              case let .known(finder, _) = presentation.finderAvailable,
              finder != actual
        else {
            return "Finder and the important-usage capacity API currently agree."
        }
        return "Finder says \(bytes(finder)). The honest answer is \(bytes(actual))."
    }

    private func finderNote(_ presentation: StoragePresentation) -> String {
        guard case let .known(actual, _) = presentation.actuallyFree,
              case let .known(finder, _) = presentation.finderAvailable,
              finder > actual
        else {
            return "It counts purgeable space it may not release"
        }
        return "\(bytes(finder - actual)) of that is not guaranteed to a write"
    }

    private func known(_ measurement: FathomKit.Measurement<UInt64>) -> UInt64 {
        guard case let .known(value, _) = measurement else { return 0 }
        return value
    }

    /// What "Scan again" costs, from the last scan rather than an estimate.
    ///
    /// It discards a completed result and re-reads every file, and rule 5 says
    /// an action names its cost before it runs. The duration is the measured
    /// one; where a scan has not been timed the sentence stops rather than
    /// inventing a figure.
    private func rescanCost(_ presentation: StoragePresentation) -> String {
        let seconds = Double(presentation.scanDuration.components.seconds)
        guard seconds > 0 else {
            return "Discards this result and reads every file again."
        }
        let measured = seconds < 90
            ? "\(seconds.formatted(.number.precision(.fractionLength(0)))) seconds"
            : "\((seconds / 60).formatted(.number.precision(.fractionLength(1)))) minutes"
        return "Discards this result and reads every file again. Last scan took \(measured)."
    }

    private func bytes(_ value: UInt64) -> String {
        ByteString.file(value)
    }
}

/// Read and write rates from the IOKit block-storage counters.
private struct DiskThroughputPanel: View {
    @State private var measurement:
        FathomKit.Measurement<DiskThroughputSnapshot> = .notPublished(
            reason: "A disk counter sample has not run yet."
        )

    var body: some View {
        Group {
            switch measurement {
            case let .known(snapshot, source):
                VStack(spacing: 3) {
                    rateRow("Read", snapshot.readBytesPerSecond, source)
                    rateRow("Write", snapshot.writtenBytesPerSecond, source)
                    FathomDataRow.simple(
                        "Publishing drivers",
                        value: snapshot.driverCount.formatted(),
                        annotation: source.rawValue
                    )
                }
            case let .notPublished(reason):
                FathomPanelUnavailable(reason: reason)
            case let .notAttributable(measured, explained):
                FathomPanelUnavailable(
                    reason: "\(measured.bytesRead) read bytes measured, \(explained.bytesRead) explained.",
                    isAttributionGap: true
                )
            }
        }
        .task {
            let sampler = DiskThroughputSampler()
            _ = await sampler.sample()
            do {
                try await Task.sleep(for: .milliseconds(250))
            } catch {
                return
            }
            while !Task.isCancelled {
                measurement = await sampler.sample()
                do {
                    try await Task.sleep(for: .seconds(1))
                } catch {
                    return
                }
            }
        }
    }

    private func rateRow(
        _ label: String,
        _ measurement: FathomKit.Measurement<Double>,
        _ source: DataSource
    ) -> some View {
        switch measurement {
        case let .known(value, _):
            FathomDataRow.simple(
                label,
                value: ByteString.perSecond(UInt64(max(0, value))),
                annotation: source.rawValue
            )
        case let .notPublished(reason):
            FathomDataRow.simple(
                label,
                value: "not published",
                valueColor: .white.opacity(FathomSurface.minimumTextOpacity),
                annotation: reason
            )
        case .notAttributable:
            FathomDataRow.simple(
                label,
                value: "not attributable",
                valueColor: FathomSemantic.caution,
                isEmphasised: true
            )
        }
    }
}
