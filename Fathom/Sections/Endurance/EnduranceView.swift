import FathomKit
import SwiftUI

struct EnduranceView: View {
    @EnvironmentObject private var model: HardwareAppModel
    let openSSDHealth: () -> Void

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
            title: "Endurance",
            message: "This SSD is soldered to the logic board. Here is the arithmetic on how long it has.",
            symbol: "shield.lefthalf.filled",
            world: .endurance,
            shape: AnyShape(
                RoundedRectangle(cornerRadius: 72)
            ),
            isScanning: isReading,
            action: model.readSSD
        )
    }

    private func result(_ snapshot: NVMeSMARTSnapshot) -> some View {
        ScrollView {
            VStack(spacing: 25) {
                Text("Endurance")
                    .font(.fathomDisplay(38))
                    .tracking(-1.2)

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 280), spacing: 18)],
                    alignment: .leading,
                    spacing: 18
                ) {
                    HardwareResultCard(label: "ENDURANCE CONSUMED") {
                        HardwareMeasurementView(
                            measurement: snapshot.percentageUsed,
                            format: { "\($0)%" },
                            prominent: true
                        )
                        HardwareMeasurementView(
                            measurement: snapshot.availableSparePercent,
                            format: { "\($0)% spare available" }
                        )
                    }
                    HardwareResultCard(label: "LINEAR PROJECTION") {
                        HardwareMeasurementView(
                            measurement:
                                snapshot.linearPowerOnHoursAtHundredPercent,
                            format: hardwareHoursString,
                            prominent: true
                        )
                        Text("Power-on hours at the controller’s lifetime rate—not a calendar date.")
                            .font(.fathomSystem(12))
                            .foregroundStyle(.white.opacity(0.82))
                    }
                }
                .frame(maxWidth: 820)

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 190), spacing: 10)],
                    alignment: .leading,
                    spacing: 10
                ) {
                    chainItem(
                        "WRITTEN",
                        snapshot.bytesWritten,
                        format: hardwareByteString
                    )
                    chainItem(
                        "PER POWER-ON HOUR",
                        snapshot.lifetimeBytesWrittenPerHour,
                        format: hardwareByteString
                    )
                    chainItem(
                        "CONSUMED",
                        snapshot.percentageUsed,
                        format: { "\($0)%" }
                    )
                    chainItem(
                        "POWER ON",
                        snapshot.powerOnHours,
                        format: { "\(hardwareIntegerString($0)) hours" }
                    )
                }
                .frame(maxWidth: 900)

                Text(
                    "Apple does not publish a TBW rating for this soldered SSD. FATHOM therefore shows the controller’s lifetime counters and straight-line power-on-hour arithmetic, but never turns them into a failure date."
                )
                .font(.fathomSystem(13))
                .foregroundStyle(.white.opacity(0.82))
                .lineSpacing(3)
                .frame(maxWidth: 760, alignment: .leading)

                HStack(spacing: 12) {
                    Button("Read again", action: model.reset)
                    Button("Open SSD Health", action: openSSDHealth)
                        .buttonStyle(.borderedProminent)
                        .tint(.white)
                        .foregroundStyle(Color(hex: 0x051E2C))
                }
                .controlSize(.large)
            }
            .padding(38)
        }
    }

    private func chainItem<Value: Sendable>(
        _ label: String,
        _ measurement: FathomKit.Measurement<Value>,
        format: @escaping (Value) -> String
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.fathomSystem(9.5, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(.white.opacity(0.82))
            HardwareMeasurementView(
                measurement: measurement,
                format: format
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(17)
        .background(.black.opacity(0.16))
        .clipShape(RoundedRectangle(cornerRadius: 15))
    }

}

struct HardwareResultCard<Content: View>: View {
    let label: String
    let content: Content

    init(
        label: String,
        @ViewBuilder content: () -> Content
    ) {
        self.label = label
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            Text(label)
                .font(.fathomSystem(10.5, weight: .bold))
                .tracking(1.05)
                .foregroundStyle(.white.opacity(0.82))
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(24)
        .background(.white.opacity(0.105))
        .background(.ultraThinMaterial.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .stroke(.white.opacity(0.20), lineWidth: 0.5)
        }
    }
}
