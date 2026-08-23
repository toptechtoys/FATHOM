import SwiftUI

/// The colour field, under everything.
///
/// The prototype draws three layers and the plate goes on top of all three:
/// `linear-gradient(177deg, b1 0%, b2 60%, b3 100%)`, then the grain, then a
/// white radial highlight across the upper field. This is that stack, in that
/// order.
///
/// **The order is part of the specification.** The grain blends with `overlay`,
/// which is not commutative with the highlight's alpha compositing: blending
/// the grain against the bare field and laying the highlight over the result is
/// a different picture from the reverse, and a slightly darker one.
/// `scripts/check-contrast.py` composites the same three layers in the same
/// order, so the gate measures the field this actually draws.
///
/// **Two deliberate departures, both recorded in FATHOM-DESIGN.md.**
///
/// The highlight peaks at 15% where the prototype draws 30%. That is the
/// contrast rule winning over the visual spec, as `AGENTS.md` says it must:
/// at 30% body text on the bare plate measures 4.24:1 on the Storage world.
/// Only the strength changed — the geometry and the falloff are the
/// prototype's, halved stop for stop.
///
/// The gradient's 3° tilt is not reproduced. SwiftUI's endpoints are fractions
/// of the view, so a fixed pair of `UnitPoint`s holds an aspect ratio rather
/// than an angle, and the tilt would swing with every window resize. Vertical
/// is the one reading of `177deg` that stays where it was put.
struct FathomWorldBackground: View {
    let world: FathomColorWorld

    var body: some View {
        ZStack {
            LinearGradient(
                stops: [
                    .init(color: world.top, location: 0),
                    .init(color: world.middle, location: 0.6),
                    .init(color: world.bottom, location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            // Over the field and under the highlight, as the prototype has it.
            // The noise is bounded rather than merely faded, because `overlay`
            // drives bright channels toward white and this sits beneath text.
            // See FathomGrain.
            FathomGrainOverlay()

            // The white highlight across the upper field.
            //
            // The prototype puts it in a box inset `left:20%; top:-8%;
            // height:88%` and draws `radial-gradient(52% 58% at 50% 42%, …)`
            // inside it, so in window fractions it is an ellipse centred at
            // (0.60, 0.29) with radii (0.416w, 0.510h). Proportional rather
            // than a fixed radius: the field has to look the same on a 13-inch
            // display and a 32-inch one.
            //
            // Its outer edge lands at 80% of the window height, so the
            // highlight and the gradient's bottom stop never actually meet.
            // The gate composites them anyway, which is what keeps it the
            // pessimistic reading it is meant to be.
            //
            // Written out here rather than pulled into a `private var` on
            // purpose. The gate reads the draw order off this body, so a layer
            // hidden behind a name would be a layer it cannot see.
            GeometryReader { geometry in
                let size = geometry.size
                EllipticalGradient(
                    stops: [
                        .init(color: .white.opacity(0.15), location: 0),
                        .init(color: .white.opacity(0.05), location: 0.42),
                        .init(color: .clear, location: 0.72),
                        .init(color: .clear, location: 1),
                    ]
                )
                .frame(width: size.width * 0.832, height: size.height * 1.020)
                .position(x: size.width * 0.60, y: size.height * 0.29)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        .ignoresSafeArea()
    }
}
