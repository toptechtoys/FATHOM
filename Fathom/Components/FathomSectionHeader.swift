import FathomKit
import SwiftUI

/// The header every section carries.
///
/// Title, the machine line, and a live pill on the right holding the section's
/// own subtitle. Baseline-aligned, with a hairline under it.
///
/// The subtitle says what this section is reading and how often, so the claim
/// on screen is dated without a timestamp cluttering every figure.
struct FathomSectionHeader: View {
    let title: String
    let subtitle: String
    /// `false` for sections that read once rather than stream — the dot means
    /// *sampling right now*, and lighting it on a static screen would be a lie
    /// about where the numbers came from.
    var isLive = true

    @EnvironmentObject private var machine: MachineIdentityAppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 20) {
                HStack(alignment: .firstTextBaseline, spacing: 18) {
                    Text(title)
                        .font(.fathomDisplay(34))
                        .tracking(-0.95)
                    if !machine.headerLine.isEmpty {
                        Text(machine.headerLine)
                            .font(.fathomSystem(12.5))
                            .foregroundStyle(
                                .white.opacity(FathomSurface.minimumTextOpacity)
                            )
                    }
                }
                Spacer(minLength: 12)
                HStack(spacing: 9) {
                    if isLive { LiveDot(size: 5) }
                    Text(subtitle)
                        .font(.fathomSystem(11.5))
                        .foregroundStyle(
                            .white.opacity(FathomSurface.minimumTextOpacity)
                        )
                }
                .fixedSize(horizontal: true, vertical: false)
            }
            .padding(.bottom, 16)

            Rectangle()
                .fill(.white.opacity(0.16))
                .frame(height: 0.5)
        }
        .padding(.bottom, 20)
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isHeader)
        .accessibilityLabel(
            machine.headerLine.isEmpty
                ? "\(title). \(subtitle)"
                : "\(title). \(machine.headerLine). \(subtitle)"
        )
    }
}

/// The 32pt strip above the content column.
///
/// It states what the window is and how often it samples, which is the one
/// piece of chrome that earns permanent space: the reader should never have to
/// wonder whether what they are looking at is live.
struct FathomStatusStrip: View {
    var body: some View {
        HStack {
            Text("INSTRUMENT PANEL")
            Spacer()
            Text("1 HZ · LIVE")
        }
        .font(.fathomSystem(10, weight: .bold))
        .tracking(1)
        .foregroundStyle(.white.opacity(FathomSurface.minimumTextOpacity))
        .padding(.horizontal, 16)
        .frame(height: 32)
        .background(.black.opacity(0.25))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(.white.opacity(0.08))
                .frame(height: 0.5)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Instrument panel, sampling at 1 hertz")
    }
}

/// Reads the machine's identity once and holds the history depth.
///
/// `hw.model` and `hw.memsize` cannot change while the app is running, so this
/// reads them at launch rather than on every section change.
@MainActor
final class MachineIdentityAppModel: ObservableObject {
    @Published private(set) var identity: MachineIdentity
    /// `nil` until the history store has been read at all. Zero means it was
    /// read and holds nothing, which the header says differently.
    @Published var daysRecorded: Int?

    init(reader: MachineIdentityReader = MachineIdentityReader()) {
        identity = reader.read()
    }

    var headerLine: String { identity.headerLine(daysRecorded: daysRecorded) }
}
