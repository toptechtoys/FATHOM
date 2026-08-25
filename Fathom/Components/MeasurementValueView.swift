import FathomKit
import SwiftUI

struct MeasurementValueView: View {
    let measurement: FathomKit.Measurement<UInt64>
    var prominent = false
    /// Which claim this value makes — "On disk", "Freed if deleted" — for
    /// VoiceOver. On screen the column position says it; in speech two bare
    /// byte counts in a row are indistinguishable, which loses exactly the
    /// two-number distinction the product exists to draw.
    var spokenRole: String?

    var body: some View {
        switch measurement {
        case let .known(value, source):
            Text(ByteString.file(value))
                .font(
                    prominent
                        ? .fathomDisplay(42)
                        : .fathomData(17, weight: .semibold)
                )
                .monospacedDigit()
                .help("\(value) bytes · \(source.rawValue)")
                .accessibilityLabel(
                    spoken("\(value) bytes, source \(source.rawValue)")
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
                .accessibilityLabel(spoken("not published. \(reason)"))
        case let .notAttributable(measured, explained):
            VStack(alignment: .trailing, spacing: 2) {
                Text("not attributable")
                    .font(.fathomData(15, weight: .medium))
                // Formatted like every other figure: the raw integers this
                // used to print were the one place bytes reached a screen
                // without going through ByteString.
                Text(
                    "\(ByteString.file(measured)) measured · "
                        + "\(ByteString.file(explained)) explained"
                )
                .font(.fathomSystem(10))
                .foregroundStyle(.white.opacity(0.82))
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                spoken(
                    "not attributable, \(ByteString.file(measured)) measured, "
                        + "\(ByteString.file(explained)) explained"
                )
            )
        }
    }

    private func spoken(_ body: String) -> String {
        spokenRole.map { "\($0), \(body)" } ?? body
    }
}
