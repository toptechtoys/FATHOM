import FathomKit
import SwiftUI

struct DeepScanView: View {
    @EnvironmentObject private var storage: StorageAppModel
    let openExplore: () -> Void

    var body: some View {
        Group {
            switch storage.state {
            case .idle:
                FathomEmptySection(
                    title: "Deep Scan",
                    subtitle: "No pass has run yet",
                    headline: "Both numbers, before you touch anything.",
                    detail: "One pass maps physical extents, clone families, open descriptors and snapshot-held ranges across every volume. It takes a few minutes and reads each volume once. Until it has run, the only honest numbers are the volume totals.",
                    actionTitle: "Run the first Deep Scan",
                    actionCost: "Reads every volume once. Changes nothing.",
                    action: storage.scanSelectedVolume
                )
            case .scanning:
                FathomEmptySection(
                    title: "Deep Scan",
                    subtitle: "Reading",
                    headline: "Reading every volume once.",
                    detail: storage.scanProgressMessage,
                    actionTitle: "Scanning…",
                    isBusy: true,
                    action: {}
                )
            case let .failed(reason):
                FathomEmptySection(
                    title: "Deep Scan",
                    subtitle: "The pass did not complete",
                    headline: "The scan stopped before it could claim anything.",
                    detail: reason,
                    actionTitle: "Try again",
                    action: storage.reset
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
                    title: "Deep Scan",
                    subtitle: "Last full pass complete",
                    isLive: false
                )

                FathomReadoutGrid {
                    FathomMeasurementReadout(
                        label: "On disk",
                        measurement: presentation.sizeOnDisk,
                        note: "What the volume is actually carrying",
                        format: bytes
                    )
                    FathomMeasurementReadout(
                        label: "Freed if deleted",
                        measurement: presentation.freedIfDeleted,
                        note: "The number no other tool shows you",
                        format: bytes
                    )
                    FathomMeasurementReadout(
                        label: "Inspected",
                        measurement: inspected(presentation),
                        note: presentation.issueCount == 0
                            ? "Every traversed item was inspected"
                            : "\(presentation.issueCount) items remain explicitly partial",
                        format: { $0 }
                    )
                }
                .padding(.bottom, 22)

                FathomNote(
                    headline: "The gap between those two numbers is APFS doing its job.",
                    detail: "Clones, snapshots and sparse files mean size on disk is not what deletion returns. Everything below is reported with both figures, and a row that frees nothing says so rather than being hidden."
                )
                .padding(.bottom, 22)

                HStack(spacing: 14) {
                    FathomAction(
                        title: "Explore exact paths",
                        action: openExplore
                    )
                    FathomAction(
                        title: "Scan again",
                        cost: rescanCost(presentation),
                        isProminent: false,
                        action: storage.reset
                    )
                }
            }
            .padding(EdgeInsets(top: 22, leading: 28, bottom: 40, trailing: 28))
        }
    }

    /// Whether the pass was complete is itself a measurement: a partial scan
    /// that reports as complete is the failure mode this whole product exists
    /// to avoid.
    private func inspected(
        _ presentation: StoragePresentation
    ) -> FathomKit.Measurement<String> {
        presentation.issueCount == 0
            ? .known("Complete", source: .fts)
            : .notAttributable(
                measured: "Partial",
                explained: "\(presentation.issueCount) items"
            )
    }

    private func bytes(_ value: UInt64) -> String {
        value.formatted(.byteCount(style: .file))
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

}
