import FathomKit
import SwiftUI

/// Item / on disk / freed if deleted.
///
/// The second column is the product. A row that frees nothing shows `0` at the
/// muted weight rather than being hidden, because *this frees nothing* is the
/// answer people came for; a row that frees something carries the freeable
/// colour and the figure, never the colour alone.
struct FathomTwoNumberTable: View {
    struct Row: Identifiable {
        /// What the freed-if-deleted column claims. Four cases, because the
        /// column makes four different claims and the `String?` this replaces
        /// could only spell two of them: `nil` stood for a measured zero, so
        /// a reading that was never published rendered as the numeral `0` —
        /// a not-published state presented as a measured fact.
        enum Freed {
            /// Deletion measurably frees this many bytes, pre-formatted.
            case bytes(String)
            /// Deletion measurably frees nothing. A fact, not a gap.
            case nothing
            /// macOS did not publish the reading.
            case notPublished
            /// Partly attributed; the text states both halves.
            case gap(String)
        }

        let id = UUID()
        let name: String
        let onDisk: String
        let freed: Freed
        var annotation: String?
        var isPath = true

        var freedText: String {
            switch freed {
            case let .bytes(text): text
            case .nothing: "0"
            case .notPublished: "not published"
            case let .gap(text): text
            }
        }

        /// Freeing nothing is not a caution, it is a fact. Only a row that
        /// frees something conditionally earns the caution colour, and the
        /// annotation always says why. The two gap states read at the same
        /// dimmed weight as *frees nothing* — words where a figure goes,
        /// never the figure's colour.
        var freedColor: Color {
            switch freed {
            case .bytes:
                annotation == nil
                    ? FathomSemantic.freeable
                    : FathomSemantic.caution
            case .nothing, .notPublished, .gap:
                .white.opacity(FathomSurface.minimumTextOpacity)
            }
        }

        var freedSpoken: String {
            switch freed {
            case let .bytes(text): "\(text) freed if deleted"
            case .nothing: "nothing freed if deleted"
            case .notPublished: "freed if deleted not published"
            case let .gap(text): "freed if deleted \(text)"
            }
        }
    }

    let rows: [Row]
    var hint: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            header
            ForEach(rows) { row in
                FathomDataRow(
                    leading: {
                        Text(row.name)
                            .font(row.isPath ? .fathomPath(12) : .fathomSystem(13))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    },
                    trailing: {
                        HStack(spacing: 0) {
                            Text(row.onDisk)
                                .font(.fathomSystem(13))
                                .monospacedDigit()
                                .frame(
                                    width: 110 * FathomType.scale,
                                    alignment: .trailing
                                )
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(row.freedText)
                                    .font(.fathomSystem(13, weight: .medium))
                                    .monospacedDigit()
                                    .foregroundStyle(row.freedColor)
                                if let annotation = row.annotation {
                                    Text(annotation)
                                        .font(.fathomSystem(10.5))
                                        .foregroundStyle(
                                            .white.opacity(
                                                FathomSurface.minimumTextOpacity
                                            )
                                        )
                                }
                            }
                            .frame(
                                width: 150 * FathomType.scale,
                                alignment: .trailing
                            )
                        }
                    }
                )
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(label(for: row))
            }
            if let hint {
                Text(hint)
                    .font(.fathomSystem(11.5))
                    .foregroundStyle(.white.opacity(FathomSurface.minimumTextOpacity))
                    .padding(.top, 7)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // The prototype's `.rw{grid-template-columns:minmax(0,1fr) 110px 150px}`,
    // carrying FathomType.scale because the figures in those two columns do.
    // At 110 the *on disk* column held 112.6pt of "not published" at
    // fathomSystem(13) x 1.45 = 18.85pt and wrapped it; 159.5 clears it by
    // 47pt. Header and body must move together or the column heads stop
    // standing over the figures they name.
    private var header: some View {
        HStack(spacing: 0) {
            Text("ITEM")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("ON DISK")
                .frame(width: 110 * FathomType.scale, alignment: .trailing)
            Text("FREED IF DELETED")
                .frame(width: 150 * FathomType.scale, alignment: .trailing)
        }
        .font(.fathomSystem(9, weight: .semibold))
        .tracking(1.26)
        .foregroundStyle(.white.opacity(FathomSurface.minimumTextOpacity))
        .padding(.horizontal, 13)
        .padding(.bottom, 4)
        .accessibilityHidden(true)
    }

    private func label(for row: Row) -> String {
        let base = "\(row.name), \(row.onDisk) on disk, \(row.freedSpoken)"
        return row.annotation.map { "\(base), \($0)" } ?? base
    }
}

