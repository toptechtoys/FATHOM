import FathomKit
import SwiftUI

struct HardwareMeasurementView<Value: Sendable>: View {
    let measurement: FathomKit.Measurement<Value>
    let format: (Value) -> String
    var prominent = false
    /// Which claim this value makes — "on disk", "freed if deleted" — for
    /// VoiceOver. On screen the column position says it; in speech two bare
    /// byte counts in a row are indistinguishable, which loses exactly the
    /// two-number distinction the product exists to draw.
    ///
    /// `MeasurementValueView` has carried this since the August pass. This
    /// view did not, and it is the one Reclaim's dry-run review uses — the
    /// single screen in the app that moves files.
    var spokenRole: String?

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
                    spoken("\(format(value)), source \(source.rawValue)")
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
                .accessibilityLabel(spoken("not published. \(reason)"))
        case let .notAttributable(measured, explained):
            VStack(alignment: .leading, spacing: 2) {
                Text("not attributable")
                    .font(.fathomData(15, weight: .medium))
                Text(
                    "\(format(measured)) measured · \(format(explained)) explained"
                )
                .font(.fathomSystem(10))
                .foregroundStyle(.white.opacity(0.82))
                // At fathomSystem(10) x 1.45 = 14.5pt this line measures
                // 283.6pt for two full byte strings, wider than any column
                // that holds it — Reclaim's rule rows and its dry-run review
                // both put it in a right-aligned stack that then restacks
                // around a three-line value. Shortening keeps the remainder
                // on one line without abbreviating either word: "measured"
                // and "explained" are the two-number claim itself.
                .lineLimit(2)
                .minimumScaleFactor(0.75)
            }
            // `.combine` read the interpunct aloud and dropped the role.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                spoken(
                    "not attributable, \(format(measured)) measured, "
                        + "\(format(explained)) explained"
                )
            )
        }
    }

    private func spoken(_ body: String) -> String {
        spokenRole.map { "\($0), \(body)" } ?? body
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
