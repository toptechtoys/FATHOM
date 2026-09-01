import FathomKit
import SwiftUI

/// The one pill a section may end with.
///
/// The label states the outcome and the cost, in that order — *Move 101.0 GB
/// to Trash*, not *Continue*.
///
/// **One primary action per section.** A secondary control that declines or
/// retreats — *Back*, *Scan again*, *Cancel* — is not a second action and does
/// not count against it; it is the way out of the first one, and Storage, Deep
/// Scan and Cloud each need theirs. This rule read "one per section, never
/// two" until 26 August, which those three sections had always violated. The
/// rule was the thing that was wrong: removing their way out to satisfy a
/// sentence would have been the worse reading. Two *primary* actions side by
/// side is still forbidden — that is a section that has not decided what it is
/// asking for.
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
                            .tint(isProminent ? .black : .white)
                    }
                    Text(title)
                }
                .font(.fathomSystem(13, weight: .semibold))
                .foregroundStyle(
                    // The prominent fill reuses the menu-bar chip's gated
                    // pairing — black 82% on white 88% — the one light
                    // surface the contrast gate already composites.
                    isProminent
                        ? Color.black.opacity(0.82)
                        : Color.white.opacity(0.92)
                )
                .padding(.horizontal, 22)
                .padding(.vertical, 12)
                .background(
                    isProminent
                        ? Color.white.opacity(isHovering && !isBusy ? 1 : 0.88)
                        : Color.white.opacity(isHovering && !isBusy ? 0.14 : 0.08)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(
                            .white.opacity(isProminent ? 0 : 0.22),
                            lineWidth: 0.5
                        )
                }
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(
                    color: .black.opacity(isProminent ? 0.28 : 0),
                    radius: 9,
                    y: 3
                )
                .scaleEffect(isHovering && !isBusy ? 1.02 : 1)
                .animation(reduceMotion ? nil : .fathomPress, value: isHovering)
                .contentShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .fathomFocusRing(cornerRadius: 12)
            .disabled(isBusy)
            .onHover { isHovering = $0 }
            // The label goes on the Button itself. It used to go on the
            // enclosing HStack, under `.accessibilityElement(children:
            // .ignore)` — which replaces the children with one element that
            // has no action, so VoiceOver saw a thing that announced itself
            // as a button and did nothing when activated. The manually added
            // `.isButton` trait was the tell: a real Button never needs one.
            //
            // Every route to data in this app is a FathomAction, including
            // "Run the first Deep Scan", so that made the whole product
            // plausibly unreachable by screen reader.
            //
            // `isBusy` is spoken as well as dimmed. `.disabled` conveys
            // "dimmed", which says the button cannot be pressed but not that
            // the thing it starts is already running — on Deep Scan the
            // difference is the whole state of the screen.
            .accessibilityLabel(spokenLabel)

            if let cost {
                Text(cost)
                    .font(.fathomSystem(11.5))
                    .foregroundStyle(.white.opacity(FathomSurface.minimumTextOpacity))
                    .fixedSize(horizontal: false, vertical: true)
                    // Already spoken as part of the button's label; left
                    // visible, and not repeated to VoiceOver.
                    .accessibilityHidden(true)
            }
        }
    }

    private var spokenLabel: String {
        let base = cost.map { "\(title). \($0)" } ?? title
        return isBusy ? "\(base). Running." : base
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
    /// When the work being waited on began. Rendered as a live elapsed clock
    /// beside the busy state — a long walk that prints no numbers yet can
    /// still always say how long it has been walking.
    var busySince: Date?
    /// What the walk is reading right now. The elapsed clock above proves the
    /// app is alive; this proves it is getting somewhere, which is the part a
    /// person watching a five-minute phase actually wants.
    var liveProgress: LiveScanProgress?
    var action: (() -> Void)?

    var body: some View {
        // The header stays at the top; the message block floats in the
        // middle of the leftover height instead of stacking under the header
        // with a page of dead ground below it. The GeometryReader gives the
        // inner column the viewport's height as a minimum, so the spacers
        // can centre — and content taller than the viewport still scrolls.
        GeometryReader { viewport in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    FathomSectionHeader(
                        title: title,
                        subtitle: subtitle,
                        isLive: false
                    )

                    Spacer(minLength: 24)

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

                    if isBusy, let busySince {
                        // `style: .relative` keeps itself current; no timer.
                        (Text("Running for ") + Text(busySince, style: .relative))
                            .font(.fathomSystem(11.5))
                            .monospacedDigit()
                            .foregroundStyle(
                                .white.opacity(FathomSurface.minimumTextOpacity)
                            )
                            .padding(.top, 12)
                    }

                    if isBusy, let liveProgress {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(
                                liveProgress.entryCount.formatted()
                                    + " entries · "
                                    + ByteString.file(liveProgress.bytesOnDisk)
                            )
                            .monospacedDigit()
                            Text(liveProgress.currentDirectory)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        .font(.fathomSystem(11.5))
                        .foregroundStyle(
                            .white.opacity(FathomSurface.minimumTextOpacity)
                        )
                        .padding(.top, 6)
                        .frame(maxWidth: 520, alignment: .leading)
                    }

                    Spacer(minLength: 96)
                }
                .padding(EdgeInsets(top: 22, leading: 28, bottom: 40, trailing: 28))
                .frame(minHeight: viewport.size.height)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