extension FathomTwoNumberTable.Row.Freed {
    /// The cell for a freed-if-deleted measurement, written beside the type
    /// so the mapping from state to claim exists exactly once. A measured
    /// zero is `.nothing`; the two gap states stay themselves rather than
    /// borrowing the zero.
    static func cell(
        _ measurement: FathomKit.Measurement<UInt64>,
        format: (UInt64) -> String
    ) -> Self {
        switch measurement {
        case let .known(value, _):
            value == 0 ? .nothing : .bytes(format(value))
        case .notPublished:
            .notPublished
        case .notAttributable:
            .gap(measurement.described(format))
        }
    }
}

/// Name, meter, value — for anything that reports a level.
///
/// A device that publishes no battery level reads *does not report* in place of
/// the number, with an empty meter beside it. The row is not dimmed away: the
/// fact that a device will not say is itself worth seeing.
struct FathomDeviceRows: View {
    struct Device: Identifiable {
        let id = UUID()
        let name: String
        /// `nil` when the device publishes no level.
        let level: Double?
        var unreportedNote = "does not report"
    }

    let devices: [Device]

    var body: some View {
        VStack(spacing: 3) {
            ForEach(devices) { device in
                FathomDataRow(
                    leading: {
                        Text(device.name)
                            .font(.fathomSystem(13))
                            .lineLimit(1)
                    },
                    trailing: {
                        HStack(spacing: 12) {
                            meter(device.level)
                            Text(
                                device.level.map {
                                    ($0 * 100)
                                        .formatted(.number.precision(.fractionLength(0)))
                                        + "%"
                                } ?? device.unreportedNote
                            )
                            .font(
                                device.level == nil
                                    ? .fathomSystem(11).italic()
                                    : .fathomSystem(13, weight: .semibold)
                            )
                            .monospacedDigit()
                            .foregroundStyle(
                                .white.opacity(
                                    device.level == nil
                                        ? FathomSurface.minimumTextOpacity
                                        : 1
                                )
                            )
                            // "does not report" at fathomSystem(11).italic()
                            // x 1.45 measures 106.7pt upright, in a 110pt
                            // column, before the synthesised slant pushes its
                            // last glyph past the edge. 159.5 ends that.
                            .frame(
                                width: 110 * FathomType.scale,
                                alignment: .trailing
                            )
                        }
                    }
                )
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(label(for: device))
            }
        }
    }

    private func meter(_ level: Double?) -> some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.16))
                if let level {
                    Capsule()
                        .fill(.white.opacity(0.85))
                        .frame(width: geometry.size.width * min(max(level, 0), 1))
                }
            }
        }
        // Width scales with the type it stands beside; the 6pt bar height is
        // chrome and the prototype's `.dev .mt{height:6px}` does not move.
        .frame(width: 120 * FathomType.scale, height: 6)
    }

    /// The meter bar is the only thing on screen that says what the figure
    /// measures, and a bar says nothing at all in speech — "Magic Mouse, 64
    /// percent" leaves the listener to guess at battery, signal or volume.
    /// This component has exactly one caller, paired Bluetooth devices, so
    /// the word belongs here beside the meter rather than in the section.
    private func label(for device: Device) -> String {
        guard let level = device.level else {
            return "\(device.name), battery level \(device.unreportedNote)"
        }
        let percent = (level * 100).formatted(.number.precision(.fractionLength(0)))
        return "\(device.name), battery \(percent) percent"
    }
}

/// Things worth a look. Four at most, each one sentence.
///
/// The dot never carries the meaning alone: every item states its finding in
/// words and gives the number beside it. An empty feed is a valid, expected
/// state — see `FindingEngine`.
struct FathomFeed: View {
    let findings: [Finding]
    let open: (Finding.Subject) -> Void

    var body: some View {
        VStack(spacing: 3) {
            ForEach(findings) { finding in
                FathomDataRow(
                    leading: {
                        HStack(alignment: .top, spacing: 12) {
                            Circle()
                                .fill(tint(finding.kind))
                                .frame(width: 8, height: 8)
                                .padding(.top, 5)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(finding.title)
                                    .font(.fathomSystem(13.5, weight: .semibold))
                                    .fixedSize(horizontal: false, vertical: true)
                                Text(finding.detail)
                                    .font(.fathomSystem(11.5))
                                    .foregroundStyle(
                                        .white.opacity(
                                            FathomSurface.minimumTextOpacity
                                        )
                                    )
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    },
                    trailing: {
                        Text(finding.value)
                            .font(.fathomData(15, weight: .semibold))
                            .foregroundStyle(value(finding.kind))
                            // A finding's figure is a byte string: "1,023.4
                            // GB" at fathomData(15) x 1.45 = 21.75pt measures
                            // 112.7pt and "not published" 135.8pt, both over
                            // the prototype's 110pt column, both wrapping.
                            .frame(
                                width: 110 * FathomType.scale,
                                alignment: .trailing
                            )
                    },
                    action: { open(finding.subject) }
                )
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(
                    "\(finding.title). \(finding.detail) \(finding.value)"
                )
                .accessibilityHint("Opens the evidence")
            }
        }
    }

    private func tint(_ kind: Finding.Kind) -> Color {
        switch kind {
        case .freeable: FathomSemantic.freeable
        case .conditional: FathomSemantic.caution
        case .freesNothing: FathomSemantic.blocked
        case .informational: FathomSemantic.informational
        }
    }

    /// A figure that frees nothing is white, not red. Zero is a fact here, not
    /// a fault, and rule 7 forbids dressing routine state as an alarm.
    private func value(_ kind: Finding.Kind) -> Color {
        switch kind {
        case .freeable: FathomSemantic.freeable
        case .conditional: FathomSemantic.caution
        case .freesNothing, .informational: .white
        }
    }
}

/// The arithmetic, left to right, ending on the conclusion.
///
/// Used where a number is only trustworthy if you can see how it was reached —
/// Endurance being the case that matters.
struct FathomChain: View {
    struct Step: Identifiable {
        let id = UUID()
        let label: String
        let value: String
        let detail: String
    }

