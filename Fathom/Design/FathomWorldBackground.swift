import SwiftUI

struct FathomWorldBackground: View {
    let world: FathomColorWorld

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [world.top, world.middle, world.bottom],
                startPoint: .top,
                endPoint: .bottom
            )

            RadialGradient(
                colors: [
                    world.bottom.opacity(0.95),
                    .clear
                ],
                center: UnitPoint(x: 0.5, y: 1.2),
                startRadius: 0,
                endRadius: 620
            )

            RadialGradient(
                colors: [.white.opacity(0.15), .clear],
                center: UnitPoint(x: 0.6, y: 0.38),
                startRadius: 0,
                endRadius: 500
            )
        }
        .ignoresSafeArea()
    }
}
