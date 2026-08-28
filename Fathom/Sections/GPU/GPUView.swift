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
            VStack(alignment: .leading, spacing: 0) {
                FathomSectionHeader(
                    title: "GPU",
                    subtitle: coreSubtitle(gpu.coreCount)
                )

                FathomReadoutGrid {
                    FathomMeasurementReadout(
                        label: "Utilisation",
                        measurement: gpu.deviceUtilizationPercent,
                        unit: "%",
                        note: "Device total, as IOAccelerator publishes it",
                        format: percent
                    )
                    FathomMeasurementReadout(
                        label: "Renderer",
                        measurement: gpu.rendererUtilizationPercent,
                        unit: "%",
                        note: "The shading half of the pipeline",
                        format: percent
                    )
                    FathomMeasurementReadout(
                        label: "Tiler",
                        measurement: gpu.tilerUtilizationPercent,
                        unit: "%",
                        note: "Geometry binning, before shading",
                        format: percent
                    )
                    FathomMeasurementReadout(
                        label: "Cores",
                        measurement: gpu.coreCount,
                        note: "As the device reports itself",
                        format: { $0.formatted() }
                    )
                }
                .padding(.bottom, 22)

                FathomPanel(label: "Utilisation, last 60 seconds") {
                    FathomSparkline(
                        history: model.gpuHistory,
                        maximum: 100,
                        accessibilityValue: "GPU utilisation",
                        spokenFormat: percentSpoken
                    )
                }

                FathomPanel(label: "Display callback rate") {
                    DisplayRefreshPanel()
                }

                FathomPanel(label: "Frequency, power and Neural Engine") {
                    FathomPanelUnavailable(reason: privateReason(channelMap))
                }

                FathomNote(
                    headline: "The Neural Engine reads nothing almost always.",
                    detail: "It only wakes for Core ML work, so most of the time it is a block of silicon doing nothing. We would report it if the signed IOReport map published a channel we could verify; it does not, so we say so rather than deriving a plausible figure from residencies."
                )
            }
            .padding(EdgeInsets(top: 22, leading: 28, bottom: 40, trailing: 28))
        }
    }

    private func percent(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1)))
    }

    private func coreSubtitle(
        _ cores: FathomKit.Measurement<UInt64>
    ) -> String {
        guard case let .known(count, _) = cores else {
            return "Core count not published · sampling 1 Hz"
        }
        return "\(count) cores · sampling 1 Hz while visible"
    }

    /// Frequency, power and ANE activity share one cause for being absent, so
    /// they share one panel rather than three identical empty cards.
    private func privateReason(
        _ map: FathomKit.Measurement<IOReportChannelMap>
    ) -> String {
        switch map {
        case .known:
            "The signed IOReport map publishes no verified channel for GPU frequency, GPU power or Neural Engine activity on this Mac."
        case let .notPublished(reason):
            reason
        case .notAttributable:
            "The signed IOReport channel map is not attributable."
        }
    }
}

/// Compositor callback rate, sampled independently of the 1 Hz system loop
/// because it comes from a display link rather than a counter read.
private struct DisplayRefreshPanel: View {
    @State private var measurement:
        FathomKit.Measurement<Double> = .notPublished(
            reason: "Display-link sampling has not started"
        )

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            switch measurement {
            case let .known(value, source):
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(value.formatted(.number.precision(.fractionLength(1))))
                        .font(.fathomDisplay(28))
                        .monospacedDigit()
                    Text("Hz")
                        .font(.fathomSystem(13))
                        .foregroundStyle(
                            .white.opacity(FathomSurface.minimumTextOpacity)
                        )
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(
                    "Display callback rate \(value.formatted(.number.precision(.fractionLength(1)))) hertz, source \(source.rawValue)"
                )
                Text("Compositor callback rate, not app-rendered frames")
                    .font(.fathomSystem(11.5))
                    .foregroundStyle(
                        .white.opacity(FathomSurface.minimumTextOpacity)
                    )
            case let .notPublished(reason):
                FathomPanelUnavailable(reason: reason)
            case .notAttributable:
                FathomPanelUnavailable(
                    reason: "The callback rate cannot be attributed to a single display.",
                    isAttributionGap: true
                )
            }
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
