import FathomKit
import SwiftUI

struct TimelineView: View {
    @EnvironmentObject private var storage: StorageAppModel
    @EnvironmentObject private var history: HistoryAppModel
    @EnvironmentObject private var machine: MachineIdentityAppModel
    @State private var comparisonStartID = ""
    @State private var comparisonEndID = ""

    var body: some View {
        Group {
            switch storage.state {
            case .idle:
                FathomEmptySection(
                    title: "Timeline",
                    subtitle: "No history recorded",
                    headline: "There is no history to draw.",
                    detail: "The first column appears after the first completed scan, and change is not published until a second observation exists. Where the Mac was asleep the chart draws the absence rather than smoothing over it — a chart that hides its own blind spots is worse than no chart.",
                    actionTitle: "Run the first Deep Scan",
                    actionCost: "Reads every volume once. Changes nothing.",
                    action: storage.scanSelectedVolume
                )
            case .scanning:
                FathomEmptySection(
                    title: "Timeline",
                    subtitle: "Recording",
                    headline: "Recording a completed scan.",
                    detail: storage.scanProgressMessage,
                    actionTitle: "Scanning…",
                    isBusy: true,
                    action: {}
                )
            case let .failed(reason):
                FathomEmptySection(
                    title: "Timeline",
                    subtitle: "The pass did not complete",
                    headline: "There is no history to draw.",
                    detail: reason,
                    actionTitle: "Try again",
                    action: storage.reset
                )
            case let .result(presentation):
                historyContent(presentation)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func historyContent(_ presentation: StoragePresentation) -> some View {
        switch history.state {
        case .idle:
            ProgressView().onAppear { history.load(from: presentation) }
        case .loading:
            ProgressView("Reading persisted scan history…")
        case let .failed(reason):
            FathomEmptySection(
                title: "Timeline",
                subtitle: "History could not be read",
                headline: "There is no history to draw.",
                detail: reason
            )
        case let .result(samples, _):
            content(samples)
        }
    }

    private func content(_ samples: [StorageHistorySample]) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                FathomSectionHeader(
                    title: "Timeline",
                    subtitle: "\(samples.count) observation\(samples.count == 1 ? "" : "s") recorded",
                    isLive: false
                )

                FathomReadoutGrid {
                    FathomMeasurementReadout(
                        label: "Observations",
                        measurement: FathomKit.Measurement<Int>.known(
                            samples.count,
                            source: .fts
                        ),
                        note: samples.count < 2
                            ? "Change is not published until a second one exists"
                            : "Each one a completed scan",
                        format: { $0.formatted() }
                    )
                    FathomMeasurementReadout(
                        label: "Recording since",
                        measurement: firstDate(samples),
                        note: "The day this history begins",
                        format: { $0 }
                    )
                    FathomMeasurementReadout(
                        label: "Net change",
                        measurement: netChange(samples),
                        note: "Across the whole recorded window",
                        format: signedBytes
                    )
                }
                .padding(.bottom, 22)

                if samples.count >= 2 {
                    FathomPanel(label: "Observed change, oldest to newest") {
                        FathomDayColumns(
                            days: days(samples),
                            format: { signedBytes(Int64($0)) }
                        )
                    }

                    FathomPanel(label: "Compare any two observations") {
                        comparison(samples)
                    }
                }

                FathomPanel(label: "Every observation") {
                    observations(samples)
                }

                FathomNote(
                    headline: "It admits its gaps.",
                    detail: "A period the Mac spent asleep is marked as a gap and never interpolated across. The record starts the day FATHOM was installed, and days before that are drawn empty rather than smoothed over."
                )
            }
            .padding(EdgeInsets(top: 22, leading: 28, bottom: 40, trailing: 28))
            .onAppear {
                if comparisonStartID.isEmpty {
                    comparisonStartID = samples.first?.id ?? ""
                }
                if comparisonEndID.isEmpty {
                    comparisonEndID = samples.last?.id ?? ""
                }
                machine.daysRecorded = daysRecorded(samples)
            }
        }
    }

    /// One column per consecutive pair, growth up and deletion down.
    ///
    /// A pair separated by a sleep gap gets a column with no bars: the change
    /// across an interval nobody observed is not zero, it is unknown, and
    /// drawing it as zero would be the interpolation this section refuses.
    private func days(_ samples: [StorageHistorySample]) -> [FathomDayColumns.Day] {
        zip(samples, samples.dropFirst()).map { previous, current in
            let label = current.wallTimestamp.formatted(
                .dateTime.weekday(.abbreviated)
            )
            guard StorageHistoryClock.gap(from: previous, to: current) == nil,
                  case let .known(before, _) = previous.actuallyFree,
                  case let .known(after, _) = current.actuallyFree
            else {
                return FathomDayColumns.Day(
                    label: label,
                    written: nil,
                    deleted: nil
                )
            }
            // Free space falling means the volume grew.
            let grew = before > after ? Double(before - after) : 0
            let shrank = after > before ? Double(after - before) : 0
            return FathomDayColumns.Day(
                label: label,
                written: grew,
                deleted: shrank
            )
        }
    }

