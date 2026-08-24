import FathomKit
import SwiftUI

/// Sixty seconds of one value, at 1 Hz.
///
/// The line breaks wherever the history has a gap. `SampleHistory` keeps
/// unpublished intervals rather than dropping them, and drawing straight
/// through would invent a reading; leaping across without breaking would
/// misdate every sample after it.
///
/// The area fill is drawn per run for the same reason, so nothing is shaded
/// under a second the app never measured.
struct FathomSparkline: View {
    /// Grows with the text size. A reader who enlarged the type wants the
    /// chart bigger too, not a bigger caption over the same 52pt of line.
    @ScaledMetric(relativeTo: .caption) private var height: CGFloat = 52
    let history: SampleHistory<Double>
    /// The ceiling. `nil` scales to the window's own peak, for values like
    /// throughput that have no fixed maximum.
    var maximum: Double?
    var accessibilityValue: String

    var body: some View {
        Group {
            if history.isEmpty {
                placeholder("Sampling starts when this section opens.")
            } else if history.isEntirelyGaps {
                placeholder("Nothing was published in the last minute.")
            } else {
                chart
            }
        }
        .frame(height: height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
    }

    private var chart: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let ceiling = resolvedCeiling
            let step = history.capacity > 1
                ? size.width / Double(history.capacity - 1)
                : size.width

            ZStack {
                ForEach(Array(history.runs.enumerated()), id: \.offset) { _, run in
                    let points = run.values.enumerated().map { offset, value in
                        CGPoint(
                            x: Double(run.start + offset) * step,
                            y: size.height
                                - min(1, max(0, value / ceiling)) * size.height
                        )
                    }
                    // A single sample cannot be a line; draw it as a tick so a
                    // one-second island is still visible.
                    if points.count == 1 {
                        Path { $0.addEllipse(in: CGRect(
                            x: points[0].x - 1.25, y: points[0].y - 1.25,
                            width: 2.5, height: 2.5
                        )) }
                        .fill(.white.opacity(0.92))
                    } else {
                        Path { path in
                            path.move(to: CGPoint(x: points[0].x, y: size.height))
                            path.addLines(points)
                            path.addLine(
                                to: CGPoint(
                                    x: points[points.count - 1].x,
                                    y: size.height
                                )
                            )
                            path.closeSubpath()
                        }
                        .fill(.white.opacity(0.13))

                        Path { $0.addLines(points) }
                            .stroke(
                                .white.opacity(0.92),
                                style: StrokeStyle(
                                    lineWidth: 2.5,
                                    lineCap: .round,
                                    lineJoin: .round
                                )
                            )
                    }
                }
            }
        }
    }

    private func placeholder(_ text: String) -> some View {
        Text(text)
            .font(.fathomSystem(11.5))
            .foregroundStyle(.white.opacity(FathomSurface.minimumTextOpacity))
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Never zero: dividing by a peak of nothing would put every point at the
    /// top of the chart.
    private var resolvedCeiling: Double {
        if let maximum, maximum > 0 { return maximum }
        if let peak = history.peak, peak > 0 { return peak }
        return 1
    }

    /// VoiceOver gets the shape stated, because a sparkline carries meaning no
    /// label otherwise gives it — including how much of the minute is missing.
    private var label: String {
        if history.isEmpty {
            return "\(accessibilityValue). Sampling has not started."
        }
        if history.isEntirelyGaps {
            return "\(accessibilityValue). Nothing published in the last minute."
        }
        let values = history.samples.compactMap { $0 }
        let low = values.min() ?? 0
        let high = values.max() ?? 0
        let latest = history.latest ?? 0
        let shape = "\(accessibilityValue) over the last minute. "
            + "Now \(format(latest)), low \(format(low)), high \(format(high))."
        guard history.gapCount > 0 else { return shape }
        return shape + " \(history.gapCount) second"
            + (history.gapCount == 1 ? "" : "s")
            + " not published, drawn as gaps."
    }

    private func format(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(value < 10 ? 1 : 0)))
    }
}

/// Load per core, one bar each.
///
/// Performance cores read at 92% white and efficiency cores at 50%, and the
/// label under each states which cluster it belongs to, so the distinction
/// never rests on brightness alone.
///
/// `perflevel0` is the performance cluster. `AGENTS.md` names getting this
/// backwards as the most common bug in Mac monitoring code, and it was in the
/// prototype once.
struct FathomCoreBars: View {
    @ScaledMetric(relativeTo: .caption) private var height: CGFloat = 110
    let cores: FathomKit.Measurement<[CPUCoreLoad]>
    let performanceCount: FathomKit.Measurement<UInt64>
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        switch cores {
        case let .known(loads, source):
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(loads) { core in
                    bar(core, isPerformance: isPerformance(core.index))
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(summary(loads, source: source))
        case let .notPublished(reason):
            FathomPanelUnavailable(reason: reason)
        case .notAttributable:
            FathomPanelUnavailable(
                reason: "The per-core split cannot be attributed on this Mac.",
                isAttributionGap: true
            )
        }
    }

