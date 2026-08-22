import FathomKit
import SwiftUI

struct GPUView: View {
    @EnvironmentObject private var model: SystemMonitorModel

    var body: some View {
        Group {
            switch model.state {
            case .idle, .reading:
                ProgressView("Reading IOAccelerator counters…")
                    .controlSize(.large)
            case let .result(presentation):
                content(
                    presentation.gpu,
                    channelMap: presentation.channelMap
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear(perform: model.start)
        .onDisappear(perform: model.stop)
    }

    private func content(
        _ gpu: GPUSnapshot,
        channelMap: FathomKit.Measurement<IOReportChannelMap>
    ) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack {
                    Text("GPU")
                        .font(.fathomDisplay(34))
                    Spacer()
                    Text("LIVE")
                        .font(.fathomSystem(10, weight: .bold))
                        .tracking(1)
                }
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 220), spacing: 14)],
                    spacing: 14
                ) {
                    percentCard("DEVICE", gpu.deviceUtilizationPercent, prominent: true)
                    percentCard("RENDERER", gpu.rendererUtilizationPercent)
                    percentCard("TILER", gpu.tilerUtilizationPercent)
                    HardwareResultCard(label: "CORES") {
                        HardwareMeasurementView(
                            measurement: gpu.coreCount,
                            format: hardwareIntegerString
                        )
                    }
                    privateMetric("GPU FREQUENCY", map: channelMap)
                    privateMetric("GPU POWER", map: channelMap)
                    privateMetric("ANE POWER / ACTIVE", map: channelMap)
                    DisplayRefreshCard()
                }
                Text("Values are the exact keys published by IOAccelerator. Missing keys remain not published.")
                    .font(.fathomSystem(12.5))
                    .foregroundStyle(.white.opacity(0.82))
            }
            .padding(34)
        }
    }

    private func privateMetric(
        _ label: String,
        map: FathomKit.Measurement<IOReportChannelMap>
    ) -> some View {
        let reason: String
        switch map {
        case .known:
            reason = "The signed map does not include a verified channel for this metric"
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

    private func percentCard(
        _ label: String,
        _ measurement: FathomKit.Measurement<Double>,
        prominent: Bool = false
    ) -> some View {
        HardwareResultCard(label: label) {
            HardwareMeasurementView(
                measurement: measurement,
                format: { "\($0.formatted(.number.precision(.fractionLength(1))))%" },
                prominent: prominent
            )
        }
    }
}

private struct DisplayRefreshCard: View {
    @State private var measurement:
        FathomKit.Measurement<Double> = .notPublished(
            reason: "Display-link sampling has not started"
        )

    var body: some View {
        HardwareResultCard(label: "DISPLAY CALLBACK RATE") {
            HardwareMeasurementView(
                measurement: measurement,
                format: {
                    "\($0.formatted(.number.precision(.fractionLength(1)))) Hz"
                }
            )
            Text("Compositor callback rate, not app-rendered FPS")
                .font(.fathomSystem(9.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.82))
        }
        .task {
            let sampler: DisplayRefreshSampler
            do {
                sampler = try DisplayRefreshSampler()
            } catch {
                measurement = .notPublished(
                    reason: "CVDisplayLink is unavailable: \(error)"
                )
                return
            }
            _ = await sampler.sample()
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(1))
                } catch {
                    return
                }
                measurement = await sampler.sample()
            }
        }
    }
}
