import FathomKit
import SwiftUI

struct ApplicationsView: View {
    @EnvironmentObject private var storage: StorageAppModel
    @EnvironmentObject private var applications: ApplicationsAppModel

    var body: some View {
        Group {
            switch storage.state {
            case .idle:
                FathomPoster(
                    title: "Applications",
                    message: "What every app occupies, plus exact bundle-ID leftovers—never prefix guesses.",
                    symbol: "square.grid.2x2",
                    world: .applications,
                    shape: AnyShape(RoundedRectangle(cornerRadius: 42)),
                    isScanning: false,
                    action: storage.scanSelectedVolume
                )
            case .scanning:
                ProgressView("Accounting for application bundles and leftovers…")
            case let .failed(reason):
                Text("not published — \(reason)")
            case let .result(presentation):
                content(presentation)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func content(_ storage: StoragePresentation) -> some View {
        switch applications.state {
        case .idle:
            ProgressView().onAppear { applications.load(from: storage) }
        case .loading:
            ProgressView("Reading application metadata…")
        case let .failed(reason):
            Text(reason).textSelection(.enabled)
        case let .result(records):
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    Text("Applications").font(.fathomDisplay(34))
                    ForEach(records) { app in
                        appCard(app)
                    }
                }
                .padding(34)
            }
        }
    }

    private func appCard(_ app: ApplicationPresentation) -> some View {
        HardwareResultCard(label: app.record.url.path) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    HardwareMeasurementView(
                        measurement: app.record.name,
                        format: { $0 }
                    )
                    Spacer()
                    HardwareMeasurementView(
                        measurement: app.record.version,
                        format: { "v\($0)" }
                    )
                }
                HStack(spacing: 28) {
                    metric("APP ON DISK", app.sizeOnDisk)
                    metric("APP FREED", app.freedIfDeleted)
                    metric("LEFTOVERS ON DISK", app.leftoverSizeOnDisk)
                    metric("LEFTOVERS FREED", app.leftoverFreedIfDeleted)
                }
                HStack {
                    Text("Last accessed")
                    HardwareMeasurementView(
                        measurement: app.record.lastAccessed,
                        format: { $0.formatted(date: .abbreviated, time: .omitted) }
                    )
                    Text("May be stale on noatime volumes")
                        .foregroundStyle(.white.opacity(0.82))
                }
                .font(.fathomSystem(10.5))
            }
        }
    }

    private func metric(
        _ label: String,
        _ value: FathomKit.Measurement<UInt64>
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.fathomSystem(9, weight: .bold))
            HardwareMeasurementView(measurement: value, format: hardwareByteString)
        }
    }
}
