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

    private func content(_ snapshot: BluetoothSnapshot) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                FathomSectionHeader(
                    title: "Bluetooth",
                    subtitle: subtitle(snapshot.devices)
                )

                FathomReadoutGrid {
                    FathomMeasurementReadout(
                        label: "Paired",
                        measurement: snapshot.devices.map { $0.count },
                        unit: "devices",
                        note: "Known to this Mac",
                        format: { $0.formatted() }
                    )
                    FathomMeasurementReadout(
                        label: "Connected",
                        measurement: connectedCount(snapshot.devices),
                        note: "Right now",
                        format: { $0.formatted() }
                    )
                    FathomMeasurementReadout(
                        label: "Will not say",
                        measurement: silentCount(snapshot.devices),
                        unit: "devices",
                        note: "Publish no battery level at all",
                        format: { $0.formatted() }
                    )
                }
                .padding(.bottom, 22)

                FathomPanel(label: "Devices") {
                    devices(snapshot.devices)
                }

                FathomNote(
                    headline: "A blank battery means the device will not say.",
                    detail: "Plenty of third-party Bluetooth peripherals never implement the battery service. Showing an estimate there would be a guess wearing a percentage sign, so the row reads does not report and the meter stays empty."
                )
            }
            .padding(EdgeInsets(top: 22, leading: 28, bottom: 40, trailing: 28))
        }
    }

    @ViewBuilder
    private func devices(
        _ measurement: FathomKit.Measurement<[BluetoothDeviceSnapshot]>
    ) -> some View {
        switch measurement {
        case let .known(devices, _):
            if devices.isEmpty {
                FathomPanelUnavailable(
                    reason: "No devices are paired with this Mac."
                )
            } else {
                FathomDeviceRows(
                    devices: devices.map { device in
                        FathomDeviceRows.Device(
                            name: name(of: device),
                            level: level(of: device)
                        )
                    }
                )
            }
        case let .notPublished(reason):
            FathomPanelUnavailable(reason: reason)
        case let .notAttributable(measured, explained):
            FathomPanelUnavailable(
                reason: "\(measured.count) devices measured, \(explained.count) explained. The rest cannot be attributed.",
                isAttributionGap: true
            )
        }
    }

    /// A device that publishes no name is still a device. Its address is the
    /// only honest label available, so it gets that rather than "Unknown".
    private func name(of device: BluetoothDeviceSnapshot) -> String {
        guard case let .known(name, _) = device.name, !name.isEmpty else {
            return device.address
        }
        return name
    }

    private func level(of device: BluetoothDeviceSnapshot) -> Double? {
        guard case let .known(percent, _) = device.batteryPercent else {
            return nil
        }
        return Double(percent) / 100
    }

    private func connectedCount(
        _ measurement: FathomKit.Measurement<[BluetoothDeviceSnapshot]>
    ) -> FathomKit.Measurement<Int> {
        measurement.map { devices in
            devices.count { device in
                if case let .known(connected, _) = device.connected {
                    return connected
                }
                return false
            }
        }
    }

    private func silentCount(
        _ measurement: FathomKit.Measurement<[BluetoothDeviceSnapshot]>
    ) -> FathomKit.Measurement<Int> {
        measurement.map { devices in
            devices.count { device in
                if case .known = device.batteryPercent { return false }
                return true
            }
        }
    }

    private func subtitle(
        _ measurement: FathomKit.Measurement<[BluetoothDeviceSnapshot]>
    ) -> String {
        guard case let .known(devices, _) = measurement else {
            return "Paired devices not published"
        }
        return "\(devices.count) paired"
    }
}
