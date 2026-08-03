import FathomKit
import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var storage: StorageAppModel
    @EnvironmentObject private var hardware: HardwareAppModel
    let openStorage: () -> Void
    let openSSDHealth: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("FATHOM").font(.fathomDisplay(40))
                Text("No overall score. Every value keeps its source and state.")
                    .foregroundStyle(.white.opacity(0.82))

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 260), spacing: 16)],
                    spacing: 16
                ) {
                    storageCards
                    ssdCard
                    volumeEncryptionCard
                }

                HardwareResultCard(label: "CURRENT STATEMENT") {
                    currentStatement
                }
            }
            .padding(34)
        }
        .onAppear {
            if case .idle = hardware.state { hardware.readSSD() }
        }
    }

    private var volumeEncryptionCard: some View {
        HardwareResultCard(label: "ROOT VOLUME ENCRYPTION") {
            HardwareMeasurementView(
                measurement: VolumeEncryptionReader().read(
                    volumeURL: URL(fileURLWithPath: "/")
                ),
                format: { $0 ? "Encrypted" : "Not encrypted" }
            )
            Text("Foundation reports volume encryption, not the named FileVault policy.")
                .font(.fathomSystem(11))
                .foregroundStyle(.white.opacity(0.82))
        }
    }

    @ViewBuilder
    private var storageCards: some View {
        switch storage.state {
        case let .result(presentation):
            homeCard("ACTUALLY FREE", presentation.actuallyFree, openStorage)
            homeCard("FREED IF SELECTED", presentation.freedIfDeleted, openStorage)
        case .scanning:
            HardwareResultCard(label: "STORAGE") {
                ProgressView("Whole-volume scan in progress…")
            }
        case .idle, .failed:
            HardwareResultCard(label: "STORAGE") {
                Text("not published")
                    .foregroundStyle(.white.opacity(0.82))
                Button("Run Deep Scan", action: openStorage)
            }
        }
    }

    private var ssdCard: some View {
        HardwareResultCard(label: "NVME CRITICAL WARNING") {
            switch hardware.state {
            case .idle, .reading:
                ProgressView("Read-only SMART read…")
            case let .result(snapshot):
                HardwareMeasurementView(
                    measurement: snapshot.criticalWarning,
                    format: {
                        $0 == 0
                            ? "None"
                            : "Raw bitfield 0x\(String($0, radix: 16))"
                    }
                )
                Button("Evidence", action: openSSDHealth)
            }
        }
    }

    private func homeCard(
        _ label: String,
        _ measurement: FathomKit.Measurement<UInt64>,
        _ action: @escaping () -> Void
    ) -> some View {
        HardwareResultCard(label: label) {
            HardwareMeasurementView(
                measurement: measurement,
                format: hardwareByteString,
                prominent: true
            )
            Button("Evidence", action: action)
        }
    }

    @ViewBuilder
    private var currentStatement: some View {
        if case let .result(snapshot) = hardware.state,
           case let .known(warning, _) = snapshot.criticalWarning,
           warning == 0 {
            Text("The SSD controller currently reports no critical warning. FATHOM makes no broader health claim from that fact.")
                .font(.fathomSystem(14, weight: .medium))
        } else {
            Text("not published — the evidence needed for a current statement is incomplete")
                .foregroundStyle(.white.opacity(0.82))
        }
    }
}
