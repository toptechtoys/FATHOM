import FathomKit
import SwiftUI

struct HardwareMeasurementView<Value: Sendable>: View {
    let measurement: FathomKit.Measurement<Value>
    let format: (Value) -> String
    var prominent = false

    var body: some View {
        switch measurement {
        case let .known(value, source):
            Text(format(value))
                .font(
                    prominent
                        ? .fathomDisplay(42)
                        : .fathomData(19, weight: .semibold)
                )
                .monospacedDigit()
                .help(source.rawValue)
                .accessibilityLabel(
                    "\(format(value)), source \(source.rawValue)"
                )
        case let .notPublished(reason):
            Text("not published")
                .font(
                    prominent
                        ? .fathomDisplay(27)
                        : .fathomData(15, weight: .medium)
                )
                .foregroundStyle(.white.opacity(0.82))
                .help(reason)
                .accessibilityLabel("Not published. \(reason)")
        case let .notAttributable(measured, explained):
            VStack(alignment: .leading, spacing: 2) {
                Text("not attributable")
                    .font(.fathomData(15, weight: .medium))
                Text(
                    "\(format(measured)) measured · \(format(explained)) explained"
                )
                .font(.fathomSystem(10))
                .foregroundStyle(.white.opacity(0.82))
            }
            .accessibilityElement(children: .combine)
        }
    }
}

func hardwareByteString(_ value: UInt64) -> String {
    ByteString.file(value)
}

func hardwareByteString(_ value: Double) -> String {
    ByteString.file(rounding: value)
}

func hardwareIntegerString(_ value: UInt64) -> String {
    value.formatted(.number.grouping(.automatic))
}

func hardwareHoursString(_ value: Double) -> String {
    "\(value.formatted(.number.precision(.fractionLength(0)))) hours"
}
