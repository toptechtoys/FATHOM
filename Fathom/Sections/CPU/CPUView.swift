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

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 240), spacing: 18)],
                    spacing: 18
                ) {
                    HardwareResultCard(label: "TOTAL LOAD") {
                        HardwareMeasurementView(
                            measurement: cpu.aggregateBusy,
                            format: {
                                "\(($0 * 100).formatted(.number.precision(.fractionLength(1))))%"
                            },
                            prominent: true
                        )
                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: 68))],
                            alignment: .leading,
                            spacing: 6
                        ) {
                            breakdown("USER", cpu.aggregateUser)
                            breakdown("SYSTEM", cpu.aggregateSystem)
                            breakdown("IDLE", cpu.aggregateIdle)
                        }
                    }
                    HardwareResultCard(label: "TOPOLOGY") {
                        topology(cpu)
                    }
                    HardwareResultCard(label: "LOAD AVERAGE") {
                        HardwareMeasurementView(
                            measurement: cpu.loadAverages,
                            format: { values in
                                values.map {
                                    $0.formatted(
                                        .number.precision(.fractionLength(2))
                                    )
                                }.joined(separator: "  /  ")
                            },
                            prominent: true
                        )
                        Text("1 / 5 / 15 minutes")
                            .font(.fathomSystem(10.5, weight: .medium))
                            .foregroundStyle(.white.opacity(0.72))
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

    private func breakdown(
        _ label: String,
        _ measurement: FathomKit.Measurement<Double>
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.fathomSystem(9, weight: .bold))
                .foregroundStyle(.white.opacity(0.72))
            HardwareMeasurementView(
                measurement: measurement,
                format: {
                    "\(($0 * 100).formatted(.number.precision(.fractionLength(1))))%"
                }
            )
        }
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
