import FathomKit
import SwiftUI

struct MemoryView: View {
    @EnvironmentObject private var model: SystemMonitorModel

    private let columns = [
        GridItem(.adaptive(minimum: 220), spacing: 14)
    ]

    var body: some View {
        Group {
            switch model.state {
            case .idle, .reading:
                ProgressView("Reading virtual memory counters…")
                    .controlSize(.large)
            case let .result(presentation):
                result(
                    presentation.memory,
                    channelMap: presentation.channelMap
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear(perform: model.start)
        .onDisappear(perform: model.stop)
    }

    private func result(
        _ memory: MemorySnapshot,
        channelMap: FathomKit.Measurement<IOReportChannelMap>
    ) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack {
                    Text("Memory")
                        .font(.fathomDisplay(34))
                        .tracking(-1)
                    Spacer()
                    HardwareMeasurementView(
                        measurement: model.memoryPressure,
                        format: { $0 }
                    )
                }

                LazyVGrid(columns: columns, spacing: 14) {
                    memoryCard("PHYSICAL TOTAL", memory.totalBytes)
                    memoryCard("ACTIVE", memory.activeBytes)
                    memoryCard("INACTIVE", memory.inactiveBytes)
                    memoryCard("WIRED", memory.wiredBytes)
                    memoryCard("COMPRESSED", memory.compressedBytes)
                    memoryCard("FREE", memory.freeBytes)
                    memoryCard("SPECULATIVE", memory.speculativeBytes)
                    memoryCard("PURGEABLE", memory.purgeableBytes)
                    HardwareResultCard(label: "SWAP") {
                        HardwareMeasurementView(
                            measurement: memory.swapUsedBytes,
                            format: hardwareByteString
                        )
                        HStack(spacing: 5) {
                            Text("of")
                            HardwareMeasurementView(
                                measurement: memory.swapTotalBytes,
                                format: hardwareByteString
                            )
                        }
                        .foregroundStyle(.white.opacity(0.82))
                    }
                    HardwareResultCard(label: "MEMORY BANDWIDTH") {
                        Text("not published")
                            .font(.fathomData(16, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.82))
                            .help(privateMetricReason(channelMap))
                            .accessibilityLabel(
                                "Memory bandwidth not published. \(privateMetricReason(channelMap))"
                            )
                    }
                }

                Text(
                    "These are direct Mach VM categories. FATHOM does not rename their sum “app memory” because that headline requires undocumented Activity Monitor accounting."
                )
                .font(.fathomSystem(12.5))
                .foregroundStyle(.white.opacity(0.82))
                .frame(maxWidth: 700, alignment: .leading)
            }
            .padding(34)
        }
    }

    private func privateMetricReason(
        _ map: FathomKit.Measurement<IOReportChannelMap>
    ) -> String {
        switch map {
        case .known:
            return "The signed map does not include verified AMC counter semantics"
        case let .notPublished(reason):
            return reason
        case .notAttributable:
            return "The signed IOReport channel map is not attributable"
        }
    }

    private func memoryCard(
        _ label: String,
        _ measurement: FathomKit.Measurement<UInt64>
    ) -> some View {
        HardwareResultCard(label: label) {
            HardwareMeasurementView(
                measurement: measurement,
                format: hardwareByteString
            )
        }
        .frame(minHeight: 110, alignment: .top)
    }
}