    @ViewBuilder
    private func comparison(_ samples: [StorageHistorySample]) -> some View {
        let start = samples.first { $0.id == comparisonStartID }
        let end = samples.first { $0.id == comparisonEndID }
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 16) {
                Picker("From", selection: $comparisonStartID) {
                    ForEach(samples) { sample in
                        Text(historyDate(sample.wallTimestamp)).tag(sample.id)
                    }
                }
                Picker("To", selection: $comparisonEndID) {
                    ForEach(samples) { sample in
                        Text(historyDate(sample.wallTimestamp)).tag(sample.id)
                    }
                }
            }
            .font(.fathomSystem(12))

            if let start, let end {
                let delta = StorageHistoryComparison.compare(from: start, to: end)
                VStack(spacing: 3) {
                    deltaRow("Actually free", delta.actuallyFree)
                    deltaRow("On disk", delta.sizeOnDisk)
                    deltaRow("Freed if deleted", delta.freedIfDeleted)
                    deltaRow("Purgeable", delta.purgeable)
                }
                topLevel(delta.topLevel)
            } else {
                FathomPanelUnavailable(
                    reason: "Choose two persisted observations to compare."
                )
            }
        }
    }

    @ViewBuilder
    private func topLevel(
        _ measurement: FathomKit.Measurement<[StorageHistoryNodeDelta]>
    ) -> some View {
        if case let .known(nodes, _) = measurement, !nodes.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                Text("TOP-LEVEL CHANGE")
                    .font(.fathomSystem(9, weight: .semibold))
                    .tracking(1.26)
                    .foregroundStyle(
                        .white.opacity(FathomSurface.minimumTextOpacity)
                    )
                    .padding(.top, 10)
                ForEach(nodes, id: \.path) { node in
                    FathomDataRow.simple(
                        node.name,
                        value: deltaText(node.sizeOnDisk),
                        valueColor: color(for: node.sizeOnDisk),
                        annotation: node.path,
                        isPath: false
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func observations(_ samples: [StorageHistorySample]) -> some View {
        let ordered = Array(samples.reversed())
        VStack(spacing: 3) {
            ForEach(Array(ordered.enumerated()), id: \.element.id) { index, sample in
                FathomDataRow.simple(
                    sample.wallTimestamp.formatted(
                        date: .abbreviated,
                        time: .shortened
                    ),
                    value: value(sample.actuallyFree),
                    annotation: "actually free · "
                        + value(sample.freedIfDeleted) + " freeable"
                )
                if index + 1 < ordered.count,
                   let gap = StorageHistoryClock.gap(
                       from: ordered[index + 1],
                       to: sample
                   ) {
                    FathomDataRow.simple(
                        "Sleep gap",
                        value: durationString(gap.duration),
                        valueColor: .white.opacity(
                            FathomSurface.minimumTextOpacity
                        ),
                        annotation: "No values were interpolated across it",
                        isEmphasised: true
                    )
                }
            }
        }
    }

    private func deltaRow(
        _ label: String,
        _ delta: FathomKit.Measurement<Int64>
    ) -> some View {
        FathomDataRow.simple(
            label,
            value: deltaText(delta),
            valueColor: color(for: delta)
        )
    }

    private func deltaText(_ delta: FathomKit.Measurement<Int64>) -> String {
        // `described` keeps the third state distinct: a partly-attributed
        // delta used to render exactly like a known one, a hard number in
        // the colour reserved for absent readings.
        delta.described(signedBytes)
    }

    private func color(for delta: FathomKit.Measurement<Int64>) -> Color {
        guard case let .known(value, _) = delta else {
            return .white.opacity(FathomSurface.minimumTextOpacity)
        }
        // More free space is the outcome the user wanted; less is a fact, not
        // an alarm, so it takes caution rather than blocked.
        return value > 0 ? FathomSemantic.freeable
            : value < 0 ? FathomSemantic.caution : .white
    }

    private func value(_ measurement: FathomKit.Measurement<UInt64>) -> String {
        measurement.described(ByteString.file)
    }

    private func firstDate(
        _ samples: [StorageHistorySample]
    ) -> FathomKit.Measurement<String> {
        guard let first = samples.first else {
            return .notPublished(reason: "No observation has been recorded yet.")
        }
        return .known(
            first.wallTimestamp.formatted(date: .abbreviated, time: .omitted),
            source: .fts
        )
    }

    private func netChange(
        _ samples: [StorageHistorySample]
    ) -> FathomKit.Measurement<Int64> {
        guard let first = samples.first, let last = samples.last,
              samples.count >= 2
        else {
            return .notPublished(
                reason: "Change is not published until a second observation exists."
            )
        }
        return StorageHistoryComparison.compare(from: first, to: last)
            .actuallyFree
    }

    private func daysRecorded(_ samples: [StorageHistorySample]) -> Int? {
        guard let first = samples.first, let last = samples.last else {
            return nil
        }
        let days = Calendar.current.dateComponents(
            [.day],
            from: first.wallTimestamp,
            to: last.wallTimestamp
        ).day
        return days.map { max(0, $0) }
    }

    private func historyDate(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }

    private func signedBytes(_ value: Int64) -> String {
        let magnitude = ByteString.file(UInt64(value.magnitude))
        return value < 0 ? "−\(magnitude)" : "+\(magnitude)"
    }

    private func durationString(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3_600
        let minutes = (Int(seconds) % 3_600) / 60
        return hours > 0 ? "\(hours) h \(minutes) min" : "\(minutes) min"
    }
}
