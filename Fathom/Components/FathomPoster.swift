import SwiftUI

struct FathomPoster: View {
    let title: String
    let message: String
    let symbol: String
    let world: FathomColorWorld
    let shape: AnyShape
    let isScanning: Bool
    let action: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            FathomObject(
                symbol: symbol,
                world: world,
                shape: shape
            )
            .frame(width: 250, height: 250)
            .padding(.bottom, 32)

            Text(title)
                .font(.fathomDisplay(48))
                .tracking(-1.75)
                .padding(.bottom, 12)

            Text(message)
                .font(.fathomSystem(15))
                .foregroundStyle(.white.opacity(0.82))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 520)
                .lineSpacing(3)

            Button(action: action) {
                ZStack {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    world.bottom,
                                    world.middle
                                ],
                                center: .topLeading,
                                startRadius: 0,
                                endRadius: 95
                            )
                        )
                        .shadow(
                            color: world.bottom.opacity(0.62),
                            radius: 25
                        )
                    if isScanning {
                        ProgressView()
                            .controlSize(.large)
                            .tint(.white)
                    } else {
                        Text("Scan")
                            .font(.fathomSystem(14, weight: .bold))
                    }
                }
                .frame(width: 86, height: 86)
            }
            .buttonStyle(.plain)
            .disabled(isScanning)
            .padding(.top, 34)
            .accessibilityLabel(
                isScanning ? "Scanning \(title)" : "Scan \(title)"
            )
        }
        .padding(.horizontal, 36)
        .padding(.bottom, 24)
    }
}

private struct FathomObject: View {
    let symbol: String
    let world: FathomColorWorld
    let shape: AnyShape

    var body: some View {
        ZStack {
            shape
                .fill(.black.opacity(0.46))
                .frame(width: 215, height: 48)
                .blur(radius: 30)
                .offset(y: 120)

            shape
                .fill(
                    LinearGradient(
                        colors: [world.objectLight, world.objectDark],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay {
                    shape.fill(
                        RadialGradient(
                            colors: [.white.opacity(0.44), .clear],
                            center: UnitPoint(x: 0.3, y: 0.2),
                            startRadius: 0,
                            endRadius: 145
                        )
                    )
                }
                .overlay {
                    shape.fill(
                        RadialGradient(
                            colors: [.clear, .black.opacity(0.28)],
                            center: UnitPoint(x: 0.7, y: 0.9),
                            startRadius: 0,
                            endRadius: 180
                        )
                    )
                }
                .overlay {
                    shape.stroke(.white.opacity(0.30), lineWidth: 1.5)
                }
                .overlay(alignment: .topLeading) {
                    Ellipse()
                        .fill(.white.opacity(0.44))
                        .frame(width: 105, height: 22)
                        .blur(radius: 17)
                        .rotationEffect(.degrees(-20))
                        .offset(x: 26, y: 17)
                }

            Image(systemName: symbol)
                .font(.fathomSystem(92, weight: .thin))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(.white.opacity(0.96))
                .shadow(color: .black.opacity(0.30), radius: 5, y: 3)
        }
    }
}
