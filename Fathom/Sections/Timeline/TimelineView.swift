import FathomKit
import SwiftUI

struct TimelineView: View {
    @EnvironmentObject private var storage: StorageAppModel
    @EnvironmentObject private var history: HistoryAppModel
    @State private var comparisonStartID = ""
    @State private var comparisonEndID = ""

    var body: some View {
        Group {
            switch storage.state {
            case .idle:
                FathomPoster(
                    title: "Timeline",
                    message: "What changed between completed scans, with sleep gaps left as gaps.",
                    symbol: "clock",
                    world: .timeline,
                    shape: AnyShape(Circle()),
                    isScanning: false,
                    action: storage.scanSelectedVolume
                )
            case .scanning:
                ProgressView("Recording a completed scan…")
            case let .failed(reason):
                Text("not published — \(reason)")
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
            Text(reason)
        case let .result(samples, _):
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Timeline").font(.fathomDisplay(34))
                    if samples.count < 2 {
                        Text("One completed scan exists. Change is not published until a second observation.")
                            .foregroundStyle(.white.opacity(0.82))
                    }
                    if samples.count >= 2 {
                        comparison(samples)
                    }
                    let ordered = Array(samples.reversed())
                    ForEach(Array(ordered.enumerated()), id: \.element.id) { index, sample in
                        VStack(spacing: 14) {
                            HardwareResultCard(
                                label: sample.wallTimestamp.formatted(
                                    date: .abbreviated,
                                    time: .shortened
                                )
                            ) {
                                LazyVGrid(
                                    columns: [GridItem(.adaptive(minimum: 125), spacing: 18)],
                                    alignment: .leading,
                                    spacing: 12
                                ) {
                                    metric("ACTUALLY FREE", sample.actuallyFree)
                                    metric("ON DISK", sample.sizeOnDisk)
                                    metric("FREEABLE", sample.freedIfDeleted)
                                    metric("PURGEABLE", sample.purgeable)
                                }
                            }
                            if index + 1 < ordered.count,
                               let gap = StorageHistoryClock.gap(
                                   from: ordered[index + 1],
                                   to: sample
                               ) {
                                Label(
                                    "Sleep gap · \(durationString(gap.duration)) · no interpolation",
                                    systemImage: "moon.zzz"
                                )
                                .font(.fathomSystem(11, weight: .medium))
                                .foregroundStyle(.white.opacity(0.68))
                                .accessibilityLabel(
                                    "Sleep gap. No values were interpolated."
                                )
                            }
                        }
                    }
                }
                .padding(34)
                .onAppear {
                    if comparisonStartID.isEmpty {
                        comparisonStartID = samples.first?.id ?? ""
                    }
                    if comparisonEndID.isEmpty {
                        comparisonEndID = samples.last?.id ?? ""
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func comparison(_ samples: [StorageHistorySample]) -> some View {
        let start = samples.first { $0.id == comparisonStartID }
        let end = samples.first { $0.id == comparisonEndID }
        HardwareResultCard(label: "COMPARE ANY TWO OBSERVATIONS") {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 250), spacing: 14)],
                alignment: .leading,
                spacing: 12
            ) {
                Picker("From", selection: $comparisonStartID) {
                    ForEach(samples) { sample in
                        Text(historyDate(sample.wallTimestamp))
                            .tag(sample.id)
                    }
                }
                Picker("To", selection: $comparisonEndID) {
                    ForEach(samples) { sample in
                        Text(historyDate(sample.wallTimestamp))
                            .tag(sample.id)
                    }
                }
            }
            if let start, let end {
                let delta = StorageHistoryComparison.compare(
                    from: start,
                    to: end
                )
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 130), spacing: 18)],
                    alignment: .leading,
                    spacing: 12
                ) {
                    deltaMetric("ACTUALLY FREE", delta.actuallyFree)
                    deltaMetric("ON DISK", delta.sizeOnDisk)
                    deltaMetric("FREEABLE", delta.freedIfDeleted)
                    deltaMetric("PURGEABLE", delta.purgeable)
                }
                topLevelDelta(delta.topLevel)
            } else {
                Text("Choose two persisted observations")
                    .foregroundStyle(.white.opacity(0.82))
            }
        }
    }

    @ViewBuilder
    private func topLevelDelta(
        _ measurement:
            FathomKit.Measurement<[StorageHistoryNodeDelta]>
    ) -> some View {
        switch measurement {
        case let .known(rows, source):
            if !rows.isEmpty {
                VStack(alignment: .leading, spacing: 7) {
                    Text("TOP-LEVEL CHANGE")
                        .font(.fathomSystem(9, weight: .bold))
                        .foregroundStyle(.white.opacity(0.72))
                    ForEach(rows) { row in
                        HStack(spacing: 12) {
                            Text(row.name)
                                .font(.fathomPath(11.5))
                                .lineLimit(1)
                            Spacer()
                            HardwareMeasurementView(
                                measurement: row.sizeOnDisk,
                                format: signedBytes
                            )
                            .help("On-disk change · \(source.rawValue)")
                            .accessibilityHint("On-disk change")
                            HardwareMeasurementView(
                                measurement: row.freedIfDeleted,
                                format: signedBytes
                            )
                            .help("Freeable change · \(source.rawValue)")
                            .accessibilityHint("Freeable change")
                        }
                    }
                }
            }
        case let .notPublished(reason):
            Text("Top-level comparison not published")
                .foregroundStyle(.white.opacity(0.82))
                .help(reason)
                .accessibilityLabel(
                    "Top-level comparison not published. \(reason)"
                )
        case .notAttributable:
            Text("Top-level comparison not attributable")
        }
    }

    private func deltaMetric(
        _ label: String,
        _ measurement: FathomKit.Measurement<Int64>
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.fathomSystem(9, weight: .bold))
            HardwareMeasurementView(
                measurement: measurement,
                format: signedBytes
            )
        }
    }

    private func signedBytes(_ value: Int64) -> String {
        let magnitude = value.magnitude.formatted(.byteCount(style: .file))
        if value > 0 { return "+\(magnitude)" }
        if value < 0 { return "−\(magnitude)" }
        return magnitude
    }

    private func historyDate(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }

    private func metric(
        _ label: String,
        _ value: FathomKit.Measurement<UInt64>
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.fathomSystem(9, weight: .bold))
            HardwareMeasurementView(measurement: value, format: hardwareByteString)
        }
    }

    private func durationString(_ seconds: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.day, .hour, .minute]
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 2
        return formatter.string(from: seconds) ?? "less than one minute"
    }
}
