import SwiftUI

/// The focus ring, drawn rather than inherited.
///
/// `FATHOM-DESIGN.md` specifies 2pt white at 60%, 3pt offset, 8pt radius, and
/// the prototype draws exactly that. Swift drew the macOS system ring instead,
/// and that divergence stood open for one good reason: the system ring honours
/// the user's own accessibility settings, and overriding it can regress the
/// very users the requirement exists for.
///
/// That objection is about *losing the settings*, not about the ring's
/// appearance — so this ring honours them. Under Increased Contrast it goes to
/// full white and 3pt, which is stronger than the system ring it replaces
/// rather than weaker.
///
/// The 60% value was checked rather than assumed: a focus ring is a non-text
/// UI component, so WCAG 1.4.11 asks 3:1, and 60% white measures 3.31:1 on the
/// worst world's plate. `scripts/check-contrast.py` proves it from source, so
/// the value here and the value the rule permits cannot drift apart.
struct FathomFocusRing: ViewModifier {
    /// Matches the prototype's `:focus-visible` radius. A ring rounder than
    /// the control it surrounds reads as a halo rather than an outline.
    var cornerRadius: CGFloat = 8

    @Environment(\.colorSchemeContrast) private var contrast
    @FocusState private var isFocused: Bool

    func body(content: Content) -> some View {
        content
            .focused($isFocused)
            .overlay {
                if isFocused {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(ringColor, lineWidth: lineWidth)
                        // Outward, so the ring never covers the thing it is
                        // pointing at.
                        .padding(-offset)
                }
            }
    }

    private var isIncreased: Bool { contrast == .increased }

    /// 60% is the specified value. Increased Contrast takes it to full white,
    /// which measures 6.12:1 on the worst world against the 3:1 the rule asks.
    private var ringColor: Color {
        .white.opacity(isIncreased ? 1 : FathomFocus.ringOpacity)
    }

    private var lineWidth: CGFloat {
        isIncreased ? FathomFocus.increasedLineWidth : FathomFocus.lineWidth
    }

    private var offset: CGFloat { FathomFocus.offset }
}

/// The focus ring's values, in one place so the gate can read them.
enum FathomFocus {
    static let ringOpacity: Double = 0.6
    static let lineWidth: CGFloat = 2
    static let increasedLineWidth: CGFloat = 3
    static let offset: CGFloat = 3

    /// How far the ring extends beyond the control it surrounds.
    ///
    /// The stroke is centred on the path, so half of it falls outside the
    /// offset, and Increased Contrast widens it to 3pt. Anything that clips
    /// its children has to leave this much room or the ring loses an edge —
    /// `FathomRail` did, on the first icon.
    static var reach: CGFloat { offset + increasedLineWidth / 2 }
}

extension View {
    /// Draws FATHOM's focus ring on this control.
    ///
    /// Use on anything focusable that sits on a colour world. Controls inside a
    /// sheet or popover keep the system ring, because those surfaces are
    /// standard macOS chrome and the system ring is right there.
    func fathomFocusRing(cornerRadius: CGFloat = 8) -> some View {
        modifier(FathomFocusRing(cornerRadius: cornerRadius))
    }
}
