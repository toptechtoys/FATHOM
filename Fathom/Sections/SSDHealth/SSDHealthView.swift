import FathomKit
import Foundation
import SwiftUI

struct SSDHealthView: View {
    @EnvironmentObject private var model: HardwareAppModel
    let openEndurance: () -> Void

    private let columns = [
        GridItem(.adaptive(minimum: 230), spacing: 16)
    ]

    var body: some View {
        Group {
            switch model.state {
            case .idle:
                poster(isReading: false)
            case .reading:
                poster(isReading: true)
            case let .result(snapshot):
                result(snapshot)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func poster(isReading: Bool) -> some View {
        FathomPoster(
            title: "SSD Health",
            message: "What the controller itself reports. Read only, and neutral until it is not.",
            symbol: "waveform.path.ecg",
            world: .ssdHealth,
            shape: AnyShape(
                RoundedRectangle(cornerRadius: 58)
            ),
            isScanning: isReading,
            action: model.readSSD
        )
    }

    private func result(_ snapshot: NVMeSMARTSnapshot) -> some View {
        ScrollView {
            VStack(spacing: 22) {
                Text("SSD Health")
                    .font(.fathomDisplay(38))
                    .tracking(-1.2)

                Text("Read only. Nothing here can be changed by this app.")
                    .font(.fathomSystem(13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.82))

                LazyVGrid(columns: columns, spacing: 16) {
                    card("DATA WRITTEN") {
                        HardwareMeasurementView(
                            measurement: snapshot.bytesWritten,
                            format: hardwareByteString
                        )
                        detail("Read", snapshot.bytesRead, hardwareByteString)
                    }
                    card("ENDURANCE CONSUMED") {
                        HardwareMeasurementView(
                            measurement: snapshot.percentageUsed,
                            format: { "\($0)%" }
                        )
                        detail(
                            "Spare available",
                            snapshot.availableSparePercent,
                            { "\($0)%" }
                        )
                    }
                    card("POWER ON") {
                        HardwareMeasurementView(
                            measurement: snapshot.powerOnHours,
                            format: {
                                "\(hardwareIntegerString($0)) hours"
                            }
                        )
                        detail(
                            "Cycles",
                            snapshot.powerCycles,
                            hardwareIntegerString
                        )
                    }
                    card("UNSAFE SHUTDOWNS") {
                        HardwareMeasurementView(
                            measurement: snapshot.unsafeShutdowns,
                            format: hardwareIntegerString
                        )
                        detail(
                            "Media errors",
                            snapshot.mediaErrors,
                            hardwareIntegerString
                        )
                        HardwareMeasurementView(
                            measurement: model.unsafeShutdowns30Days,
                            format: {
                                "\(hardwareIntegerString($0.count)) since \($0.start.formatted(date: .abbreviated, time: .omitted))"
                            }
                        )
                    }
                    card("CRITICAL WARNING") {
                        HardwareMeasurementView(
                            measurement: snapshot.criticalWarning,
                            format: {
                                $0 == 0
                                    ? "None"
                                    : String(format: "0x%02llX", $0)
                            }
                        )
                        Text("The raw NVMe warning bitfield.")
                            .font(.fathomSystem(11))
                            .foregroundStyle(.white.opacity(0.82))
                    }
                    card("CONTROLLER TEMPERATURE") {
                        HardwareMeasurementView(
                            measurement: snapshot.temperatureCelsius,
                            format: {
                                "\($0.formatted(.number.precision(.fractionLength(1)))) °C"
                            }
                        )
                        Text("Reported directly by SMART log page 0x02.")
                            .font(.fathomSystem(11))
                            .foregroundStyle(.white.opacity(0.82))
                    }
                    card("ROOT VOLUME ENCRYPTION") {
                        HardwareMeasurementView(
                            measurement: VolumeEncryptionReader().read(
                                volumeURL: URL(fileURLWithPath: "/")
                            ),
                            format: { $0 ? "Encrypted" : "Not encrypted" }
                        )
                        Text("Foundation does not name the FileVault policy behind this state.")
                            .font(.fathomSystem(11))
                            .foregroundStyle(.white.opacity(0.82))
                    }
                }
                .frame(maxWidth: 840)

                HStack(spacing: 12) {
                    Button("Read again", action: model.reset)
                    Button("Open Endurance", action: openEndurance)
                        .buttonStyle(.borderedProminent)
                        .tint(.white)
                        .foregroundStyle(Color(hex: 0x0A1F2E))
                }
                .controlSize(.large)
            }
            .padding(38)
        }
    }

    private func card<Content: View>(
        _ label: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HardwareResultCard(label: label, content: content)
            .frame(minHeight: 135, alignment: .top)
    }

    private func detail<Value: Sendable>(
        _ label: String,
        _ measurement: FathomKit.Measurement<Value>,
        _ format: @escaping (Value) -> String
    ) -> some View {
        HStack(spacing: 5) {
            Text("\(label):")
            HardwareMeasurementView(
                measurement: measurement,
                format: format
            )
        }
        .font(.fathomSystem(11))
        .foregroundStyle(.white.opacity(0.82))
    }
}
