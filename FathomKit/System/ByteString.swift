import Foundation

/// Every byte figure the product prints, in one place.
///
/// This exists because of one word. `ByteCountFormatStyle` spells out zero by
/// default, so `0.formatted(.byteCount(style: .file))` is **"Zero kB"** — and
/// twenty-eight call sites across ten sections, FathomKit and the widget were
/// all taking that default. The Network section showed a column of *Zero kB/s*
/// against *29 kB/s* the first time anyone ran the app.
///
/// Two things are wrong with that in this product specifically. A figure is
/// supposed to be a figure: FATHOM's argument is that it prints what it
/// measured, and a word where the numeral goes reads as a euphemism for a
/// value nobody checked. And FATHOM-DESIGN.md calls tabular numerals
/// non-negotiable, which a spelled-out zero silently opts out of — "Zero kB"
/// does not align with "29 kB/s" in a column no matter what the font does.
///
/// Zero is a real reading here. An interface that carried no traffic this
/// second carried **0 bytes**, and that is not the same statement as *not
/// published*, which is what `Measurement` is for. Both need to be sayable,
/// and they need to look different.
///
/// The formatting lives here rather than beside each view for the same reason
/// the accessibility labels do: written once beside the thing it describes, it
/// cannot drift from it. The CI audit fails the build if `.byteCount(` appears
/// anywhere else.
public enum ByteString {
    /// Bytes on disk.
    public static func file(_ value: UInt64) -> String {
        value.formatted(.byteCount(style: .file, spellsOutZero: false))
    }

    /// Bytes on disk, from a computed value.
    ///
    /// Out-of-range says so rather than printing whatever the conversion
    /// happened to produce — an arithmetic result that cannot be a byte count
    /// is a defect, not a number.
    public static func file(rounding value: Double) -> String {
        guard value.isFinite, value >= 0, value <= Double(UInt64.max) else {
            return "outside display range"
        }
        return file(UInt64(value.rounded()))
    }

    /// Bytes in RAM. macOS reports memory in powers of two, and the `.memory`
    /// style is what says so.
    public static func memory(_ value: UInt64) -> String {
        value.formatted(.byteCount(style: .memory, spellsOutZero: false))
    }

    /// Whole gigabytes, for the machine line — *MacBook Air M2 · 16 GB*.
    public static func memoryGigabytes(_ value: UInt64) -> String {
        value.formatted(
            .byteCount(style: .memory, allowedUnits: .gb, spellsOutZero: false)
        )
    }

    /// A throughput. The rate and its unit are one figure and wrap as one.
    public static func perSecond(_ value: UInt64) -> String {
        file(value) + "/s"
    }
}
