import FathomKit
import SwiftUI

struct NetworkView: View {
    @EnvironmentObject private var model: SystemMonitorModel

    var body: some View {
        Group {
            switch model.state {
            case .idle, .reading:
                ProgressView("Establishing a network counter delta…")
                    .controlSize(.large)
            case let .result(presentation):
                content(presentation.network)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear(perform: model.start)
        .onDisappear(perform: model.stop)
    }

    @ViewBuilder
    private func content(_ snapshot: NetworkSnapshot) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Network")
                    .font(.fathomDisplay(34))
                localAddressCard(snapshot.localAddresses)
                configurationCard(snapshot.configuration)
                WiFiCard()
                switch snapshot.interfaces {
                case let .known(interfaces, source):
                    if interfaces.isEmpty {
                        Text("No active non-loopback interfaces")
                            .foregroundStyle(.white.opacity(0.82))
                            .help(source.rawValue)
                    } else {
                        ForEach(interfaces) { interface in
                            interfaceCard(interface)
                        }
                    }
                case let .notPublished(reason):
                    HardwareMeasurementView(
                        measurement: FathomKit.Measurement<String>.notPublished(reason: reason),
                        format: { $0 }
                    )
                case .notAttributable:
                    Text("not attributable")
                }
                Text("Per-process attribution is not published: kernel interface totals cannot honestly be redistributed to processes. Little Snitch is the right tool when reliable per-process traffic is the job.")
                    .font(.fathomSystem(12.5))
                    .foregroundStyle(.white.opacity(0.82))
            }
            .padding(34)
        }
    }

    private func configurationCard(
        _ snapshot: NetworkConfigurationSnapshot
    ) -> some View {
        HardwareResultCard(label: "SYSTEM NETWORK STATE") {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 180), spacing: 16)],
                alignment: .leading,
                spacing: 10
            ) {
                stringMetric("PRIMARY INTERFACE", snapshot.primaryInterface)
                stringMetric("ROUTER", snapshot.router)
                VStack(alignment: .leading, spacing: 4) {
                    Text("DNS SERVERS")
                        .font(.fathomSystem(10, weight: .bold))
                        .foregroundStyle(.white.opacity(0.82))
                    HardwareMeasurementView(
                        measurement: snapshot.dnsServers,
                        format: { $0.joined(separator: ", ") }
                    )
                }
            }
        }
    }

    private func stringMetric(
        _ label: String,
        _ measurement: FathomKit.Measurement<String>
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.fathomSystem(10, weight: .bold))
                .foregroundStyle(.white.opacity(0.82))
            HardwareMeasurementView(
                measurement: measurement,
                format: { $0 }
            )
        }
    }

    @ViewBuilder
    private func localAddressCard(
        _ measurement: FathomKit.Measurement<[NetworkAddress]>
    ) -> some View {
        HardwareResultCard(label: "LOCAL ADDRESSES") {
            switch measurement {
            case let .known(addresses, source):
                if addresses.isEmpty {
                    Text("No active non-loopback IPv4 or IPv6 address")
                        .foregroundStyle(.white.opacity(0.82))
                } else {
                    LazyVGrid(
                        columns: [
                            GridItem(.adaptive(minimum: 220), spacing: 12)
                        ],
                        alignment: .leading,
                        spacing: 10
                    ) {
                        ForEach(addresses) { address in
                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(address.interfaceName) · IPv\(address.family)")
                                    .font(.fathomSystem(10, weight: .bold))
                                    .foregroundStyle(.white.opacity(0.82))
                                Text(address.address)
                                    .font(.fathomPath(13))
                                    .textSelection(.enabled)
                            }
                        }
                    }
                }
                Text("Published by \(source.rawValue)")
                    .font(.fathomPath(9.5))
                    .foregroundStyle(.white.opacity(0.68))
            case let .notPublished(reason):
                Text("not published")
                    .foregroundStyle(.white.opacity(0.82))
                    .help(reason)
            case .notAttributable:
                Text("not attributable")
            }
        }
    }

    private func interfaceCard(
        _ interface: NetworkInterfaceMetrics
    ) -> some View {
        HardwareResultCard(label: interface.name.uppercased()) {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 150), spacing: 20)],
                alignment: .leading,
                spacing: 12
            ) {
                metric("DOWN", interface.receivedBytesPerSecond)
                metric("UP", interface.sentBytesPerSecond)
                VStack(alignment: .leading, spacing: 4) {
                    Text("LIFETIME")
                        .font(.fathomSystem(10, weight: .bold))
                        .foregroundStyle(.white.opacity(0.82))
                    Text("↓ \(hardwareByteString(interface.receivedBytes))  ↑ \(hardwareByteString(interface.sentBytes))")
                        .font(.fathomData(14, weight: .semibold))
                }
            }
        }
    }

    private func metric(
        _ label: String,
        _ value: FathomKit.Measurement<Double>
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.fathomSystem(10, weight: .bold))
                .foregroundStyle(.white.opacity(0.82))
            HardwareMeasurementView(
                measurement: value,
                format: { "\(hardwareByteString($0))/s" }
            )
        }
    }
}

private struct WiFiCard: View {
    @State private var snapshot: WiFiSnapshot?
    @State private var reading = false

    var body: some View {
        HardwareResultCard(label: "WI-FI · USER-TRIGGERED") {
            if let snapshot {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 160), spacing: 16)],
                    alignment: .leading,
                    spacing: 10
                ) {
                    metric("INTERFACE", snapshot.interfaceName) { $0 }
                    metric("SSID", snapshot.ssid) { $0 }
                    metric("RSSI", snapshot.rssi) { "\($0) dBm" }
                }
            } else {
                Text(
                    "macOS may request Location Services because it treats the connected network name as location data. FATHOM reads it only when you ask."
                )
                .font(.fathomSystem(11.5))
                .foregroundStyle(.white.opacity(0.82))
            }
            Button(reading ? "Reading…" : "Read Wi-Fi details") {
                reading = true
                Task {
                    snapshot = await Task.detached(priority: .utility) {
                        WiFiReader().read()
                    }.value
                    reading = false
                }
            }
            .disabled(reading)
        }
    }

    private func metric<Value: Sendable>(
        _ label: String,
        _ measurement: FathomKit.Measurement<Value>,
        format: @escaping (Value) -> String
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.fathomSystem(10, weight: .bold))
                .foregroundStyle(.white.opacity(0.82))
            HardwareMeasurementView(
                measurement: measurement,
                format: format
            )
        }
    }
}
