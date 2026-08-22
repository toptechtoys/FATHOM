import FathomKit
import SwiftUI

struct NetworkView: View {
    @EnvironmentObject private var model: SystemMonitorModel

    var body: some View {
        Group {
            switch model.state {
            case .idle, .reading:
                ProgressView("Establishing an interface counter delta…")
                    .controlSize(.large)
            case let .result(presentation):
                content(presentation.network)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear(perform: model.start)
        .onDisappear(perform: model.stop)
    }

    private func content(_ snapshot: NetworkSnapshot) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                FathomSectionHeader(
                    title: "Network",
                    subtitle: subtitle(snapshot.configuration)
                )

                FathomReadoutGrid {
                    FathomMeasurementReadout(
                        label: "Down",
                        measurement: snapshot.totalThroughput,
                        note: "Across every active interface",
                        format: rate
                    )
                    FathomMeasurementReadout(
                        label: "Up",
                        measurement: sentThroughput(snapshot),
                        note: "Across every active interface",
                        format: rate
                    )
                    FathomMeasurementReadout(
                        label: "Interfaces",
                        measurement: snapshot.interfaces.map { $0.count },
                        unit: "active",
                        note: "Non-loopback, carrying traffic",
                        format: { $0.formatted() }
                    )
                    FathomMeasurementReadout(
                        label: "Primary",
                        measurement: snapshot.configuration.primaryInterface,
                        note: "As the system configuration reports it",
                        format: { $0 }
                    )
                }
                .padding(.bottom, 22)

                FathomPanel(label: "Throughput, last 60 seconds") {
                    FathomSparkline(
                        history: model.networkHistory,
                        accessibilityValue: "Bytes received per second"
                    )
                }

                FathomPanel(label: "Per interface") {
                    interfaces(snapshot.interfaces)
                }

                FathomPanel(label: "Addresses") {
                    addresses(snapshot.localAddresses)
                }

                PublicIPPanel()
                    .padding(.bottom, 26)

                FathomPanel(label: "System network state") {
                    VStack(spacing: 3) {
                        stringRow("Router", snapshot.configuration.router)
                        listRow("DNS servers", snapshot.configuration.dnsServers)
                    }
                }

                FathomPanel(label: "Wi-Fi · user-triggered") {
                    WiFiPanel()
                }

                FathomNote(
                    headline: "There is no per-process breakdown here.",
                    detail: "macOS does not attribute traffic to processes in a way we would stand behind, and kernel interface totals cannot honestly be redistributed. Little Snitch does it properly with a network extension, and we would rather send you there than guess."
                )
            }
            .padding(EdgeInsets(top: 22, leading: 28, bottom: 40, trailing: 28))
        }
    }

    @ViewBuilder
    private func interfaces(
        _ measurement: FathomKit.Measurement<[NetworkInterfaceMetrics]>
    ) -> some View {
        switch measurement {
        case let .known(interfaces, _):
            if interfaces.isEmpty {
                FathomPanelUnavailable(
                    reason: "No non-loopback interface is currently active."
                )
            } else {
                VStack(spacing: 3) {
                    ForEach(interfaces) { interface in
                        FathomDataRow.simple(
                            interface.name,
                            value: throughput(interface.receivedBytesPerSecond),
                            annotation: "up "
                                + throughput(interface.sentBytesPerSecond)
                                + " · "
                                + interface.receivedBytes.formatted(
                                    .byteCount(style: .file)
                                )
                                + " received in total"
                        )
                    }
                }
            }
        case let .notPublished(reason):
            FathomPanelUnavailable(reason: reason)
        case .notAttributable:
            FathomPanelUnavailable(
                reason: "Interface counters cannot be attributed to interfaces.",
                isAttributionGap: true
            )
        }
    }

    @ViewBuilder
    private func addresses(
        _ measurement: FathomKit.Measurement<[NetworkAddress]>
    ) -> some View {
        switch measurement {
        case let .known(addresses, source):
            if addresses.isEmpty {
                FathomPanelUnavailable(
                    reason: "No active non-loopback IPv4 or IPv6 address."
                )
            } else {
                VStack(spacing: 3) {
                    ForEach(addresses) { address in
                        FathomDataRow.simple(
                            "\(address.interfaceName) · IPv\(address.family)",
                            value: address.address,
                            annotation: source.rawValue
                        )
                    }
                }
            }
        case let .notPublished(reason):
            FathomPanelUnavailable(reason: reason)
        case .notAttributable:
            FathomPanelUnavailable(
                reason: "Addresses cannot be attributed to interfaces.",
                isAttributionGap: true
            )
        }
    }

    private func stringRow(
        _ label: String,
        _ measurement: FathomKit.Measurement<String>
    ) -> some View {
        switch measurement {
        case let .known(value, source):
            FathomDataRow.simple(label, value: value, annotation: source.rawValue)
        case let .notPublished(reason):
            FathomDataRow.simple(
                label,
                value: "not published",
                valueColor: .white.opacity(FathomSurface.minimumTextOpacity),
                annotation: reason
            )
        case .notAttributable:
            FathomDataRow.simple(
                label,
                value: "not attributable",
                valueColor: FathomSemantic.caution,
                isEmphasised: true
            )
        }
    }

    private func listRow(
        _ label: String,
        _ measurement: FathomKit.Measurement<[String]>
    ) -> some View {
        stringRow(label, measurement.map { $0.joined(separator: ", ") })
    }

    private func sentThroughput(
        _ snapshot: NetworkSnapshot
    ) -> FathomKit.Measurement<Double> {
        snapshot.interfaces.map { list in
            list.reduce(0.0) { running, interface in
                guard case let .known(rate, _) = interface.sentBytesPerSecond
                else { return running }
                return running + rate
            }
        }
    }

    private func throughput(
        _ measurement: FathomKit.Measurement<Double>
    ) -> String {
        guard case let .known(value, _) = measurement else {
            return "not published"
        }
        return rate(value)
    }

    private func rate(_ bytesPerSecond: Double) -> String {
        UInt64(max(0, bytesPerSecond))
            .formatted(.byteCount(style: .file)) + "/s"
    }

    private func subtitle(_ configuration: NetworkConfigurationSnapshot) -> String {
        guard case let .known(primary, _) = configuration.primaryInterface else {
            return "Sampling 1 Hz while visible"
        }
        return "\(primary) · sampling 1 Hz"
    }
}

