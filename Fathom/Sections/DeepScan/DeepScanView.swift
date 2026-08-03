import FathomKit
import SwiftUI

struct DeepScanView: View {
    @EnvironmentObject private var storage: StorageAppModel
    let openExplore: () -> Void

    var body: some View {
        Group {
            switch storage.state {
            case .idle:
                poster(scanning: false)
            case .scanning:
                poster(scanning: true)
            case let .failed(reason):
                VStack(spacing: 14) {
                    Text("not published").font(.fathomDisplay(32))
                    Text(reason).textSelection(.enabled)
                    Button("Try again", action: storage.reset)
                }
            case let .result(presentation):
                result(presentation)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func poster(scanning: Bool) -> some View {
        FathomPoster(
            title: "Deep Scan",
            message: scanning
                ? storage.scanProgressMessage
                : "Map physical extents, clone families, open descriptors and snapshot-held ranges before making a claim.",
            symbol: "magnifyingglass",
            world: .deepScan,
            shape: AnyShape(Circle()),
            isScanning: scanning,
            action: storage.scanSelectedVolume
        )
    }

    private func result(_ presentation: StoragePresentation) -> some View {
        VStack(spacing: 22) {
            Text("Deep Scan").font(.fathomDisplay(38))
            HStack(spacing: 16) {
                HardwareResultCard(label: "ON DISK") {
                    HardwareMeasurementView(
                        measurement: presentation.sizeOnDisk,
                        format: hardwareByteString,
                        prominent: true
                    )
                }
                HardwareResultCard(label: "FREED IF DELETED") {
                    HardwareMeasurementView(
                        measurement: presentation.freedIfDeleted,
                        format: hardwareByteString,
                        prominent: true
                    )
                }
            }
            .frame(maxWidth: 760)
            Text(
                presentation.issueCount == 0
                    ? "Every traversed item was inspected."
                    : "\(presentation.issueCount) items remain explicitly partial."
            )
            .foregroundStyle(.white.opacity(0.82))
            HStack {
                Button("Scan again", action: storage.reset)
                Button("Explore exact paths", action: openExplore)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(34)
    }
}
