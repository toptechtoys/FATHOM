import AppKit
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
                        measurement: MeasuredIdleCost.load().map {
                            $0.cpuPercent
                                .formatted(.number.precision(.fractionLength(2)))
                        },
                        unit: "% CPU",
                        note: costNote,
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
                    FathomMeasurementReadout(
                        label: "Height",
                        measurement: statusBarThickness,
                        unit: "pt",
                        note: "The height macOS gives the widget, whatever your text size",
                        format: {
                            $0.formatted(.number.precision(.fractionLength(0)))
                        }
                    )
                }
                .padding(.bottom, 22)

                FathomPanel(label: "Live preview — actual size") {
                    VStack(alignment: .leading, spacing: 10) {
                        preview
                        Text(previewNote)
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

    /// What the figure means, including whether it is comparable to the budget.
    ///
    /// The 0.2% target is stated for four items. A cost measured with one item
    /// is a real measurement of a different thing, so the note says which.
    private var costNote: String {
        guard case let .known(cost, _) = MeasuredIdleCost.load() else {
            return "The widget measures itself; the budget is not printed as an observation"
        }
        let verdict = switch IdleCostBudget.verdict(forCPUPercent: cost.cpuPercent) {
        case .withinTarget: "within the 0.2% target"
        case .overTargetWithinBlocking: "over the 0.2% target, under the 0.5% limit"
        case .blocking: "over the 0.5% limit that blocks a release"
        }
        return cost.itemCount == 4
            ? "Measured with four items · \(verdict)"
            : "Measured with \(cost.itemCount) item\(cost.itemCount == 1 ? "" : "s") · the target is stated for four"
    }

    /// What macOS actually gives the status item.
    ///
    /// Read rather than stated. The prototype drew 22 pt and the copy here
    /// repeated it; the figure was correct on this hardware and still had no
    /// source, which is the shape of the endurance-date mistake recorded in the
    /// PRD. `NSStatusBar` is AppKit, so this lives here rather than in
    /// FathomKit, which is deliberately AppKit-free.
    private var statusBarThickness: FathomKit.Measurement<Double> {
        let thickness = NSStatusBar.system.thickness
        guard thickness > 0 else {
            return .notPublished(
                reason: "NSStatusBar published no thickness for the status item."
            )
        }
        return .known(thickness, source: .statusBarThickness)
    }

    /// The preview caption, which names the height rather than asserting it.
    private var previewNote: String {
        let base = "Values read as dashes because the widget is not sampling while this screen is open. The layout is the real one, and it does not grow with your text size"
        guard case let .known(thickness, _) = statusBarThickness else {
            return base + "."
        }
        let points = thickness.formatted(.number.precision(.fractionLength(0)))
        return base + " — macOS gives the widget \(points) points whatever that size is."
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

    /// The widget at the size macOS grants it, with dashes where the values
    /// would be. Drawing plausible numbers in the one screen about the
    /// widget's honesty would be a poor place to start inventing.
    private var preview: some View {
        FathomMenuBarPreview(items: previewItems)
    }

    private var previewItems: [FathomMenuBarPreview.Item] {
        var items: [FathomMenuBarPreview.Item] = []
        if freeSpace { items.append(.init(text: "— GB", isEmphasised: true)) }
        if hottestSensor { items.append(.init(text: "—°")) }
        if networkThroughput { items.append(.init(text: "↓ —")) }
        if cpuLoad { items.append(.init(text: "— %")) }
        items.append(.init(text: "FATHOM"))
        return items
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
