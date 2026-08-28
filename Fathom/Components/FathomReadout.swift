import FathomKit
import SwiftUI

/// The row of readouts at the top of every section.
///
/// `repeat(auto-fit, minmax(210pt, 1fr))` with the cells 10pt apart — the
/// native-feel pass's `.rg`, and the cells are separated cards now rather than
/// one continuous table sharing a 1pt hairline. Each card draws its whole own
/// border; nothing shows through the gap, so the ragged last row that the
/// hairline construction had to work around no longer arises.
///
/// The 4pt below is the prototype's `margin-bottom`, and it is not decoration:
/// it keeps the first panel's own card edge from meeting the bottom of the
/// readout cards as one thick, slightly uneven line. It belongs to the grid
/// rather than to twenty section views, for the same reason the labels do —
/// written once beside the thing it describes, it cannot drift from it.
struct FathomReadoutGrid<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        FathomReadoutRow {
            content
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 4)
    }
}

/// `repeat(auto-fit, minmax(190pt, 1fr))`, which SwiftUI has no column for.
///
/// `LazyVGrid` with `GridItem(.adaptive(minimum: 190))` is CSS *auto-fill*: it
/// keeps the tracks nothing landed in. The first time this app was run, four
/// readouts on a 2,184pt content column rendered at 198pt each and stopped a
/// third of the way across, with *not published* wrapping onto two lines in
/// three cells out of four. Nothing had gone wrong — that is what auto-fill
/// does, and it is not what the prototype asks for.
///
/// A `Layout` can count its own subviews, which is the whole difference:
/// auto-fit is auto-fill capped at the number of things there are to place.
/// The arithmetic is `ReadoutRowLayout` in FathomKit, where it is tested.
struct FathomReadoutRow: Layout {
    /// The prototype drew `minmax(190px, …)`; the native-feel pass widened it
    /// to 210 for the larger type.
    ///
    /// **Deliberately not multiplied by `FathomType.scale`, unlike every other
    /// container that holds scaled type.** Multiplying is what the arithmetic
    /// wants and it costs more than it buys. At the default 1,200pt window the
    /// content column is 930pt, so 210 + a 10pt gap gives four columns of a
    /// 225pt cell — 185pt of content once the card's 20pt padding is taken off
    /// each side. Anything from 230 up gives three, and twelve of the twenty
    /// sections carry exactly four readouts, so widening moves one of them
    /// onto a row of its own across most of the app. That is an owner
    /// decision about composition, not a fix.
    ///
    /// What it costs, stated rather than hidden: a full byte string —
    /// "494.38 GB" at fathomDisplay(34) × 1.45 = 49.3pt with tracking −1.02 —
    /// measures 266.8pt, so `minimumScaleFactor` below squeezes it to 0.694
    /// and it lands at 34.2pt, which is the size it rendered at before the
    /// scale existed. The readout headline is the one place in the app where
    /// ×1.45 currently buys nothing. 280 is the number that fixes it.
    var minimum: CGFloat = 210
    /// The prototype's `gap: 1px` made the cells one continuous table. The
    /// native-feel pass separates them into cards, so the gap is real space
    /// and each card owns its whole border.
    var gap: CGFloat = 10

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        // A nil or infinite proposal means "how wide would you like to be".
        // One row at the minimum track width is the honest answer, and it keeps
        // an unbounded number out of the arithmetic below.
        let natural = minimum * CGFloat(max(1, subviews.count))
            + gap * CGFloat(max(0, subviews.count - 1))
        let proposed = proposal.width
        let width = (proposed?.isFinite == true ? proposed! : natural)
        let heights = rowHeights(width: width, subviews: subviews)
        return CGSize(
            width: width,
            height: heights.reduce(0, +)
                + gap * CGFloat(max(0, heights.count - 1))
        )
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        let columns = ReadoutRowLayout.columnCount(
            width: bounds.width,
            itemCount: subviews.count,
            minimum: minimum,
            gap: gap
        )
        guard columns > 0 else { return }
        let cell = ReadoutRowLayout.cellWidth(
            width: bounds.width,
            columns: columns,
            gap: gap
        )
        let heights = rowHeights(width: bounds.width, subviews: subviews)
        var y = bounds.minY
        for (row, range) in ReadoutRowLayout.rows(
            itemCount: subviews.count,
            columns: columns
        ).enumerated() {
            for index in range {
                subviews[index].place(
                    at: CGPoint(
                        x: bounds.minX
                            + CGFloat(index - range.lowerBound) * (cell + gap),
                        y: y
                    ),
                    proposal: ProposedViewSize(width: cell, height: heights[row])
                )
            }
            y += heights[row] + gap
        }
    }

    /// Every cell in a row is as tall as the tallest one in it.
    ///
    /// A readout whose note runs to three lines makes its neighbours match,
    /// because the gap between two cells *is* the hairline and a short cell
    /// would leave that line stopping in mid-air.
    private func rowHeights(width: CGFloat, subviews: Subviews) -> [CGFloat] {
        let columns = ReadoutRowLayout.columnCount(
            width: width,
            itemCount: subviews.count,
            minimum: minimum,
            gap: gap
        )
        guard columns > 0 else { return [] }
        let cell = ReadoutRowLayout.cellWidth(
            width: width,
            columns: columns,
            gap: gap
        )
        return ReadoutRowLayout.rows(
            itemCount: subviews.count,
            columns: columns
        ).map { range in
            range.reduce(CGFloat(0)) { tallest, index in
                max(
                    tallest,
                    subviews[index].sizeThatFits(
                        ProposedViewSize(width: cell, height: nil)
                    ).height
                )
            }
        }
    }
}

/// One readout: a tracked label, a large value with an optional unit, and a
/// note capped at 32 characters.
///
/// A card, since the native-feel pass: radius 12, a top-lit gradient border
/// and a soft shadow, all drawn below. The sentence that used to stand here —
/// "no radius, no lift, no shadow, a readout is not a card" — described the
/// construction this replaced and sat directly above the code that replaced
/// it. Hover deepens the cell rather than lightening it: on the plate a
/// lighter hover walks the contrast back toward the field the plate exists to
/// escape.
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
                // Uppercase is a display choice. `.combine` below would take
                // the rendered string, and VoiceOver reads an all-caps word
                // it does not recognise a letter at a time — "F, A, T, H, O,
                // M, apostrophe, S". Spoken from the written casing instead.
                .accessibilityLabel(label)

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
        .padding(EdgeInsets(top: 18, leading: 20, bottom: 20, trailing: 20))
        .background(isHovering ? FathomSurface.rowHover : FathomSurface.card)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay {
            // Each card owns its border: brighter along the top edge where
            // the light would catch it, fading down the sides. Chrome only —
            // no text sits on the stroke, so the gate's cell model is
            // unchanged.
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.20), .white.opacity(0.05)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
        }
        .shadow(color: .black.opacity(0.22), radius: 8, y: 2)
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
                    // The same guard `valueText` carries, and for the same
                    // reason. At fathomDisplay(24) × 1.45 = 34.8pt the phrase
                    // measures 244.9pt against the 185pt a cell offers at the
                    // default window, so without this it wraps onto two lines
                    // — which is exactly the regression the comment at the
                    // head of `FathomReadoutRow` records having ended once.
                    // 185 / 244.9 = 0.755, comfortably above the 0.6 floor.
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
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
