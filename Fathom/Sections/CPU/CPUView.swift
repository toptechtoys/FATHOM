import FathomKit
import SwiftUI

struct CPUView: View {
    @EnvironmentObject private var model: SystemMonitorModel

    var body: some View {
        Group {
            switch model.state {
            case .idle, .reading:
                ProgressView("Establishing a CPU tick delta…")
                    .controlSize(.large)
            case let .result(presentation):
                result(presentation.cpu, channelMap: presentation.channelMap)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear(perform: model.start)
        .onDisappear(perform: model.stop)
    }

    private func result(
        _ cpu: CPULoadSnapshot,
        channelMap: FathomKit.Measurement<IOReportChannelMap>
    ) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                FathomSectionHeader(
                    title: "CPU",
                    subtitle: subtitle(cpu)
                )

                // The first section built entirely from the Instrument Panel
                // vocabulary: readout grid, sparkline, core bars, note.
                FathomReadoutGrid {
                    FathomMeasurementReadout(
                        label: "Total load",
                        measurement: cpu.aggregateBusy,
                        unit: "%",
                        note: breakdownNote(cpu),
                        format: {
                            ($0 * 100).formatted(.number.precision(.fractionLength(1)))
                        }
                    )
                    FathomMeasurementReadout(
                        label: "Load average",
                        measurement: cpu.loadAverages,
                        note: "1 / 5 / 15 minutes",
                        format: { values in
                            values.map {
                                $0.formatted(.number.precision(.fractionLength(2)))
                            }.joined(separator: " / ")
                        }
                    )
                    FathomMeasurementReadout(
                        label: "P-cluster",
                        measurement: cpu.performanceLogicalCPUCount,
                        unit: "cores",
                        note: "perflevel0 is the performance cluster",
                        format: { $0.formatted() }
                    )
                    FathomMeasurementReadout(
                        label: "E-cluster",
                        measurement: cpu.efficiencyLogicalCPUCount,
                        unit: "cores",
                        note: "Usually carrying most of the load",
                        format: { $0.formatted() }
                    )
                }

                FathomPanel(label: "Total load, last 60 seconds") {
                    FathomSparkline(
                        history: model.cpuHistory,
                        maximum: 100,
                        accessibilityValue: "Total CPU load",
                        spokenFormat: percentSpoken
                    )
                }

                FathomPanel(label: "Load per core") {
                    FathomCoreBars(
                        cores: cpu.cores,
                        performanceCount: cpu.performanceLogicalCPUCount
                    )
                }

                FathomPanel(label: "Cluster frequency") {
                    clusterFrequency(channelMap)
                }

                // The prototype's copy here was demo data that leaked: "We
                // show all eight" on a reference machine with twelve cores,
                // and "the efficiency cores are carrying most of this" as a
                // static claim about live load. The note now states the
                // policy, which is true on every Mac including one that
                // publishes no cluster split at all.
                FathomNote(
                    headline: "An average would hide which cluster is working.",
                    detail: "Every core is shown separately, because the scheduler routes work deliberately: background tasks land on the efficiency cores, and a busy efficiency cluster is macOS doing its job, not a problem."
                )
            }
            .padding(34)
        }
    }

    /// Per-cluster DVFS frequency is not something the signed IOReport channel
    /// map exposes, so the panel says so rather than deriving a plausible
    /// figure from residencies.
    private func clusterFrequency(
        _ channelMap: FathomKit.Measurement<IOReportChannelMap>
    ) -> some View {
        let reason: String
        switch channelMap {
        case .known:
            reason = "The signed map does not include verified DVFS frequency tables."
        case let .notPublished(value):
            reason = value
        case .notAttributable:
            reason = "The signed IOReport channel map is not attributable."
        }
        return FathomPanelUnavailable(reason: reason)
    }

    /// User / system / idle as one sentence under the total.
    ///
    /// Only the parts macOS actually published are named. A breakdown that
    /// silently drops an unpublished component would read as a complete
    /// account of the total, which it would not be.
    private func subtitle(_ cpu: CPULoadSnapshot) -> String {
        guard case let .known(cores, _) = cpu.cores else {
            return "Sampling 1 Hz while visible"
        }
        return "\(cores.count) cores · sampling 1 Hz while visible"
    }

    private func breakdownNote(_ cpu: CPULoadSnapshot) -> String {
        let parts: [(String, FathomKit.Measurement<Double>)] = [
            ("system", cpu.aggregateSystem),
            ("user", cpu.aggregateUser),
            ("idle", cpu.aggregateIdle),
        ]
        let known = parts.compactMap { name, measurement -> String? in
            guard case let .known(value, _) = measurement else { return nil }
            let percent = (value * 100)
                .formatted(.number.precision(.fractionLength(0)))
            return "\(name) \(percent)%"
        }
        if known.isEmpty {
            return "The breakdown is not published on this Mac."
        }
        if known.count < parts.count {
            return known.joined(separator: " · ")
                + " · the rest is not published"
        }
        return known.joined(separator: " · ")
    }



}
