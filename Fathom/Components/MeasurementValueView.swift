import FathomKit
import SwiftUI

struct MeasurementValueView: View {
    let measurement: FathomKit.Measurement<UInt64>
    var prominent = false

    var body: some View {
        switch measurement {
        case let .known(value, source):
            Text(value.formatted(.byteCount(style: .file)))
                .font(
                    prominent
                        ? .fathomDisplay(42)
                        : .fathomData(17, weight: .semibold)
                )
                .monospacedDigit()
                .help("\(value) bytes · \(source.rawValue)")
                .accessibilityLabel(
                    "\(value) bytes, source \(source.rawValue)"
                )
        case let .notPublished(reason):
            Text("not published")
                .font(
                    prominent
                        ? .fathomDisplay(28)
                        : .fathomData(15, weight: .medium)
                )
                .foregroundStyle(.white.opacity(0.82))
                .help(reason)
                .accessibilityLabel("Not published. \(reason)")
        case let .notAttributable(measured, explained):
            VStack(alignment: .trailing, spacing: 2) {
                Text("not attributable")
                    .font(.fathomData(15, weight: .medium))
                Text(
                    "\(measured) measured · \(explained) explained"
                )
                .font(.fathomSystem(10))
                .foregroundStyle(.white.opacity(0.82))
            }
            .accessibilityElement(children: .combine)
        }
    }
}