/// Wi-Fi details stay behind a button.
///
/// macOS treats the connected network name as location data and may prompt for
/// Location Services, so this is read when asked for and not before — a section
/// that triggers a permission prompt merely by being opened has spent the
/// user's trust without asking.
private struct WiFiPanel: View {
    @State private var snapshot: WiFiSnapshot?
    @State private var isReading = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let snapshot {
                VStack(spacing: 3) {
                    row("Interface", snapshot.interfaceName) { $0 }
                    row("SSID", snapshot.ssid) { $0 }
                    row("RSSI", snapshot.rssi) { "\($0) dBm" }
                }
            } else {
                Text("macOS may request Location Services, because it treats the connected network name as location data. FATHOM reads it only when you ask.")
                    .font(.fathomSystem(11.5))
                    .foregroundStyle(.white.opacity(FathomSurface.minimumTextOpacity))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 560, alignment: .leading)
            }

            Button(isReading ? "Reading…" : "Read Wi-Fi details") {
                isReading = true
                Task {
                    snapshot = await Task.detached(priority: .utility) {
                        WiFiReader().read()
                    }.value
                    isReading = false
                }
            }
            .buttonStyle(.plain)
            .font(.fathomSystem(12, weight: .semibold))
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(.white.opacity(0.14))
            .overlay {
                RoundedRectangle(cornerRadius: 15)
                    .stroke(.white.opacity(0.22), lineWidth: 0.5)
            }
            .clipShape(RoundedRectangle(cornerRadius: 15))
            .disabled(isReading)
        }
    }

    private func row<Value>(
        _ label: String,
        _ measurement: FathomKit.Measurement<Value>,
        format: (Value) -> String
    ) -> some View {
        switch measurement {
        case let .known(value, source):
            FathomDataRow.simple(
                label,
                value: format(value),
                annotation: source.rawValue
            )
        case let .notPublished(reason):
            FathomDataRow.simple(
                label,
                value: "not published",
                valueColor: .white.opacity(FathomSurface.minimumTextOpacity),
                annotation: reason
            )
        case let .notAttributable(measured, _):
            FathomDataRow.simple(
                label,
                value: format(measured),
                valueColor: FathomSemantic.caution,
                annotation: "not fully attributable",
                isEmphasised: true
            )
        }
    }
}
