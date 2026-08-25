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
                                .frame(width: 110, alignment: .trailing)
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
                            .frame(width: 150, alignment: .trailing)
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

    private var header: some View {
        HStack(spacing: 0) {
            Text("ITEM")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("ON DISK").frame(width: 110, alignment: .trailing)
            Text("FREED IF DELETED").frame(width: 150, alignment: .trailing)
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
                            .frame(width: 110, alignment: .trailing)
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
        .frame(width: 120, height: 6)
    }

    private func label(for device: Device) -> String {
        guard let level = device.level else {
            return "\(device.name), \(device.unreportedNote)"
        }
        let percent = (level * 100).formatted(.number.precision(.fractionLength(0)))
        return "\(device.name), \(percent)%"
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
                            .frame(width: 110, alignment: .trailing)
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
            columns: [GridItem(.adaptive(minimum: 150), spacing: 10)],
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
            columns: [GridItem(.adaptive(minimum: 178), spacing: 1)],
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
