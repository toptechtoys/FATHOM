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
        let id = UUID()
        let name: String
        let onDisk: String
        /// `nil` when deletion would free nothing at all.
        let freed: String?
        var annotation: String?
        var isPath = true

        /// Freeing nothing is not a caution, it is a fact. Only a row that
        /// frees something conditionally earns the caution colour, and the
        /// annotation always says why.
        var freedColor: Color {
            guard freed != nil else {
                return .white.opacity(FathomSurface.minimumTextOpacity)
            }
            return annotation == nil ? FathomSemantic.freeable : FathomSemantic.caution
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
                                Text(row.freed ?? "0")
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
        let freed = row.freed ?? "nothing"
        let base = "\(row.name), \(row.onDisk) on disk, \(freed) freed if deleted"
        return row.annotation.map { "\(base), \($0)" } ?? base
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

/// Include or exclude, one row per rule, recomputing as you go.
///
/// Every rule states its cost before it runs, and nothing here deletes: the
/// panel says so, and the destination is the Trash.
struct FathomRuleRows: View {
    struct Rule: Identifiable {
        let id: String
        let name: String
        let frees: String
        /// What including it costs you. Stated before it runs, never after.
        let cost: String
    }

    let rules: [Rule]
    @Binding var included: Set<String>

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            header
            ForEach(rules) { rule in
                let isIncluded = included.contains(rule.id)
                FathomDataRow(
                    leading: {
                        HStack(spacing: 9) {
                            Image(
                                systemName: isIncluded
                                    ? "checkmark.square.fill"
                                    : "square"
                            )
                            .foregroundStyle(
                                isIncluded
                                    ? FathomSemantic.freeable
                                    : .white.opacity(FathomSurface.minimumTextOpacity)
                            )
                            Text(rule.name).font(.fathomSystem(13))
                        }
                    },
                    trailing: {
                        HStack(spacing: 0) {
                            Text(rule.frees)
                                .font(.fathomSystem(13, weight: .medium))
                                .monospacedDigit()
                                .foregroundStyle(
                                    isIncluded
                                        ? FathomSemantic.freeable
                                        : .white.opacity(
                                            FathomSurface.minimumTextOpacity
                                        )
                                )
                                .frame(width: 110, alignment: .trailing)
                            Text(rule.cost)
                                .font(.fathomSystem(11.5))
                                .foregroundStyle(
                                    .white.opacity(FathomSurface.minimumTextOpacity)
                                )
                                .frame(width: 170, alignment: .trailing)
                        }
                    },
                    isEmphasised: isIncluded,
                    action: { toggle(rule.id) }
                )
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(
                    "\(rule.name), frees \(rule.frees), costs \(rule.cost)"
                )
                .accessibilityValue(isIncluded ? "included" : "not included")
                .accessibilityAddTraits(.isButton)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 0) {
            Text("RULE").frame(maxWidth: .infinity, alignment: .leading)
            Text("FREES").frame(width: 110, alignment: .trailing)
            Text("COST").frame(width: 170, alignment: .trailing)
        }
        .font(.fathomSystem(9, weight: .semibold))
        .tracking(1.26)
        .foregroundStyle(.white.opacity(FathomSurface.minimumTextOpacity))
        .padding(.horizontal, 13)
        .padding(.bottom, 4)
        .accessibilityHidden(true)
    }

    private func toggle(_ id: String) {
        if included.contains(id) {
            included.remove(id)
        } else {
            included.insert(id)
        }
    }
}

/// Things worth a look. Four at most, each one sentence.
///
/// A category dot plus a value; the dot never carries the meaning alone, which
/// is why every item states its finding in words as well.
struct FathomFeed: View {
    struct Item: Identifiable {
        let id = UUID()
        let title: String
        let detail: String
        let value: String
        var tint: Color = FathomSemantic.caution
        var valueColor: Color = .white
        var action: (() -> Void)?
    }

    let items: [Item]

    var body: some View {
        VStack(spacing: 3) {
            ForEach(items) { item in
                FathomDataRow(
                    leading: {
                        HStack(alignment: .top, spacing: 12) {
                            Circle()
                                .fill(item.tint)
                                .frame(width: 8, height: 8)
                                .padding(.top, 5)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.title)
                                    .font(.fathomSystem(13.5, weight: .semibold))
                                Text(item.detail)
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
                        Text(item.value)
                            .font(.fathomData(15, weight: .semibold))
                            .foregroundStyle(item.valueColor)
                            .frame(width: 110, alignment: .trailing)
                    },
                    action: item.action
                )
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(
                    "\(item.title). \(item.detail) \(item.value)"
                )
            }
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
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(
                    "\(entry.section.rawValue), \(entry.value), \(entry.detail)"
                )
                .accessibilityHint("Opens \(entry.section.rawValue)")
            }
        }
    }
}