    let steps: [Step]

    var body: some View {
        LazyVGrid(
            // The track holds a display figure, so it carries the type's
            // factor. Even so it is the tightest container left: a step card
            // needs 174.8pt for "123.45 TB" at fathomDisplay(23) x 1.45 =
            // 33.35pt, plus 30pt of padding and 29pt for the arrow beside it
            // — 233.8pt against the 217.5 this resolves to. Wide windows are
            // fine, because `.adaptive` grows the track to fill; a window
            // near 770pt is where the value wraps.
            columns: [
                GridItem(.adaptive(minimum: 150 * FathomType.scale), spacing: 10),
            ],
            alignment: .leading,
            spacing: 10
        ) {
            ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(step.label.uppercased())
                            .font(.fathomSystem(9, weight: .semibold))
                            .tracking(1.26)
                            .foregroundStyle(
                                .white.opacity(FathomSurface.minimumTextOpacity)
                            )
                        Text(step.value)
                            .font(.fathomDisplay(23))
                            .tracking(-0.46)
                            .padding(.top, 4)
                        Text(step.detail)
                            .font(.fathomSystem(10.5))
                            .foregroundStyle(
                                .white.opacity(FathomSurface.minimumTextOpacity)
                            )
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(EdgeInsets(top: 12, leading: 15, bottom: 12, trailing: 15))
                    .background(FathomSurface.card)
                    .overlay {
                        Rectangle().stroke(.white.opacity(0.14), lineWidth: 1)
                    }

                    if index < steps.count - 1 {
                        Image(systemName: "arrow.right")
                            .font(.fathomSystem(12))
                            .foregroundStyle(
                                .white.opacity(FathomSurface.minimumTextOpacity)
                            )
                            .accessibilityHidden(true)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(step.label), \(step.value), \(step.detail)")
            }
        }
    }
}

/// Every section, one number each — the Home grid.
///
/// Shares the readout grid's hairline construction, at a smaller size, because
/// these are readouts that happen to be links.
struct FathomSectionGrid: View {
    struct Entry: Identifiable {
        let id = UUID()
        let section: AppSection
        let value: String
        let detail: String
    }

    let entries: [Entry]
    let open: (AppSection) -> Void

    var body: some View {
        LazyVGrid(
            // "1,023.4 GB" at fathomDisplay(21) x 1.45 = 30.45pt measures
            // 174.1pt and needs 204.1 of track with the 15pt paddings; 178
            // gave it 148.
            columns: [
                GridItem(.adaptive(minimum: 178 * FathomType.scale), spacing: 1),
            ],
            spacing: 1
        ) {
            ForEach(entries) { entry in
                Button {
                    open(entry.section)
                } label: {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(entry.section.rawValue.uppercased())
                            .font(.fathomSystem(9, weight: .semibold))
                            .tracking(1.26)
                            .foregroundStyle(
                                .white.opacity(FathomSurface.minimumTextOpacity)
                            )
                        Text(entry.value)
                            .font(.fathomDisplay(21))
                            .tracking(-0.42)
                            .padding(.top, 7)
                        Text(entry.detail)
                            .font(.fathomSystem(11))
                            .foregroundStyle(
                                .white.opacity(FathomSurface.minimumTextOpacity)
                            )
                            .padding(.top, 3)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(EdgeInsets(top: 13, leading: 15, bottom: 13, trailing: 15))
                    .background(FathomSurface.card)
                    .overlay {
                        Rectangle().stroke(.white.opacity(0.14), lineWidth: 1)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .fathomFocusRing(cornerRadius: 0)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(
                    "\(entry.section.rawValue), \(entry.value), \(entry.detail)"
                )
                .accessibilityHint("Opens \(entry.section.rawValue)")
            }
        }
    }
}
