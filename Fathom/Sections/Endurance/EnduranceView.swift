import FathomKit
import SwiftUI

struct EnduranceView: View {
    @EnvironmentObject private var model: HardwareAppModel
    let openSSDHealth: () -> Void

    var body: some View {
        Group {
            switch model.state {
            case .idle:
                FathomEmptySection(
                    title: "Endurance",
                    subtitle: "Read only",
                    headline: "One reading is not a rate.",
                    detail: "Endurance is the controller's own lifetime accounting, read from the NVMe SMART log. Nothing here writes to the drive, and nothing here can change it.",
                    actionTitle: "Read the SMART log",
                    actionCost: "Read only. The drive is not modified.",
                    action: model.readSSD
                )
            case .reading:
                FathomEmptySection(
                    title: "Endurance",
                    subtitle: "Reading",
                    headline: "Reading the controller's lifetime log.",
                    detail: "This is the drive's own accounting, not an estimate derived from filesystem activity.",
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
                    title: "Endurance",
                    subtitle: "NVMe SMART · read only",
                    isLive: false
                )

                FathomReadoutGrid {
                    FathomMeasurementReadout(
                        label: "Consumed",
                        measurement: snapshot.percentageUsed,
                        unit: "%",
                        note: spareNote(snapshot.availableSparePercent),
                        format: { $0.formatted() }
                    )
                    FathomMeasurementReadout(
                        label: "Written",
                        measurement: snapshot.bytesWritten,
                        note: "Lifetime, as the controller counts it",
                        format: bytes
                    )
                    FathomMeasurementReadout(
                        label: "Per hour",
                        measurement: snapshot.lifetimeBytesWrittenPerHour,
                        note: "Averaged over every power-on hour",
                        format: { bytes(UInt64(max(0, $0))) }
                    )
                    FathomMeasurementReadout(
                        label: "Projection",
                        measurement: snapshot.linearPowerOnHoursAtHundredPercent,
                        unit: "hours",
                        note: "Straight-line, at the lifetime rate",
                        format: {
                            $0.formatted(.number.precision(.fractionLength(0)))
                        }
                    )
                }
                .padding(.bottom, 22)

                FathomPanel(label: "The arithmetic") {
                    chain(snapshot)
                }

                FathomNote(
                    headline: "We will not print a date.",
                    detail: "Apple does not publish a terabytes-written rating for these drives, so any specific date would be a guess dressed as a forecast. The projection above is the controller's own rate carried forward in a straight line, and it is labelled in power-on hours because that is what the drive counts. If the rate changes, the weekly digest will say so."
                )
                .padding(.bottom, 22)

                FathomAction(
                    title: "Open SSD Health",
                    cost: "Every field the controller publishes.",
                    action: openSSDHealth
                )
            }
            .padding(EdgeInsets(top: 22, leading: 28, bottom: 40, trailing: 28))
        }
    }

    /// The chain only draws where every step is published. A missing link is
    /// stated rather than skipped over, because the whole point of showing the
    /// arithmetic is that the reader can follow it.
    @ViewBuilder
    private func chain(_ snapshot: NVMeSMARTSnapshot) -> some View {
        let steps: [FathomChain.Step?] = [
            step("Written", snapshot.bytesWritten, "lifetime", bytes),
            step(
                "Per hour",
                snapshot.lifetimeBytesWrittenPerHour,
                "every power-on hour",
                { bytes(UInt64(max(0, $0))) }
            ),
            step(
                "Consumed",
                snapshot.percentageUsed,
                hoursDetail(snapshot.powerOnHours),
                { "\($0)%" }
            ),
            step(
                "Projection",
                snapshot.linearPowerOnHoursAtHundredPercent,
                "power-on hours to 100%",
                { $0.formatted(.number.precision(.fractionLength(0))) }
            ),
        ]
        let resolved = steps.compactMap { $0 }
        if resolved.count == steps.count {
            FathomChain(steps: resolved)
        } else {
            FathomPanelUnavailable(
                reason: "The controller did not publish every step of this calculation, so the chain is not drawn. The readouts above show what it did publish."
            )
        }
    }

    private func step<Value>(
        _ label: String,
        _ measurement: FathomKit.Measurement<Value>,
        _ detail: String,
        _ format: (Value) -> String
    ) -> FathomChain.Step? {
        guard case let .known(value, _) = measurement else { return nil }
        return FathomChain.Step(
            label: label,
            value: format(value),
            detail: detail
        )
    }

    private func hoursDetail(
        _ hours: FathomKit.Measurement<UInt64>
    ) -> String {
        guard case let .known(value, _) = hours else {
            return "power-on hours not published"
        }
        return "in \(value.formatted()) power-on hours"
    }

    private func spareNote(
        _ spare: FathomKit.Measurement<UInt64>
    ) -> String {
        guard case let .known(percent, _) = spare else {
            return "Available spare not published"
        }
        return "\(percent)% spare still available"
    }

    private func bytes(_ value: UInt64) -> String {
        ByteString.file(value)
    }
}
