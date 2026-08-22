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
            VStack(alignment: .leading, spacing: 22) {
                liveHeader("CPU")

                // The first section on the readout grid. The rest of CPU is
                // still on the old cards until the panel types land.
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

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 240), spacing: 18)],
                    spacing: 18
                ) {
                    HardwareResultCard(label: "TOPOLOGY") {
                        topology(cpu)
                    }
                    privateMetric(
                        "CLUSTER FREQUENCY",
                        channelMap: channelMap,
                        knownMapReason: "The signed map does not include verified DVFS frequency tables"
                    )
                }

                coreGrid(cpu.cores)
            }
            .padding(34)
        }
    }

    private func privateMetric(
        _ label: String,
        channelMap: FathomKit.Measurement<IOReportChannelMap>,
        knownMapReason: String
    ) -> some View {
        let reason: String
        switch channelMap {
        case .known:
            reason = knownMapReason
        case let .notPublished(value):
            reason = value
        case .notAttributable:
            reason = "The signed IOReport channel map is not attributable"
        }
        return HardwareResultCard(label: label) {
            Text("not published")
                .font(.fathomData(16, weight: .semibold))
                .foregroundStyle(.white.opacity(0.82))
                .help(reason)
                .accessibilityLabel("\(label) not published. \(reason)")
        }
    }

    /// User / system / idle as one sentence under the total.
    ///
    /// Only the parts macOS actually published are named. A breakdown that
    /// silently drops an unpublished component would read as a complete
    /// account of the total, which it would not be.
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

    private func topology(_ cpu: CPULoadSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HardwareMeasurementView(
                measurement: cpu.performanceLogicalCPUCount,
                format: { "\($0) performance" }
            )
            HardwareMeasurementView(
                measurement: cpu.efficiencyLogicalCPUCount,
                format: { "\($0) efficiency" }
            )
            Text("perflevel0 is performance")
                .font(.fathomSystem(10.5, weight: .semibold))
                .foregroundStyle(.white.opacity(0.82))
        }
    }

    @ViewBuilder
    private func coreGrid(
        _ measurement: FathomKit.Measurement<[CPUCoreLoad]>
    ) -> some View {
        switch measurement {
        case let .known(cores, _):
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 180), spacing: 10)],
                spacing: 10
            ) {
                ForEach(cores) { core in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Core \(core.index + 1)")
                            Spacer()
                            Text(
                                "\((core.busy * 100).formatted(.number.precision(.fractionLength(1))))%"
                            )
                            .monospacedDigit()
                        }
                        .font(.fathomSystem(12, weight: .medium))
                        GeometryReader { geometry in
                            ZStack(alignment: .leading) {
                                Capsule().fill(.white.opacity(0.12))
                                Capsule().fill(.white.opacity(0.74))
                                    .frame(
                                        width: geometry.size.width *
                                            min(max(core.busy, 0), 1)
                                    )
                            }
                        }
                        .frame(height: 7)
                    }
                    .padding(14)
                    .background(FathomSurface.card)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
        case let .notPublished(reason):
            Text("not published")
                .foregroundStyle(.white.opacity(0.82))
                .help(reason)
                .accessibilityLabel("Per-core load not published. \(reason)")
        case .notAttributable:
            Text("not attributable")
        }
    }

    private func liveHeader(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(.fathomDisplay(34))
                .tracking(-1)
            Spacer()
            Text("LIVE")
                .font(.fathomSystem(10, weight: .bold))
                .tracking(1)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(FathomSurface.badge)
                .clipShape(Capsule())
        }
    }
}
