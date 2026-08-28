import FathomKit
import SwiftUI

/// The navigation sidebar.
///
/// This began as the prototype's 64pt icon rail — "always icons, never
/// labels". The owner reviewed the running app on 25 August and asked for
/// names beside the icons, CleanMyMac-style, so it is now a 214pt labelled
/// sidebar; FATHOM-DESIGN.md carries the change, and the prototype declares
/// the same 214px. Twenty sections in four groups, still separated by
/// hairlines rather than headings.
///
/// The width is the one container here that is deliberately *not* multiplied
/// by `FathomType.scale`: 214 is a number the prototype and the design
/// document both state, and a width that scaled could not be written down in
/// either. The row absorbs the type instead — see `item(_:)`.
///
/// Two things the prototype draws that this deliberately does not. It paints
/// three traffic lights, because a web page has to; the real window gets the
/// system's own, which stay in the right place and honour the user's settings.
/// And the public IP row moved to the Network section, where the address it
/// reports actually belongs — see `PublicIPPanel`.
struct FathomRail: View {
    @Binding var selection: AppSection
    /// The prototype's 34pt row. Scaled rather than fixed because the label
    /// inside it is, and unlike every other container in the app this one
    /// cannot buy room by getting wider.
    @ScaledMetric(relativeTo: .subheadline) private var rowHeight: CGFloat = 34

    var body: some View {
        VStack(spacing: 0) {
            // The system traffic lights sit here. Reserving their height keeps
            // the first row clear of them without drawing anything.
            //
            // `reach` comes off this and goes back on inside the scroll below,
            // so the first row does not move: 34pt of clearance either way.
            // The difference is which side of the clipping boundary it is on.
            Color.clear
                .frame(height: 34 - FathomFocus.reach)
                .accessibilityHidden(true)

            ScrollView {
                VStack(spacing: 2) {
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
                .padding(.horizontal, 10)
                // A `ScrollView` clips its children, and the focus ring is
                // drawn *outside* the row it surrounds. The first row sat at
                // exactly y=0 — the app was asked and said so — which put the
                // top of its ring at -4pt and threw that edge away. Nothing
                // catches that but tabbing to the first row and looking, and
                // macOS ships with the keyboard navigation that makes it
                // reachable turned off.
                //
                // The bottom already had 8pt, which clears the same reach; it
                // is left alone because the last row was never the problem.
                .padding(.top, FathomFocus.reach)
                .padding(.bottom, 8)
            }
            .scrollIndicators(.hidden)

            footer
        }
        .frame(width: 214)
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
            .fill(.white.opacity(0.18))
            .frame(height: 1)
            .padding(.horizontal, 12)
            .padding(.top, 9)
            .padding(.bottom, 8)
            .accessibilityHidden(true)
    }

    private func item(_ section: AppSection) -> some View {
        let isSelected = selection == section
        return Button {
            selection = section
        } label: {
            HStack(spacing: 10) {
                FathomSectionIcon(section: section)
                    .frame(width: 22)
                Text(section.rawValue)
                    .font(.fathomSystem(12, weight: isSelected ? .semibold : .medium))
                    // Two lines, not one. The sidebar is a fixed 214pt, which
                    // leaves 142pt for the name once the 10pt outer padding,
                    // the 10pt inner padding, the 22pt icon and the 10pt gap
                    // are taken; "Sensors & Power" at 12 x 1.45 = 17.4pt
                    // measures 138.0pt in Archivo SemiBold. Four points of
                    // slack at the default text size, and none at the first
                    // Dynamic Type step above it — at which point one line
                    // can only truncate the longest section name in the app.
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                Spacer(minLength: 0)
            }
            .foregroundStyle(
                isSelected ? .white : .white.opacity(0.82)
            )
            .padding(.horizontal, 10)
            // Minimum, not fixed. 34pt is the prototype's `.nb{height:34px}`
            // and it still is at the default size — one line of 17.4pt
            // Archivo is 18.9pt tall, so nothing moves. A fixed height had
            // no room left for a second line, and a rail row that clips its
            // own section name is unnavigable rather than merely untidy.
            .frame(minHeight: rowHeight)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 8)
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
                                    RoundedRectangle(cornerRadius: 8)
                                )
                        }
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(RailItemButtonStyle())
        .fathomFocusRing(cornerRadius: 8)
        // No `.help` here any more. It was written when the rail was 64pt of
        // icons and the tooltip was the only way to learn a section's name;
        // the name is visible text now, and SwiftUI publishes `.help` as the
        // accessibility help, so with VoiceOver hints on the rail announced
        // every section twice — "Storage, button. Storage."
        //
        // `.isButton` is not added either: a real Button already carries it,
        // and adding it by hand is the tell that an element has been replaced
        // by a synthetic one that cannot be pressed.
        .accessibilityLabel(section.rawValue)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
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
            HStack(spacing: 8) {
                LiveDot()
                VStack(alignment: .leading, spacing: 1) {
                    Text("Live · 1 Hz")
                        .font(.fathomSystem(10, weight: .semibold))
                    // The sidebar has room now, so the app's own measured
                    // cost is visible instead of hiding in a tooltip —
                    // still the measured figure, never the budget.
                    if case let .known(cost, _) = MeasuredIdleCost.load() {
                        Text(
                            "Widget \(cost.cpuPercent.formatted(.number.precision(.fractionLength(2))))% CPU"
                        )
                        .font(.fathomSystem(10))
                        .foregroundStyle(
                            .white.opacity(FathomSurface.minimumTextOpacity)
                        )
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
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
                    RoundedRectangle(cornerRadius: 8)
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
