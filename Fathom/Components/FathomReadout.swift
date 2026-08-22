import FathomKit
import SwiftUI

/// The row of readouts at the top of every section.
///
/// `repeat(auto-fit, minmax(190pt, 1fr))` with the cells 1pt apart. The hairline
/// between them is drawn by the cells, not behind them: each cell strokes its
/// own boundary, and two adjacent strokes meet in the 1pt gap to make the line.
///
/// The obvious construction — a hairline-coloured background showing through
/// the gap — breaks on the last row. When the cell count does not fill the row,
/// the leftover track shows the background as a pale block beside the final
/// cell. Rings leave it as plate. This is the same bug, and the same fix, as
/// the prototype carries.
struct FathomReadoutGrid<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 190), spacing: 1)],
            spacing: 1
        ) {
            content
        }
    }
}

/// One readout: a tracked label, a large value with an optional unit, and a
/// note capped at 32 characters.
///
/// No radius, no lift, no shadow. A readout is not a card. Hover deepens the
/// cell rather than lightening it — on the plate a lighter hover walks the
/// contrast back toward the field the plate exists to escape.
struct FathomReadout<Value: View>: View {
    let label: String
    var note: String?
    @ViewBuilder var value: Value

    @State private var isHovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label.uppercased())
                .font(.fathomSystem(9, weight: .semibold))
                .tracking(1.44)
                .foregroundStyle(.white.opacity(FathomSurface.minimumTextOpacity))
                .padding(.bottom, 12)

            value

            if let note {
                Text(note)
                    .font(.fathomSystem(11.5))
                    .foregroundStyle(.white.opacity(FathomSurface.minimumTextOpacity))
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 10)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(EdgeInsets(top: 16, leading: 18, bottom: 18, trailing: 18))
        .background(isHovering ? FathomSurface.rowHover : FathomSurface.card)
        .overlay {
            // Centred on the boundary, so half of it falls into the 1pt gap
            // and meets the neighbour's half.
            Rectangle()
                .stroke(.white.opacity(0.14), lineWidth: 1)
        }
        .animation(reduceMotion ? nil : .fathomHover, value: isHovering)
        .onHover { isHovering = $0 }
        .accessibilityElement(children: .combine)
    }
}

/// A readout whose value is a `Measurement`, rendering all three states.
///
/// Rule 2 in `AGENTS.md`: known, not published, not attributable. A component
/// that cannot draw all three is not finished, and the not-published state is
/// not an error — it is the product telling the truth about what macOS gives
/// it. Provenance is spoken to VoiceOver rather than hidden in a tooltip.
struct FathomMeasurementReadout<Value: Sendable>: View {
    let label: String
    let measurement: FathomKit.Measurement<Value>
    var unit: String?
    var note: String?
    let format: (Value) -> String

    var body: some View {
        FathomReadout(label: label, note: resolvedNote) {
            switch measurement {
            case let .known(value, _):
                valueText(format(value), unit: unit)
            case .notPublished:
                Text("not published")
                    .font(.fathomDisplay(24))
                    .foregroundStyle(.white.opacity(FathomSurface.minimumTextOpacity))
            case let .notAttributable(measured, _):
                valueText(format(measured), unit: unit)
            }
        }
        .accessibilityLabel(accessibilityLabel)
    }

    private func valueText(_ text: String, unit: String?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(text)
                .font(.fathomDisplay(34))
                .tracking(-1.02)
                .monospacedDigit()
            if let unit {
                Text(unit)
                    .font(.fathomSystem(13))
                    .foregroundStyle(.white.opacity(FathomSurface.minimumTextOpacity))
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.6)
    }

    /// The note says what the state means, not merely that there is one. An
    /// unattributed remainder gets its own sentence rather than being folded
    /// into the number above it.
    private var resolvedNote: String? {
        switch measurement {
        case .known:
            note
        case let .notPublished(reason):
            reason
        case let .notAttributable(measured, explained):
            "\(format(measured)) measured, \(format(explained)) explained. "
                + "The remainder is not attributable."
        }
    }

    private var accessibilityLabel: String {
        switch measurement {
        case let .known(value, source):
            "\(label), \(format(value))\(unit.map { " \($0)" } ?? ""), "
                + "source \(source.rawValue)"
        case let .notPublished(reason):
            "\(label), not published. \(reason)"
        case let .notAttributable(measured, explained):
            "\(label), not attributable. \(format(measured)) measured, "
                + "\(format(explained)) explained."
        }
    }
}