    private func bar(_ core: CPUCoreLoad, isPerformance: Bool) -> some View {
        VStack(spacing: 6) {
            GeometryReader { geometry in
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    Rectangle()
                        .fill(.white.opacity(isPerformance ? 0.92 : 0.5))
                        .frame(
                            height: max(
                                1,
                                geometry.size.height * min(max(core.busy, 0), 1)
                            )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 2))
                }
            }
            // The height belongs to the chart, not to the chart plus its
            // label. Wrapping both meant a label growing under Dynamic Type
            // ate the bar it was labelling.
            .frame(height: height)
            .animation(reduceMotion ? nil : .fathomCoreBar, value: core.busy)

            Text(label(for: core.index, isPerformance: isPerformance))
                .font(.fathomSystem(9, weight: .semibold))
                .tracking(0.72)
                .foregroundStyle(.white.opacity(FathomSurface.minimumTextOpacity))
        }
    }

    /// The cluster split, or `nil` when the two readings do not permit one.
    ///
    /// The arithmetic lives in `CoreClusterSplit` in FathomKit, where it is
    /// tested against the reference machine. Labelling a core with the wrong
    /// cluster is a claim about the hardware, and this project has already got
    /// that backwards once.
    private var split: CoreClusterSplit? {
        guard case let .known(performance, _) = performanceCount,
              case let .known(loads, _) = cores else { return nil }
        return CoreClusterSplit(total: loads.count, performance: Int(performance))
    }

    private func isPerformance(_ index: Int) -> Bool {
        split?.isPerformance(index: index) ?? false
    }

    /// Falls back to a bare index rather than a guessed cluster: an unlabelled
    /// bar is honest, and a mislabelled one is not.
    private func label(for index: Int, isPerformance: Bool) -> String {
        split?.label(index: index) ?? "\(index + 1)"
    }

    private func summary(_ loads: [CPUCoreLoad], source: DataSource) -> String {
        let parts = loads.map { core in
            let percent = (core.busy * 100)
                .formatted(.number.precision(.fractionLength(0)))
            return "\(label(for: core.index, isPerformance: isPerformance(core.index))) \(percent)%"
        }
        return "Load per core: " + parts.joined(separator: ", ")
            + ". Source \(source.rawValue)."
    }
}

/// A stacked proportional bar with a legend that names every segment.
///
/// The legend is not optional and neither is the remainder: a bar whose parts
/// do not reach the whole gets an *unaccounted* segment rather than having its
/// other segments scaled up to close the gap.
struct FathomSegmentBar: View {
    struct Segment: Identifiable {
        let id = UUID()
        let label: String
        let value: Double
        let color: Color
    }

    @ScaledMetric(relativeTo: .caption) private var height: CGFloat = 34
    let segments: [Segment]
    /// The whole the segments are parts of. When the parts fall short, the
    /// difference is drawn and named rather than absorbed.
    let total: Double
    var unaccountedLabel = "Unaccounted"
    let format: (Double) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            GeometryReader { geometry in
                HStack(spacing: 0) {
                    ForEach(resolved) { segment in
                        Rectangle()
                            .fill(segment.color)
                            .frame(
                                width: geometry.size.width
                                    * (total > 0 ? segment.value / total : 0)
                            )
                    }
                }
            }
            .frame(height: height)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            FlowLegend(items: resolved, format: format)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            resolved.map { "\($0.label) \(format($0.value))" }
                .joined(separator: ", ")
        )
    }

    private var resolved: [Segment] {
        let accounted = segments.reduce(0) { $0 + $1.value }
        let remainder = total - accounted
        guard remainder > total * 0.001 else { return segments }
        return segments + [
            Segment(
                label: unaccountedLabel,
                value: remainder,
                color: .white.opacity(0.22)
            ),
        ]
    }
}

/// The legend under a segment bar. Every segment is named, including the
/// remainder.
///
/// This used to be a `LazyVGrid` of `.adaptive(minimum: 150)` columns, which
/// clamped each item to a 150pt track however much room the panel had. The
/// Memory section's longest label came out as *Not separately publishe…* on a
/// 1,330pt-wide panel — a legend that truncates the name of the thing it
/// exists to name, and in this case truncated the word *published*, which is
/// the one word on that screen that carries the product's argument.
///
/// The prototype's `.leg` is `display:flex; flex-wrap:wrap; gap:8px 18px`:
/// items take their own width and wrap when they run out. That is what this
/// draws.
private struct FlowLegend: View {
    let items: [FathomSegmentBar.Segment]
    let format: (Double) -> String

    var body: some View {
        FathomWrappingRow {
            ForEach(items) { item in
                HStack(spacing: 7) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(item.color)
                        .frame(width: 9, height: 9)
                    Text("\(item.label) \(format(item.value))")
                        .font(.fathomSystem(11.5))
                        .foregroundStyle(
                            .white.opacity(FathomSurface.minimumTextOpacity)
                        )
                        .fixedSize(horizontal: true, vertical: false)
                }
            }
        }
    }
}

