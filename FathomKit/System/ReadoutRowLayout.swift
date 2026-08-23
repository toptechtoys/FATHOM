import CoreGraphics
import Foundation

/// The column arithmetic behind `repeat(auto-fit, minmax(190pt, 1fr))`.
///
/// This lives in FathomKit because SwiftUI has no column type that does it and
/// the difference is not cosmetic. `GridItem(.adaptive(minimum:))` is CSS
/// **auto-fill**: it keeps the tracks nothing landed in. **auto-fit**, which
/// the prototype specifies, collapses those empty tracks and lets the tracks
/// that do hold something share the whole width.
///
/// With four readouts across a 2,184pt content column that is the difference
/// between four 546pt cells filling the row and four 198pt cells huddled into
/// its first third — which is what the app rendered the first time anyone
/// looked at it. The row of readouts is the top of all twenty sections, so
/// getting it wrong is wrong twenty times.
public enum ReadoutRowLayout {
    /// How many columns `auto-fit` resolves to.
    ///
    /// The first term is the plain CSS grid arithmetic — how many tracks of
    /// `minimum`, separated by `gap`, fit in `width`. The second is what makes
    /// it *auto-fit* rather than auto-fill: never more tracks than there are
    /// things to put in them.
    public static func columnCount(
        width: CGFloat,
        itemCount: Int,
        minimum: CGFloat,
        gap: CGFloat
    ) -> Int {
        guard itemCount > 0 else { return 0 }
        // SwiftUI proposes an infinite width while it sizes a Layout, and
        // `Int(_:)` traps on a value it cannot represent. The first draft of
        // this file did the conversion unguarded and the app died at launch --
        // no window, no crash report, just a process that was not there a
        // second later. Unbounded width fits every readout on one row, which
        // is the right answer as well as a safe one.
        guard minimum > 0 else { return itemCount }
        guard width.isFinite else { return itemCount }
        guard width > 0 else { return 1 }
        let fitting = ((width + gap) / (minimum + gap)).rounded(.down)
        guard fitting.isFinite, fitting >= 1 else { return 1 }
        return max(1, min(itemCount, Int(fitting)))
    }

    /// The width each column takes once the gaps are removed.
    ///
    /// `1fr` shares what is left equally, so a row of readouts always reaches
    /// the far edge of the content column — the hairline between two cells is
    /// the gap, and a short row would leave that hairline hanging in space.
    public static func cellWidth(
        width: CGFloat,
        columns: Int,
        gap: CGFloat
    ) -> CGFloat {
        guard columns > 0, width.isFinite else { return 0 }
        return max(0, (width - gap * CGFloat(columns - 1)) / CGFloat(columns))
    }

    /// The index range of each row, in order.
    public static func rows(itemCount: Int, columns: Int) -> [Range<Int>] {
        guard itemCount > 0, columns > 0 else { return [] }
        return stride(from: 0, to: itemCount, by: columns).map {
            $0..<min($0 + columns, itemCount)
        }
    }
}
