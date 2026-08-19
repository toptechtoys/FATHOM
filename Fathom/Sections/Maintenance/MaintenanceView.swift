import FathomKit
import SwiftUI

struct MaintenanceView: View {
    @EnvironmentObject private var storage: StorageAppModel
    let openReclaim: () -> Void

    var body: some View {
        Group {
            switch storage.state {
            case .idle:
                FathomPoster(
                    title: "Maintenance",
                    message: "Caches, snapshots and system-managed space. Each action states its cost before it runs.",
                    symbol: "wrench.and.screwdriver",
                    world: .maintenance,
                    shape: AnyShape(RoundedRectangle(cornerRadius: 36)),
                    isScanning: false,
                    action: storage.scanSelectedVolume
                )
            case .scanning:
                ProgressView("Inspecting maintenance evidence…")
            case let .failed(reason):
                Text("not published — \(reason)")
            case let .result(presentation):
                result(presentation)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func result(_ presentation: StoragePresentation) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Maintenance").font(.fathomDisplay(34))
                HardwareResultCard(label: "PURGEABLE") {
                    HardwareMeasurementView(
                        measurement: presentation.purgeable,
                        format: hardwareByteString,
                        prominent: true
                    )
                    Text("There is no supported force-purge API. FATHOM does not allocate a pressure file as if it were maintenance.")
                        .font(.fathomSystem(11.5))
                        .foregroundStyle(.white.opacity(0.82))
                }
                HardwareResultCard(label: "LOCAL SNAPSHOTS") {
                    snapshotState(presentation.snapshotInventory)
                    Text("Snapshot removal is not offered until destination reachability and per-snapshot freeable extents are both published.")
                        .font(.fathomSystem(11.5))
                        .foregroundStyle(.white.opacity(0.82))
                }
                HardwareResultCard(label: "VALIDATED CACHE RECIPES") {
                    Text("Dry run first · exact paths · regeneration cost · Trash only")
                        .font(.fathomSystem(13, weight: .semibold))
                    Button("Open Reclaim", action: openReclaim)
                        .buttonStyle(.borderedProminent)
                }
            }
            .padding(34)
        }
    }

    @ViewBuilder
    private func snapshotState(
        _ measurement: FathomKit.Measurement<[LocalSnapshot]>
    ) -> some View {
        switch measurement {
        case let .known(snapshots, source):
            Text("\(snapshots.count) published")
                .font(.fathomData(20, weight: .semibold))
                .help(source.rawValue)
                .accessibilityLabel(
                    "\(snapshots.count) snapshots published, source \(source.rawValue)"
                )
        case let .notPublished(reason):
            Text("not published")
                .foregroundStyle(.white.opacity(0.82))
                .help(reason)
                .accessibilityLabel("Not published. \(reason)")
        case .notAttributable:
            Text("not attributable")
        }
    }
}
