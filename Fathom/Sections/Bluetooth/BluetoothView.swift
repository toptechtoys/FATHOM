import FathomKit
import SwiftUI

struct BluetoothView: View {
    @EnvironmentObject private var model: SystemMonitorModel

    var body: some View {
        Group {
            switch model.state {
            case .idle, .reading:
                ProgressView("Reading paired Bluetooth devices…")
                    .controlSize(.large)
            case let .result(presentation):
                content(presentation.bluetooth)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            model.start()
            model.beginBluetoothObservation()
        }
        .onDisappear {
            model.endBluetoothObservation()
            model.stop()
        }
    }

    @ViewBuilder
    private func content(_ snapshot: BluetoothSnapshot) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Bluetooth")
                    .font(.fathomDisplay(34))
                switch snapshot.devices {
                case let .known(devices, source):
                    if devices.isEmpty {
                        Text("No paired devices")
                            .foregroundStyle(.white.opacity(0.82))
                            .help(source.rawValue)
                    } else {
                        ForEach(devices) { device in
                            deviceCard(device)
                        }
                    }
                case let .notPublished(reason):
                    Text("not published")
                        .foregroundStyle(.white.opacity(0.82))
                        .help(reason)
                        .accessibilityLabel("Not published. \(reason)")
                case let .notAttributable(measured, explained):
                    Text("not attributable")
                        .accessibilityLabel(
                            "Not attributable. \(measured.count) measured, \(explained.count) explained"
                        )
                }
                Text("Battery is shown only when the device publishes BatteryPercent. No estimate is made from connection time.")
                    .font(.fathomSystem(12.5))
                    .foregroundStyle(.white.opacity(0.82))
            }
            .padding(34)
        }
    }

    private func deviceCard(
        _ device: BluetoothDeviceSnapshot
    ) -> some View {
        HardwareResultCard(label: device.address) {
            HStack {
                HardwareMeasurementView(
                    measurement: device.name,
                    format: { $0 }
                )
                Spacer()
                HardwareMeasurementView(
                    measurement: device.connected,
                    format: { $0 ? "Connected" : "Not connected" }
                )
                battery(device.batteryPercent)
            }
        }
    }

    @ViewBuilder
    private func battery(
        _ measurement: FathomKit.Measurement<Int>
    ) -> some View {
        switch measurement {
        case let .known(value, source):
            Text("\(value)%")
                .font(.fathomData(19, weight: .semibold))
                .help(source.rawValue)
        case let .notPublished(reason):
            Text(reason.contains("does not report") ? "does not report" : "not published")
                .font(.fathomData(14, weight: .medium))
                .foregroundStyle(.white.opacity(0.82))
                .help(reason)
                .accessibilityLabel("Battery \(reason)")
        case let .notAttributable(measured, explained):
            Text("not attributable")
                .accessibilityLabel(
                    "Battery not attributable. \(measured) measured, \(explained) explained"
                )
        }
    }
}
