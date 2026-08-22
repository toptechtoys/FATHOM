import SwiftUI

/// The poster direction's card.
///
/// Superseded by `FathomReadoutGrid` and `FathomPanel`. It survives only for
/// the sections not yet converted, and goes when the last of them does — it
/// used to live inside `EnduranceView`, which no longer uses it.
struct HardwareResultCard<Content: View>: View {
    let label: String
    let content: Content

    init(
        label: String,
        @ViewBuilder content: () -> Content
    ) {
        self.label = label
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            Text(label)
                .font(.fathomSystem(10.5, weight: .bold))
                .tracking(1.05)
                .foregroundStyle(.white.opacity(0.82))
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(24)
        .background(FathomSurface.card)
        .background(.ultraThinMaterial.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .stroke(.white.opacity(0.20), lineWidth: 0.5)
        }
    }
}
