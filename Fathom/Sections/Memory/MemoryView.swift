import FathomKit
import SwiftUI

struct MemoryView: View {
    @EnvironmentObject private var model: SystemMonitorModel

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
            VStack(alignment: .leading, spacing: 0) {
                FathomSectionHeader(
                    title: "Memory",
                    subtitle: subtitle(memory)
                )

                FathomReadoutGrid {
                    FathomMeasurementReadout(
                        label: "Used",
                        measurement: memory.usedBytes,
                        note: "Active, wired and compressed",
                        format: bytes
                    )
                    FathomMeasurementReadout(
                        label: "Cached",
                        measurement: memory.cachedBytes,
                        note: "Released the moment anything needs it",
                        format: bytes
                    )
                    FathomMeasurementReadout(
                        label: "Pressure",
                        measurement: model.memoryPressure,
                        note: "macOS's word for it, not ours",
                        format: { $0 }
                    )
                    FathomMeasurementReadout(
                        label: "Compressed",
                        measurement: memory.compressedBytes,
                        note: "Held in RAM. Costs CPU, not disk",
                        format: bytes
                    )
                    FathomMeasurementReadout(
                        label: "Swap written",
                        measurement: memory.swapUsedBytes,
                        note: "On disk, and it wears the disk",
                        format: bytes
                    )
                }
                .padding(.bottom, 22)

                FathomPanel(label: "Used, last 60 seconds") {
                    FathomSparkline(
                        history: model.memoryHistory,
                        maximum: 100,
                        accessibilityValue: "Memory in use, percent of physical",
                        spokenFormat: percentSpoken
                    )
                }

                FathomPanel(label: "Composition") {
                    composition(memory)
                }

                FathomPanel(label: "Every category macOS publishes") {
                    VStack(spacing: 3) {
                        categoryRow("Active", memory.activeBytes)
                        categoryRow("Inactive", memory.inactiveBytes)
                        categoryRow("Wired", memory.wiredBytes)
                        categoryRow("Compressed", memory.compressedBytes)
                        categoryRow("Speculative", memory.speculativeBytes)
                        categoryRow("Purgeable", memory.purgeableBytes)
                        categoryRow("Free", memory.freeBytes)
                        categoryRow("Swap used", memory.swapUsedBytes)
                        categoryRow("Swap total", memory.swapTotalBytes)
                        FathomDataRow.simple(
                            "Memory bandwidth",
                            value: "not published",
                            valueColor: .white.opacity(
                                FathomSurface.minimumTextOpacity
                            ),
                            annotation: bandwidthReason(channelMap)
                        )
                    }
                }

                FathomNote(
                    headline: "Pressure and swap answer different questions.",
                    detail: "Pressure asks whether the system is struggling right now. Swap records what it already spent on disk to avoid struggling. Only the second is written to an SSD you cannot replace. These are direct Mach VM categories, and we do not rename their sum “app memory” — that headline needs undocumented Activity Monitor accounting we cannot verify."
                )
            }
            .padding(EdgeInsets(top: 22, leading: 28, bottom: 40, trailing: 28))
        }
    }

    /// The stacked bar names its remainder rather than scaling the rest up to
    /// close the gap. The Mach categories overlap and do not sum to the total,
    /// so the difference is real and gets its own segment.
    @ViewBuilder
    private func composition(_ memory: MemorySnapshot) -> some View {
        if case let .known(total, _) = memory.totalBytes {
            FathomSegmentBar(
                segments: [
                    segment("Active", memory.activeBytes, .white.opacity(0.92)),
                    segment("Wired", memory.wiredBytes, FathomSemantic.caution),
                    segment(
                        "Compressed",
                        memory.compressedBytes,
                        FathomSemantic.blocked
                    ),
                    segment("Free", memory.freeBytes, .white.opacity(0.34)),
                ].compactMap { $0 },
                total: Double(total),
                unaccountedLabel: "Not separately published",
                format: { bytes(UInt64($0)) }
            )
        } else {
            FathomPanelUnavailable(
                reason: "Physical memory total is not published, so the parts cannot be shown as proportions of it."
            )
        }
    }

    private func segment(
        _ label: String,
        _ measurement: FathomKit.Measurement<UInt64>,
        _ color: Color
    ) -> FathomSegmentBar.Segment? {
        guard case let .known(value, _) = measurement else { return nil }
        return FathomSegmentBar.Segment(
            label: label,
            value: Double(value),
            color: color
        )
    }

    private func categoryRow(
        _ label: String,
        _ measurement: FathomKit.Measurement<UInt64>
    ) -> some View {
        switch measurement {
        case let .known(value, source):
            FathomDataRow.simple(
                label,
                value: bytes(value),
                annotation: source.rawValue
            )
        case let .notPublished(reason):
            FathomDataRow.simple(
                label,
                value: "not published",
                valueColor: .white.opacity(FathomSurface.minimumTextOpacity),
                annotation: reason
            )
        case let .notAttributable(measured, explained):
            FathomDataRow.simple(
                label,
                value: bytes(measured),
                valueColor: FathomSemantic.caution,
                annotation: "\(bytes(explained)) explained, the rest is not",
                isEmphasised: true
            )
        }
    }

    private func bytes(_ value: UInt64) -> String {
        ByteString.memory(value)
    }

    private func subtitle(_ memory: MemorySnapshot) -> String {
        guard case let .known(total, _) = memory.totalBytes else {
            return "Sampling 1 Hz while visible"
        }
        return "\(bytes(total)) unified · sampling 1 Hz"
    }

    private func bandwidthReason(
        _ map: FathomKit.Measurement<IOReportChannelMap>
    ) -> String {
        switch map {
        case .known:
            "The signed map does not include verified AMC counter semantics."
        case let .notPublished(reason):
            reason
        case .notAttributable:
            "The signed IOReport channel map is not attributable."
        }
    }
}
