import FathomKit
import SwiftUI

struct MaintenanceView: View {
    @EnvironmentObject private var storage: StorageAppModel
    let openReclaim: () -> Void

    var body: some View {
        Group {
            switch storage.state {
            case .idle:
                FathomEmptySection(
                    title: "Maintenance",
                    subtitle: "Nothing evaluated yet",
                    headline: "Costs first, always.",
                    detail: "Caches, logs, snapshots and the tasks macOS runs badly. Every task states what it takes from you before it runs, and their savings are measured during the first scan rather than estimated before it.",
                    actionTitle: "Run the first Deep Scan",
                    actionCost: "Reads every volume once. Changes nothing.",
                    action: storage.scanSelectedVolume
                )
            case .scanning:
                FathomEmptySection(
                    title: "Maintenance",
                    subtitle: "Reading",
                    headline: "Inspecting maintenance evidence.",
                    detail: storage.scanProgressMessage,
                    actionTitle: "Scanning…",
                    isBusy: true,
                    busySince: storage.scanStartedAt,
                    action: {}
                )
            case let .failed(reason):
                FathomEmptySection(
                    title: "Maintenance",
                    subtitle: "The pass did not complete",
                    headline: "Nothing here is measured yet.",
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
                    title: "Maintenance",
                    subtitle: "Each task states its cost",
                    isLive: false
                )

                FathomReadoutGrid {
                    FathomMeasurementReadout(
                        label: "Purgeable",
                        measurement: presentation.purgeable,
                        note: "Space macOS may reclaim under pressure",
                        format: bytes
                    )
                    FathomMeasurementReadout(
                        label: "Local snapshots",
                        measurement: presentation.snapshotInventory.map { $0.count },
                        note: "Published by the volume",
                        format: { $0.formatted() }
                    )
                }
                .padding(.bottom, 22)

                FathomPanel(label: "What we will not do") {
                    VStack(spacing: 3) {
                        FathomDataRow.simple(
                            "Force-purge purgeable space",
                            value: "not offered",
                            valueColor: .white.opacity(
                                FathomSurface.minimumTextOpacity
                            ),
                            annotation: "There is no supported API. Allocating a pressure file to provoke it is a trick, not maintenance."
                        )
                        FathomDataRow.simple(
                            "Delete local snapshots",
                            value: "not offered",
                            valueColor: .white.opacity(
                                FathomSurface.minimumTextOpacity
                            ),
                            annotation: "Not until destination reachability and per-snapshot freeable extents are both published."
                        )
                    }
                }

                FathomPanel(label: "Validated cache recipes") {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Dry run first · exact paths · regeneration cost stated · Trash only")
                            .font(.fathomSystem(13, weight: .semibold))
                        FathomAction(
                            title: "Open Reclaim",
                            cost: "Nothing runs until you choose it.",
                            action: openReclaim
                        )
                    }
                }

                FathomNote(
                    headline: "Nothing here runs until you have read what it takes.",
                    detail: "Every task names its cost in the same breath as its saving, and the destination is always the Trash. A task we cannot cost honestly is not offered at all, which is why two of them above say so."
                )
            }
            .padding(EdgeInsets(top: 22, leading: 28, bottom: 40, trailing: 28))
        }
    }

    private func bytes(_ value: UInt64) -> String {
        ByteString.file(value)
    }
}
