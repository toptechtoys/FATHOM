import SwiftUI

struct HonestUnavailableView: View {
    let title: String
    let message: String
    let symbol: String
    let world: FathomColorWorld

    var body: some View {
        VStack(spacing: 22) {
            Image(systemName: symbol)
                .font(.fathomSystem(54, weight: .thin))
            Text(title).font(.fathomDisplay(38))
            Text("not published")
                .font(.fathomData(18, weight: .semibold))
                .foregroundStyle(.white.opacity(0.82))
            Text(message)
                .font(.fathomSystem(13))
                .foregroundStyle(.white.opacity(0.82))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 520)
        }
        .padding(40)
        .accessibilityElement(children: .combine)
    }
}
