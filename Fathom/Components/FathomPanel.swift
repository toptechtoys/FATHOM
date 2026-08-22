import SwiftUI

/// Everything below the readouts.
///
/// No card, no blur, no radius — a hairline across the top, a tracked label,
/// and the content. The panel is a division of the page rather than an object
/// sitting on it.
struct FathomPanel<Content: View>: View {
    let label: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle()
                .fill(.white.opacity(0.16))
                .frame(height: 0.5)
                .accessibilityHidden(true)

            Text(label.uppercased())
                .font(.fathomSystem(9, weight: .semibold))
                .tracking(1.44)
                .foregroundStyle(.white.opacity(FathomSurface.minimumTextOpacity))
                .padding(.top, 22)
                .padding(.bottom, 14)

            content
                .padding(.bottom, 26)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
    }
}

/// The sentence at the end of a section, saying the thing the numbers cannot.
///
/// A display headline and one paragraph capped at 66 characters. Every section
/// has one; several of them are the whole argument of the product.
struct FathomNote: View {
    let headline: String
    /// Named `detail` rather than `body`, which is taken.
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(headline)
                .font(.fathomDisplay(19))
                .tracking(-0.42)
                .fixedSize(horizontal: false, vertical: true)
            Text(detail)
                .font(.fathomSystem(12.5))
                .foregroundStyle(.white.opacity(FathomSurface.minimumTextOpacity))
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: 560, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// One row inside a panel: a name, and up to two right-aligned figures.
///
/// The second figure is the product — *freed if deleted* — so it carries the
/// semantic colour and an optional annotation beneath it. Hover deepens.
struct FathomDataRow<Leading: View, Trailing: View>: View {
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing
    var isEmphasised = false
    var action: (() -> Void)?

    @State private var isHovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let row = HStack(alignment: .center, spacing: 12) {
            leading
                .frame(maxWidth: .infinity, alignment: .leading)
            trailing
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity)
        .background(background)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .animation(reduceMotion ? nil : .fathomHover, value: isHovering)
        .onHover { isHovering = $0 }

        if let action {
            Button(action: action) { row }
                .buttonStyle(.plain)
        } else {
            row
        }
    }

    private var background: Color {
        if isEmphasised {
            // A row that is itself the finding — the unattributed remainder,
            // an included rule — reads a shade deeper than its neighbours so
            // it is distinguishable without colour alone.
            isHovering ? .black.opacity(0.20) : .black.opacity(0.14)
        } else {
            isHovering ? FathomSurface.rowHover : FathomSurface.row
        }
    }
}

extension FathomDataRow where Leading == AnyView, Trailing == AnyView {
    /// The common shape: a name on the left, one figure on the right.
    static func simple(
        _ name: String,
        value: String,
        valueColor: Color = .white,
        annotation: String? = nil,
        isPath: Bool = false,
        isEmphasised: Bool = false
    ) -> some View {
        FathomDataRow<AnyView, AnyView>(
            leading: {
                AnyView(
                    Text(name)
                        .font(isPath ? .fathomPath(12) : .fathomSystem(13))
                        .lineLimit(1)
                        .truncationMode(.middle)
                )
            },
            trailing: {
                AnyView(
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(value)
                            .font(.fathomSystem(13, weight: .medium))
                            .monospacedDigit()
                            .foregroundStyle(valueColor)
                        if let annotation {
                            Text(annotation)
                                .font(.fathomSystem(10.5))
                                .foregroundStyle(
                                    .white.opacity(FathomSurface.minimumTextOpacity)
                                )
                        }
                    }
                )
            },
            isEmphasised: isEmphasised
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            annotation.map { "\(name), \(value), \($0)" } ?? "\(name), \(value)"
        )
    }
}

/// A panel's contents when macOS published nothing.
///
/// Inline and quiet — this is a state, not a failure. `HonestUnavailableView`
/// is the whole-section equivalent and is far too loud inside a panel.
struct FathomPanelUnavailable: View {
    let reason: String
    var isAttributionGap = false

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(isAttributionGap ? "not attributable" : "not published")
                .font(.fathomSystem(13, weight: .medium))
            Text(reason)
                .font(.fathomSystem(11.5))
                .foregroundStyle(.white.opacity(FathomSurface.minimumTextOpacity))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: 560, alignment: .leading)
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}