/// `display: flex; flex-wrap: wrap`, which SwiftUI has no container for.
///
/// Each item is measured at the width it actually wants and placed along the
/// row until the next one will not fit; then the row breaks. An item wider
/// than the whole container is offered the container's width and allowed to
/// wrap or truncate on its own terms — that is the only case where anything
/// here shortens a label.
struct FathomWrappingRow: Layout {
    /// The prototype's `gap: 8px 18px` — row gap and column gap.
    var horizontalSpacing: CGFloat = 18
    var verticalSpacing: CGFloat = 8

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let available = usableWidth(proposal, subviews: subviews)
        let (rows, _) = arrange(width: available, subviews: subviews)
        let height = rows.reduce(0) { $0 + $1.height }
            + verticalSpacing * CGFloat(max(0, rows.count - 1))
        let widest = rows.map(\.width).max() ?? 0
        return CGSize(width: min(available, max(widest, 0)), height: height)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        let (rows, sizes) = arrange(width: bounds.width, subviews: subviews)
        var y = bounds.minY
        for row in rows {
            var x = bounds.minX
            for index in row.indices {
                subviews[index].place(
                    at: CGPoint(x: x, y: y),
                    proposal: ProposedViewSize(sizes[index])
                )
                x += sizes[index].width + horizontalSpacing
            }
            y += row.height + verticalSpacing
        }
    }

    /// A nil or infinite proposal means "how wide would you like to be", and
    /// the honest answer for a flow row is one line of everything.
    private func usableWidth(
        _ proposal: ProposedViewSize,
        subviews: Subviews
    ) -> CGFloat {
        if let width = proposal.width, width.isFinite, width > 0 { return width }
        let natural = subviews.reduce(CGFloat(0)) {
            $0 + $1.sizeThatFits(.unspecified).width
        }
        return natural + horizontalSpacing * CGFloat(max(0, subviews.count - 1))
    }

    private func arrange(
        width: CGFloat,
        subviews: Subviews
    ) -> ([Row], [CGSize]) {
        let sizes = subviews.map { subview -> CGSize in
            let ideal = subview.sizeThatFits(.unspecified)
            guard width.isFinite, ideal.width > width else { return ideal }
            // Wider than everything: let it decide how to shorten itself.
            return subview.sizeThatFits(
                ProposedViewSize(width: width, height: nil)
            )
        }
        var rows: [Row] = []
        var current = Row()
        for (index, size) in sizes.enumerated() {
            let extended = current.indices.isEmpty
                ? size.width
                : current.width + horizontalSpacing + size.width
            if !current.indices.isEmpty, extended > width {
                rows.append(current)
                current = Row(indices: [index], width: size.width, height: size.height)
            } else {
                current.indices.append(index)
                current.width = extended
                current.height = max(current.height, size.height)
            }
        }
        if !current.indices.isEmpty { rows.append(current) }
        return (rows, sizes)
    }
}

/// Seven days, growth above a shared baseline and deletion below it.
///
/// A day the app was not running is drawn as an empty column rather than
/// skipped, so the week keeps its shape and the blind spot stays visible.
struct FathomDayColumns: View {
    struct Day: Identifiable {
        let id = UUID()
        let label: String
        /// `nil` for a day with no record at all.
        let written: Double?
        let deleted: Double?

        var net: Double? {
            guard let written, let deleted else { return nil }
            return written - deleted
        }
    }

    @ScaledMetric(relativeTo: .caption) private var height: CGFloat = 140
    let days: [Day]
    let format: (Double) -> String

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            ForEach(days) { day in
                column(day)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(summary)
    }

    private var peak: Double {
        let all = days.flatMap { [$0.written, $0.deleted].compactMap { $0 } }
        return max(all.max() ?? 1, 0.0001)
    }

    private func column(_ day: Day) -> some View {
        VStack(spacing: 4) {
            // Fixed for the bars only; the two label rows below grow with the
            // text size rather than squeezing the chart.
            GeometryReader { geometry in
                let half = geometry.size.height / 2
                VStack(spacing: 0) {
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        if let written = day.written {
                            Rectangle()
                                .fill(.white.opacity(0.78))
                                .frame(height: half * min(1, written / peak))
                        }
                    }
                    .frame(height: half)

                    Rectangle()
                        .fill(.white.opacity(0.16))
                        .frame(height: 1)

                    VStack(spacing: 0) {
                        if let deleted = day.deleted {
                            Rectangle()
                                .fill(.white.opacity(0.34))
                                .frame(height: half * min(1, deleted / peak))
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(height: half)
                }
            }

            .frame(height: height)

            Text(day.net.map { format($0) } ?? "—")
                .font(.fathomSystem(10.5))
                .monospacedDigit()
                .foregroundStyle(
                    day.net == nil
                        ? .white.opacity(FathomSurface.minimumTextOpacity)
                        : .white
                )
            Text(day.label)
                .font(.fathomSystem(10))
                .foregroundStyle(.white.opacity(FathomSurface.minimumTextOpacity))
        }
    }

    private var summary: String {
        let described = days.map { day -> String in
            guard let net = day.net else {
                return "\(day.label), no record"
            }
            return "\(day.label), net \(format(net))"
        }
        return "Last seven days. " + described.joined(separator: ". ")
    }
}
