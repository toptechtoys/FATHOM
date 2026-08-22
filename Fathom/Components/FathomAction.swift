import SwiftUI

/// The one pill a section may end with.
///
/// The label states the outcome and the cost, in that order — *Move 101.0 GB
/// to Trash*, not *Continue*. One per section, never two.
struct FathomAction: View {
    let title: String
    /// Shown beside the pill, not inside it: a cost is a fact about the action,
    /// and burying it in the label makes it easy to skim past.
    var cost: String?
    var isProminent = true
    var isBusy = false
    let action: () -> Void

    @State private var isHovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 14) {
            Button(action: action) {
                HStack(spacing: 8) {
                    if isBusy {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.white)
                    }
                    Text(title)
                }
                .font(.fathomSystem(13, weight: .semibold))
                .padding(.horizontal, 20)
                .padding(.vertical, 11)
                .background(.white.opacity(isProminent ? 0.14 : 0.08))
                .overlay {
                    RoundedRectangle(cornerRadius: 15)
                        .stroke(.white.opacity(0.22), lineWidth: 0.5)
                }
                .clipShape(RoundedRectangle(cornerRadius: 15))
                .scaleEffect(isHovering && !isBusy ? 1.04 : 1)
                .animation(reduceMotion ? nil : .fathomPress, value: isHovering)
                .contentShape(RoundedRectangle(cornerRadius: 15))
            }
            .buttonStyle(.plain)
            .disabled(isBusy)
            .onHover { isHovering = $0 }

            if let cost {
                Text(cost)
                    .font(.fathomSystem(11.5))
                    .foregroundStyle(.white.opacity(FathomSurface.minimumTextOpacity))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(cost.map { "\(title). \($0)" } ?? title)
    }
}

/// A section with nothing to show yet.
///
/// This replaces the poster the earlier direction used. It says what is missing
/// and why, and offers the one action that would fill it — no rendered object,
/// no circular Scan button, and no zeros standing in for numbers nobody has
/// measured.
///
/// The distinction it preserves is *not measured yet* versus *measured and
/// there is nothing*. Only the first belongs here.
struct FathomEmptySection: View {
    let title: String
    let subtitle: String
    let headline: String
    let detail: String
    var actionTitle: String?
    var actionCost: String?
    var isBusy = false
    var action: (() -> Void)?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                FathomSectionHeader(
                    title: title,
                    subtitle: subtitle,
                    isLive: false
                )

                FathomNote(headline: headline, detail: detail)

                if let actionTitle, let action {
                    FathomAction(
                        title: actionTitle,
                        cost: actionCost,
                        isBusy: isBusy,
                        action: action
                    )
                    .padding(.top, 22)
                }
            }
            .padding(EdgeInsets(top: 22, leading: 28, bottom: 40, trailing: 28))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
