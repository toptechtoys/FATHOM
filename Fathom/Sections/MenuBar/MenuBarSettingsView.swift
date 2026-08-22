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
            VStack(alignment: .leading, spacing: 0) {
                FathomSectionHeader(
                    title: "Menu Bar",
                    subtitle: "\(enabledCount) items · live preview",
                    isLive: false
                )

                FathomReadoutGrid {
                    FathomMeasurementReadout(
                        label: "Cost",
                        measurement: FathomKit.Measurement<String>.notPublished(
                            reason: "Idle cost is a shipped number and needs the Apple-silicon release measurement. The 0.2% CPU and 2.1 energy budget is a target, and printing a target as an observation is exactly the thing this app exists not to do."
                        ),
                        note: "Measured, not budgeted",
                        format: { $0 }
                    )
                    // Not measurements: these are facts about FATHOM's own
                    // configuration, not readings macOS published. Wrapping
                    // them in Measurement would attach a provenance that does
                    // not exist.
                    FathomReadout(
                        label: "Refresh",
                        note: "Stops when the menu bar is hidden"
                    ) {
                        readoutValue("1", unit: "Hz")
                    }
                    FathomReadout(
                        label: "Items shown",
                        note: "Every item costs width you cannot get back"
                    ) {
                        readoutValue(enabledCount.formatted(), unit: "of 4")
                    }
                }
                .padding(.bottom, 22)

                FathomPanel(label: "Live preview — actual size") {
                    VStack(alignment: .leading, spacing: 10) {
                        preview
                        Text("Values read as dashes because the widget is not sampling while this screen is open. The layout is the real one.")
                            .font(.fathomSystem(11.5))
                            .foregroundStyle(
                                .white.opacity(FathomSurface.minimumTextOpacity)
                            )
                    }
                }

                FathomPanel(label: "Items") {
                    VStack(spacing: 3) {
                        setting(
                            "Free space",
                            "The important-usage capacity, not Finder's",
                            $freeSpace
                        )
                        setting(
                            "Hottest sensor",
                            "Only across published sensors",
                            $hottestSensor
                        )
                        setting(
                            "Network throughput",
                            "Download total across active interfaces",
                            $networkThroughput
                        )
                        setting(
                            "CPU load",
                            "Total across published processor ticks",
                            $cpuLoad
                        )
                    }
                }

                FathomNote(
                    headline: "Every item costs width you cannot get back.",
                    detail: "And a sample you did not need. Sampling is coalesced into one task and stops entirely on window occlusion or system sleep. Tahoe's menu-bar allow-list has no readable API, so the widget cannot tell you whether macOS is actually showing it — onboarding names that limitation rather than the app pretending it knows."
                )
            }
            .padding(EdgeInsets(top: 22, leading: 28, bottom: 40, trailing: 28))
        }
    }

    private func readoutValue(_ text: String, unit: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(text)
                .font(.fathomDisplay(34))
                .tracking(-1.02)
                .monospacedDigit()
            Text(unit)
                .font(.fathomSystem(13))
                .foregroundStyle(.white.opacity(FathomSurface.minimumTextOpacity))
        }
    }

    private var enabledCount: Int {
        [freeSpace, hottestSensor, networkThroughput, cpuLoad].count { $0 }
    }

    /// The widget at the height macOS grants it, 22pt, with dashes where the
    /// values would be. Drawing plausible numbers in a preview would make the
    /// one screen about the widget's honesty the one screen that invents.
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
        .frame(width: 320, height: 22)
        .foregroundStyle(.black.opacity(0.82))
        .background(.white.opacity(0.88))
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "Menu bar layout preview, actual size. Values are not published while this screen is open."
        )
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
        FathomDataRow(
            leading: {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.fathomSystem(13, weight: .semibold))
                    Text(detail)
                        .font(.fathomSystem(11.5))
                        .foregroundStyle(
                            .white.opacity(FathomSurface.minimumTextOpacity)
                        )
                }
            },
            trailing: {
                Toggle("", isOn: value)
                    .toggleStyle(.switch)
                    .labelsHidden()
            }
        )
        .accessibilityElement(children: .contain)
    }
}
