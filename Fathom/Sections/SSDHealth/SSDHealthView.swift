import FathomKit
import Foundation
import SwiftUI

struct SSDHealthView: View {
    @EnvironmentObject private var model: HardwareAppModel
    let openEndurance: () -> Void

    var body: some View {
        Group {
            switch model.state {
            case .idle:
                FathomEmptySection(
                    title: "SSD Health",
                    subtitle: "Read only",
                    headline: "What the controller itself reports.",
                    detail: "Every value comes from the NVMe SMART log the drive keeps for its own purposes. Nothing on this screen can change anything, and where this model does not publish a field the row says so rather than being estimated.",
                    actionTitle: "Read the SMART log",
                    actionCost: "Read only. The drive is not modified.",
                    action: model.readSSD
                )
            case .reading:
                FathomEmptySection(
                    title: "SSD Health",
                    subtitle: "Reading",
                    headline: "Reading the controller's own log.",
                    detail: "Neutral until it is not: a healthy drive gets no green tick and no reassurance it did not earn.",
                    actionTitle: "Reading…",
                    isBusy: true,
                    action: {}
                )
            case let .result(snapshot):
                result(snapshot)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func result(_ snapshot: NVMeSMARTSnapshot) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                FathomSectionHeader(
                    title: "SSD Health",
                    subtitle: "NVMe SMART · read only",
                    isLive: false
                )

                FathomReadoutGrid {
                    FathomMeasurementReadout(
                        label: "Endurance consumed",
                        measurement: snapshot.percentageUsed,
                        unit: "%",
                        note: "The controller's own figure",
                        format: { $0.formatted() }
                    )
                    FathomMeasurementReadout(
                        label: "Available spare",
                        measurement: snapshot.availableSparePercent,
                        unit: "%",
                        note: "Blocks held back to replace failures",
                        format: { $0.formatted() }
                    )
                    FathomMeasurementReadout(
                        label: "Power on",
                        measurement: snapshot.powerOnHours,
                        unit: "hours",
                        note: cyclesNote(snapshot.powerCycles),
                        format: { $0.formatted() }
                    )
                    FathomMeasurementReadout(
                        label: "Media errors",
                        measurement: snapshot.mediaErrors,
                        note: warningNote(snapshot.criticalWarning),
                        format: { $0.formatted() }
                    )
                }
                .padding(.bottom, 22)

                FathomPanel(label: "Every field the controller publishes") {
                    VStack(spacing: 3) {
                        row("Data written", snapshot.bytesWritten, bytes)
                        row("Data read", snapshot.bytesRead, bytes)
                        row("Read to write ratio", ratio(snapshot)) { $0 }
                        row("Percentage used", snapshot.percentageUsed) { "\($0)%" }
                        row("Available spare", snapshot.availableSparePercent) {
                            "\($0)%"
                        }
                        row("Power-on hours", snapshot.powerOnHours) {
                            $0.formatted()
                        }
                        row("Power cycles", snapshot.powerCycles) { $0.formatted() }
                        row("Unsafe shutdowns", snapshot.unsafeShutdowns) {
                            $0.formatted()
                        }
                        row("Media errors", snapshot.mediaErrors) { $0.formatted() }
                        row("Critical warning", snapshot.criticalWarning) {
                            $0 == 0 ? "none" : "0x\(String($0, radix: 16))"
                        }
                        row("Temperature", snapshot.temperatureCelsius) {
                            $0.formatted(.number.precision(.fractionLength(1)))
                                + " °C"
                        }
                    }
                }

                FathomNote(
                    headline: "Read only. Nothing here can be changed by this app.",
                    detail: "Unsafe shutdowns are counted, not judged: they accumulate from power loss and forced restarts and are not on their own a sign of a failing drive. Where this model does not publish a field, the row is absent rather than estimated."
                )
                .padding(.bottom, 22)

                FathomAction(
                    title: "Open Endurance",
                    cost: "The arithmetic behind the projection.",
                    action: openEndurance
                )
            }
            .padding(EdgeInsets(top: 22, leading: 28, bottom: 40, trailing: 28))
        }
    }

    private func row<Value>(
        _ label: String,
        _ measurement: FathomKit.Measurement<Value>,
        _ format: (Value) -> String
    ) -> some View {
        switch measurement {
        case let .known(value, source):
            FathomDataRow.simple(
                label,
                value: format(value),
                annotation: source.rawValue
            )
        case let .notPublished(reason):
            FathomDataRow.simple(
                label,
                value: "not published",
                valueColor: .white.opacity(FathomSurface.minimumTextOpacity),
                annotation: reason
            )
        case let .notAttributable(measured, _):
            FathomDataRow.simple(
                label,
                value: format(measured),
                valueColor: FathomSemantic.caution,
                annotation: "not fully attributable",
                isEmphasised: true
            )
        }
    }

    /// Reads against writes. Unpublished if either side is, because a ratio
    /// with one half missing is not a ratio.
    private func ratio(
        _ snapshot: NVMeSMARTSnapshot
    ) -> FathomKit.Measurement<String> {
        snapshot.bytesRead.combined(with: snapshot.bytesWritten) { read, written in
            guard written > 0 else { return "not calculable, nothing written" }
            let value = Double(read) / Double(written)
            return value.formatted(.number.precision(.fractionLength(2))) + ":1"
        }
    }

    private func cyclesNote(
        _ cycles: FathomKit.Measurement<UInt64>
    ) -> String {
        guard case let .known(value, _) = cycles else {
            return "Power cycles not published"
        }
        return "\(value.formatted()) power cycles"
    }

    private func warningNote(
        _ warning: FathomKit.Measurement<UInt64>
    ) -> String {
        guard case let .known(value, _) = warning else {
            return "Critical warning flag not published"
        }
        return value == 0
            ? "No critical warning flag set"
            : "Critical warning 0x\(String(value, radix: 16))"
    }

    private func bytes(_ value: UInt64) -> String {
        ByteString.file(value)
    }
}
