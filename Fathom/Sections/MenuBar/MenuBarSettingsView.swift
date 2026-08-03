import FathomKit
import SwiftUI

struct MenuBarSettingsView: View {
    private static let defaults = UserDefaults(
        suiteName: FathomBarConfiguration.suiteName
    ) ?? .standard

    @AppStorage(
        FathomBarConfiguration.freeSpaceKey,
        store: defaults
    ) private var freeSpace = true
    @AppStorage(
        FathomBarConfiguration.hottestSensorKey,
        store: defaults
    ) private var hottestSensor = true
    @AppStorage(
        FathomBarConfiguration.networkThroughputKey,
        store: defaults
    ) private var networkThroughput = true
    @AppStorage(
        FathomBarConfiguration.cpuLoadKey,
        store: defaults
    ) private var cpuLoad = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack {
                    Text("Menu Bar")
                        .font(.fathomDisplay(34))
                    Spacer()
                    Text("MENU BAR PREVIEW")
                        .font(.fathomSystem(10, weight: .bold))
                        .tracking(1)
                        .foregroundStyle(.white.opacity(0.82))
                }

                preview

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 290), spacing: 12)],
                    spacing: 12
                ) {
                    setting("Free space", "The important-usage capacity", $freeSpace)
                    setting("Hottest sensor", "Only across published sensors", $hottestSensor)
                    setting("Network throughput", "Download total across active interfaces", $networkThroughput)
                    setting("CPU load", "Total across published processor ticks", $cpuLoad)
                }

                HardwareResultCard(label: "MEASURED COST OF THESE FOUR ITEMS") {
                    Text("not published")
                        .font(.fathomData(17, weight: .medium))
                        .foregroundStyle(.white.opacity(0.82))
                    Text("Requires the Apple-silicon release measurement. The 0.2% / 2.1 budget is not displayed as an observation.")
                        .font(.fathomSystem(11.5))
                        .foregroundStyle(.white.opacity(0.82))
                }

                Text("Sampling is coalesced to one five-second task and stops on status-window occlusion or system sleep. Tahoe’s menu-bar allow-list has no readable API, so onboarding must still name that limitation.")
                    .font(.fathomSystem(12.5))
                    .foregroundStyle(.white.opacity(0.82))
            }
            .padding(34)
        }
    }

    private var preview: some View {
        HStack(spacing: 14) {
            if freeSpace { previewItem("—", unit: "GB") }
            if hottestSensor { previewItem("—°") }
            if networkThroughput { previewItem("—", unit: "KB/s") }
            if cpuLoad { previewItem("—", unit: "%") }
            Spacer()
            Text("FATHOM")
                .font(.fathomSystem(12, weight: .medium, design: .monospaced))
        }
        .padding(.horizontal, 12)
        .frame(height: 22)
        .foregroundStyle(.black.opacity(0.82))
        .background(.white.opacity(0.88))
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .accessibilityLabel("Menu bar layout preview; values are not published")
    }

    private func previewItem(
        _ value: String,
        unit: String? = nil
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text(value).fontWeight(.semibold)
            if let unit {
                Text(unit).font(.fathomSystem(8, weight: .medium))
            }
        }
        .font(.fathomSystem(11, design: .monospaced))
    }

    private func setting(
        _ title: String,
        _ detail: String,
        _ value: Binding<Bool>
    ) -> some View {
        Toggle(isOn: value) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.fathomSystem(13.5, weight: .semibold))
                Text(detail)
                    .font(.fathomSystem(11.5))
                    .foregroundStyle(.white.opacity(0.82))
            }
        }
        .toggleStyle(.switch)
        .padding(16)
        .background(.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 13))
    }
}
