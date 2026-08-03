import SwiftUI

struct AttributionView: View {
    @EnvironmentObject private var model: AttributionAppModel
    @AppStorage(AttributionAppModel.enabledKey) private var enabled = false

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("Attribution").font(.fathomDisplay(34))
            HardwareResultCard(label: "BYTE ATTRIBUTION") {
                Text("not published")
                    .font(.fathomData(18, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.82))
                Text("Two completed scans must bracket a persisted FSEvents causal window. Event paths alone are not process attribution.")
                    .font(.fathomSystem(12))
                    .foregroundStyle(.white.opacity(0.82))
            }
            Toggle("Collect the causal window", isOn: Binding(
                get: { enabled },
                set: {
                    enabled = $0
                    model.setEnabled($0)
                }
            ))
            .toggleStyle(.switch)
            status
            Text("Any remainder will get its own unattributed row. It will never be redistributed to make the percentages total 100%.")
                .font(.fathomSystem(12.5))
                .foregroundStyle(.white.opacity(0.82))
        }
        .frame(maxWidth: 720, alignment: .leading)
        .padding(34)
    }

    @ViewBuilder
    private var status: some View {
        switch model.state {
        case .disabled:
            Text("Collection is off. No background path history is retained.")
        case .collecting:
            Text("Collecting curated-path FSEvents with durable event IDs.")
        case let .recomputeRequired(reason):
            Text("Recomputing from a complete scan — \(reason)")
        case let .failed(reason):
            Text("not published — \(reason)")
        }
    }
}
