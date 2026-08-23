import FathomKit
import SwiftUI

/// The 64pt navigation rail.
///
/// Fixed width, always icons, never labels — see *The rail* in
/// `FATHOM-DESIGN.md`. Twenty sections in four groups, separated by a hairline
/// rather than a text heading, so the grouping costs no vertical space.
///
/// Two things the prototype draws that this deliberately does not. It paints
/// three traffic lights, because a web page has to; the real window gets the
/// system's own, which stay in the right place and honour the user's settings.
/// And the public IP row moved to the Network section, where the address it
/// reports actually belongs — see `PublicIPPanel`.
struct FathomRail: View {
    @Binding var selection: AppSection

    var body: some View {
        VStack(spacing: 0) {
            // The system traffic lights sit here. Reserving their height keeps
            // the first icon clear of them without drawing anything.
            Color.clear
                .frame(height: 34)
                .accessibilityHidden(true)

            ScrollView {
                VStack(spacing: 3) {
                    ForEach(
                        Array(AppSection.railGroups.enumerated()),
                        id: \.offset
                    ) { index, group in
                        if index > 0 {
                            divider
                        }
                        ForEach(group) { section in
                            item(section)
                        }
                    }
                }
                .padding(.bottom, 8)
            }
            .scrollIndicators(.hidden)

            footer
        }
        .frame(width: 64)
        .background(FathomSurface.rail)
        .background(.ultraThinMaterial.opacity(0.18))
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(.white.opacity(0.09))
                .frame(width: 0.5)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Sections")
    }

    private var divider: some View {
        Rectangle()
            .fill(.white.opacity(0.22))
            .frame(width: 22, height: 1)
            .padding(.top, 9)
            .padding(.bottom, 8)
            .accessibilityHidden(true)
    }

    private func item(_ section: AppSection) -> some View {
        let isSelected = selection == section
        return Button {
            selection = section
        } label: {
            FathomSectionIcon(section: section)
                .foregroundStyle(
                    isSelected ? .white : .white.opacity(0.82)
                )
                .frame(width: 42, height: 42)
                .background {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        .white.opacity(0.26),
                                        .white.opacity(0.13),
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .overlay(alignment: .top) {
                                Rectangle()
                                    .fill(.white.opacity(0.3))
                                    .frame(height: 1)
                                    .clipShape(
                                        RoundedRectangle(cornerRadius: 10)
                                    )
                            }
                    }
                }
                .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(RailItemButtonStyle())
        .fathomFocusRing(cornerRadius: 10)
        .help(section.rawValue)
        .accessibilityLabel(section.rawValue)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    /// The app's own idle cost, in the app's own chrome.
    ///
    /// The figure comes from `FathomBar` measuring itself, not from the budget.
    /// Until the widget has run long enough to have two samples the tooltip
    /// says so, which is the honest version of the prototype's hardcoded
    /// `0.2% CPU · energy 2.1`.
    private var footer: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(.white.opacity(0.1))
                .frame(height: 0.5)
            LiveDot()
                .padding(.top, 12)
                .padding(.bottom, 14)
        }
        .help(costDescription)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(costDescription)
    }

    /// Showing your own cost in your own chrome is a claim only an honest
    /// utility can make — which is why it has to be the measured figure and
    /// not the budget.
    private var costDescription: String {
        guard case let .known(cost, _) = MeasuredIdleCost.load() else {
            return "Sampling at 1 Hz. The menu bar widget has not measured its own cost yet."
        }
        let percent = cost.cpuPercent
            .formatted(.number.precision(.fractionLength(2)))
        return "Sampling at 1 Hz. Menu bar widget measured at \(percent)% CPU with \(cost.itemCount) items."
    }
}

/// Press feedback only. Hover is handled by the style so the whole 42pt target
/// lights up rather than just the glyph.
private struct RailItemButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                if isHovering && !configuration.isPressed {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(.white.opacity(0.11))
                }
            }
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(
                reduceMotion ? nil : .fathomPress,
                value: configuration.isPressed
            )
            .onHover { isHovering = $0 }
    }
}

/// The pulsing live indicator, 7pt with a glow.
///
/// Reduce Motion stops the pulse and leaves the dot lit — the dot carries the
/// meaning, the pulse is decoration.
struct LiveDot: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var size: CGFloat = 7
    @State private var isDim = false

    var body: some View {
        Circle()
            .fill(FathomSemantic.live)
            .frame(width: size, height: size)
            .shadow(color: FathomSemantic.live, radius: 4.5)
            .opacity(isDim ? 0.3 : 1)
            .animation(
                reduceMotion
                    ? nil
                    : .easeInOut(duration: 1.1).repeatForever(autoreverses: true),
                value: isDim
            )
            .onAppear { if !reduceMotion { isDim = true } }
            .accessibilityHidden(true)
    }
}
