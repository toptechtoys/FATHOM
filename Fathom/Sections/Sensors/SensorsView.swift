import FathomKit
import SwiftUI

struct SensorsView: View {
    @EnvironmentObject private var model: HardwareAppModel

    var body: some View {
        Group {
            switch model.sensorState {
            case .idle, .reading:
                ProgressView("Reading hardware buses…")
                    .controlSize(.large)
                    .font(.fathomSystem(13))
            case let .result(presentation):
                result(presentation)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear(perform: model.startSensors)
        .onDisappear(perform: model.stopSensors)
    }

    private func result(_ presentation: SensorPresentation) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                FathomSectionHeader(
                    title: "Sensors & Power",
                    subtitle: subtitle(presentation)
                )

                FathomReadoutGrid {
                    FathomMeasurementReadout(
                        label: "Total system power",
                        measurement: presentation.smc.totalSystemPowerWatts,
                        unit: "W",
                        note: "SMC PSTR, the whole machine",
                        format: {
                            $0.formatted(.number.precision(.fractionLength(2)))
                        }
                    )
                    FathomMeasurementReadout(
                        label: "Hottest",
                        measurement: hottest(presentation.temperatures),
                        unit: "°C",
                        note: hottestNote(presentation.temperatures),
                        format: {
                            $0.formatted(.number.precision(.fractionLength(1)))
                        }
                    )
                    FathomMeasurementReadout(
                        label: "Sensors",
                        measurement: presentation.temperatures.map { $0.count },
                        unit: "published",
                        note: "Every one this Mac exposes over IOHID",
                        format: { $0.formatted() }
                    )
                    FathomMeasurementReadout(
                        label: "Fans",
                        measurement: fanCount(presentation.smc),
                        note: fanNote(presentation.smc),
                        format: { $0.formatted() }
                    )
                }
                .padding(.bottom, 22)

                FathomPanel(label: "Temperature · IOHID") {
                    temperatures(presentation.temperatures)
                }

                FathomPanel(label: "Fans · AppleSMC") {
                    fans(presentation.smc)
                }

                FathomPanel(label: "Component power · IOReport") {
                    componentPower(
                        presentation.componentPower,
                        channelMap: presentation.channelMap
                    )
                }

                FathomNote(
                    headline: "A dash means the sensor does not exist here.",
                    detail: "Where a Mac has no fan the row reads nothing rather than interpolating a plausible number from its neighbours, and an unknown IOReport channel keeps its raw name rather than being relabelled to something friendlier that might be wrong."
                )

                Text("Use `fathom dump-channels` to capture the exact runtime inventory for a new SoC map.")
                    .font(.fathomPath(10.5))
                    .foregroundStyle(.white.opacity(FathomSurface.minimumTextOpacity))
                    .textSelection(.enabled)
                    .padding(.top, 18)
            }
            .padding(EdgeInsets(top: 22, leading: 28, bottom: 40, trailing: 28))
        }
    }

    @ViewBuilder
    private func temperatures(
        _ measurement: FathomKit.Measurement<[TemperatureSensorReading]>
    ) -> some View {
        switch measurement {
        case let .known(readings, _):
            if readings.isEmpty {
                FathomPanelUnavailable(
                    reason: "This Mac publishes no temperature sensors over IOHID."
                )
            } else {
                VStack(spacing: 3) {
                    ForEach(readings) { reading in
                        valueRow(reading.name, reading.celsius) {
                            $0.formatted(.number.precision(.fractionLength(1)))
                                + " °C"
                        }
                    }
                }
            }
        case let .notPublished(reason):
            FathomPanelUnavailable(reason: reason)
        case .notAttributable:
            FathomPanelUnavailable(
                reason: "Temperature services are not attributable on this Mac.",
                isAttributionGap: true
            )
        }
    }

    @ViewBuilder
    private func fans(_ smc: SMCSnapshot) -> some View {
        if smc.fanSpeedsRPM.isEmpty {
            FathomPanelUnavailable(reason: fanEmptyReason(smc))
        } else {
            VStack(spacing: 3) {
                ForEach(smc.fanSpeedsRPM, id: \.key) { reading in
                    valueRow(reading.key, reading.value) {
                        $0.formatted(.number.precision(.fractionLength(0)))
                            + " RPM"
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func componentPower(
        _ measurement: FathomKit.Measurement<[IOReportPowerReading]>,
        channelMap: FathomKit.Measurement<IOReportChannelMap>
    ) -> some View {
        switch measurement {
        case let .known(readings, _):
            if readings.isEmpty {
                FathomPanelUnavailable(
                    reason: "IOReport published no power channels on this Mac."
                )
            } else {
                VStack(spacing: 3) {
                    ForEach(readings) { reading in
                        valueRow(
                            powerName(reading, map: channelMap),
                            reading.watts
                        ) {
                            $0.formatted(.number.precision(.fractionLength(3)))
                                + " W"
                        }
                    }
                }
            }
        case let .notPublished(reason):
            FathomPanelUnavailable(reason: reason)
        case .notAttributable:
            FathomPanelUnavailable(
                reason: "IOReport power channels are not attributable.",
                isAttributionGap: true
            )
        }
    }

    private func valueRow(
        _ name: String,
        _ measurement: FathomKit.Measurement<Double>,
        format: (Double) -> String
    ) -> some View {
        switch measurement {
        case let .known(value, source):
            FathomDataRow.simple(
                name,
                value: format(value),
                annotation: source.rawValue
            )
        case let .notPublished(reason):
            FathomDataRow.simple(
                name,
                value: "—",
                valueColor: .white.opacity(FathomSurface.minimumTextOpacity),
                annotation: reason
            )
        case let .notAttributable(measured, _):
            FathomDataRow.simple(
                name,
                value: format(measured),
                valueColor: FathomSemantic.caution,
                annotation: "not fully attributable",
                isEmphasised: true
            )
        }
    }

    /// The hottest published sensor, not an average.
    ///
    /// An average across sensors on different parts of the board answers no
    /// question anyone has; the hottest one is what throttles the machine.
    private func hottest(
        _ measurement: FathomKit.Measurement<[TemperatureSensorReading]>
    ) -> FathomKit.Measurement<Double> {
        switch measurement {
        case let .known(readings, source):
            let values = readings.compactMap { reading -> Double? in
                guard case let .known(celsius, _) = reading.celsius else {
                    return nil
                }
                return celsius
            }
            guard let peak = values.max() else {
                return .notPublished(
                    reason: "No temperature sensor published a reading."
                )
            }
            return .known(peak, source: source)
        case let .notPublished(reason):
            return .notPublished(reason: reason)
        case .notAttributable:
            return .notPublished(
                reason: "Temperature services are not attributable on this Mac."
            )
        }
    }

    private func hottestNote(
        _ measurement: FathomKit.Measurement<[TemperatureSensorReading]>
    ) -> String {
        guard case let .known(readings, _) = measurement else {
            return "The peak of every published sensor"
        }
        let hottestName = readings
            .compactMap { reading -> (String, Double)? in
                guard case let .known(celsius, _) = reading.celsius else {
                    return nil
                }
                return (reading.name, celsius)
            }
            .max { $0.1 < $1.1 }?
            .0
        return hottestName.map { "\($0), the peak of every sensor" }
            ?? "The peak of every published sensor"
    }

    private func fanCount(_ smc: SMCSnapshot) -> FathomKit.Measurement<Int> {
        guard smc.fanSpeedsRPM.isEmpty else {
            return .known(smc.fanSpeedsRPM.count, source: .appleSMCReadKey)
        }
        return .notPublished(reason: fanEmptyReason(smc))
    }

    private func fanNote(_ smc: SMCSnapshot) -> String {
        smc.fanSpeedsRPM.isEmpty
            ? "This Mac is passively cooled"
            : "Reported by AppleSMC"
    }

    private func fanEmptyReason(_ smc: SMCSnapshot) -> String {
        switch smc.keyInventory {
        case .known:
            "AppleSMC published no fan keys. This Mac has no fan."
        case let .notPublished(reason):
            reason
        case .notAttributable:
            "The AppleSMC key inventory is not attributable."
        }
    }

    private func subtitle(_ presentation: SensorPresentation) -> String {
        guard case let .known(readings, _) = presentation.temperatures else {
            return "One bus per datum · stops when this screen closes"
        }
        return "\(readings.count) sensors · stops when this screen closes"
    }

    private func powerName(
        _ reading: IOReportPowerReading,
        map: FathomKit.Measurement<IOReportChannelMap>
    ) -> String {
        guard case let .known(channelMap, _) = map else {
            return reading.channel
        }
        return channelMap.friendlyName(
            group: reading.group,
            subgroup: reading.subgroup,
            channel: reading.channel
        ) ?? reading.channel
    }
}
