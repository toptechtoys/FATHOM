import FathomKit
import SwiftUI

struct AttributionView: View {
    @EnvironmentObject private var model: AttributionAppModel
    @AppStorage(AttributionAppModel.enabledKey) private var enabled = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                FathomSectionHeader(
                    title: "Attribution",
                    subtitle: subtitle,
                    isLive: enabled
                )

                FathomReadoutGrid {
                    FathomMeasurementReadout(
                        label: "Written today",
                        measurement: FathomKit.Measurement<String>.notPublished(
                            reason: "Two completed scans must bracket a persisted FSEvents causal window before bytes can be attributed to a process."
                        ),
                        note: "Traced to who wrote it",
                        format: { $0 }
                    )
                    FathomMeasurementReadout(
                        label: "Collection",
                        measurement: FathomKit.Measurement<String>.known(
                            enabled ? "On" : "Off",
                            source: .fseventsCausalWindow
                        ),
                        note: enabled
                            ? "Curated paths, durable event IDs"
                            : "No background path history is retained",
                        format: { $0 }
                    )
                }
                .padding(.bottom, 22)

                FathomPanel(label: "Causal window") {
                    VStack(alignment: .leading, spacing: 14) {
                        FathomPanelUnavailable(reason: statusReason)

                        Toggle("Collect the causal window", isOn: Binding(
                            get: { enabled },
                            set: {
                                enabled = $0
                                model.setEnabled($0)
                            }
                        ))
                        .toggleStyle(.switch)
                        .font(.fathomSystem(13))
                    }
                }

                FathomNote(
                    headline: "The unattributed row is the honest one.",
                    detail: "Whatever we cannot trace to a process gets its own line rather than being distributed across the rows above to make the percentages total 100. Event paths alone are not process attribution, and we will not present them as though they were."
                )
            }
            .padding(EdgeInsets(top: 22, leading: 28, bottom: 40, trailing: 28))
        }
    }

    private var subtitle: String {
        enabled ? "Recording · nothing attributed yet" : "Collection is off"
    }

    private var statusReason: String {
        switch model.state {
        case .disabled:
            "Collection is off. No background path history is retained."
        case .collecting:
            "Collecting curated-path FSEvents with durable event IDs. Attribution needs two completed scans to bracket the window."
        case let .recomputeRequired(reason):
            "Recomputing from a complete scan — \(reason)"
        case let .failed(reason):
            reason
        }
    }
}
