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
            VStack(alignment: .leading, spacing: 22) {
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Sensors & Power")
                            .font(.fathomDisplay(34))
                            .tracking(-1)
                        Text("One bus per datum. Sampling stops when this screen closes.")
                            .font(.fathomSystem(13))
                            .foregroundStyle(.white.opacity(0.82))
                    }
                    Spacer()
                    Text("LIVE")
                        .font(.fathomSystem(10, weight: .bold))
                        .tracking(1)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(FathomSurface.badge)
                        .clipShape(Capsule())
                        .accessibilityLabel("Live sensor sampling")
                }

                section("TOTAL SYSTEM POWER · SMC PSTR") {
                    HardwareMeasurementView(
                        measurement: presentation.smc
                            .totalSystemPowerWatts,
                        format: {
                            "\($0.formatted(.number.precision(.fractionLength(2)))) W"
                        },
                        prominent: true
                    )
                }

                measurementSection(
                    title: "FANS · APPLESMC",
                    emptyReason: fanEmptyReason(presentation.smc),
                    rows: presentation.smc.fanSpeedsRPM.map {
                        SensorLine(
                            name: $0.key,
                            value: $0.value,
                            format: {
                                "\($0.formatted(.number.precision(.fractionLength(0)))) RPM"
                            }
                        )
                    }
                )

                temperatureSection(presentation.temperatures)
                powerSection(
                    presentation.componentPower,
                    channelMap: presentation.channelMap
                )

                Text(
                    "Unknown channels are not relabelled. Use `fathom dump-channels` to capture the exact runtime inventory for a new SoC map."
                )
                .font(.fathomPath(10.5))
                .foregroundStyle(.white.opacity(0.82))
                .textSelection(.enabled)
            }
            .padding(34)
        }
    }

    private func temperatureSection(
        _ measurement:
            FathomKit.Measurement<[TemperatureSensorReading]>
    ) -> some View {
        switch measurement {
        case let .known(readings, _):
            measurementSection(
                title: "TEMPERATURES · IOHID",
                emptyReason: nil,
                rows: readings.map {
                    SensorLine(
                        name: $0.name,
                        value: $0.celsius,
                        format: {
                            "\($0.formatted(.number.precision(.fractionLength(1)))) °C"
                        }
                    )
                }
            )
        case let .notPublished(reason):
            measurementSection(
                title: "TEMPERATURES · IOHID",
                emptyReason: reason,
                rows: []
            )
        case .notAttributable:
            measurementSection(
                title: "TEMPERATURES · IOHID",
                emptyReason: "Temperature services are not attributable",
                rows: []
            )
        }
    }

    private func powerSection(
        _ measurement:
            FathomKit.Measurement<[IOReportPowerReading]>,
        channelMap: FathomKit.Measurement<IOReportChannelMap>
    ) -> some View {
        switch measurement {
        case let .known(readings, _):
            measurementSection(
                title: "COMPONENT POWER · IOREPORT",
                emptyReason: nil,
                rows: readings.map {
                    SensorLine(
                        name: powerName($0, map: channelMap),
                        value: $0.watts,
                        format: {
                            "\($0.formatted(.number.precision(.fractionLength(3)))) W"
                        }
                    )
                }
            )
        case let .notPublished(reason):
            measurementSection(
                title: "COMPONENT POWER · IOREPORT",
                emptyReason: reason,
                rows: []
            )
        case .notAttributable:
            measurementSection(
                title: "COMPONENT POWER · IOREPORT",
                emptyReason: "Component power is not attributable",
                rows: []
            )
        }
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

    private func fanEmptyReason(_ snapshot: SMCSnapshot) -> String? {
        guard snapshot.fanSpeedsRPM.isEmpty else { return nil }
        switch snapshot.keyInventory {
        case .known:
            return "This SMC inventory contains no fan-speed keys."
        case let .notPublished(reason):
            return reason
        case .notAttributable:
            return "The SMC inventory is not attributable."
        }
    }

    private func measurementSection(
        title: String,
        emptyReason: String?,
        rows: [SensorLine]
    ) -> some View {
        section(title) {
            if let emptyReason {
                Text("not published")
                    .font(.fathomData(15, weight: .medium))
                    .foregroundStyle(.white.opacity(0.82))
                    .help(emptyReason)
                    .accessibilityLabel("Not published. \(emptyReason)")
            } else {
                LazyVGrid(
                    columns: [
                        GridItem(.adaptive(minimum: 220), spacing: 10)
                    ],
                    spacing: 10
                ) {
                    ForEach(rows) { row in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(row.name)
                                .font(.fathomPath(10))
                                .foregroundStyle(.white.opacity(0.82))
                                .lineLimit(1)
                            HardwareMeasurementView(
                                measurement: row.value,
                                format: row.format
                            )
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .background(FathomSurface.card)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
        }
    }

    private func section<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.fathomSystem(10.5, weight: .bold))
                .tracking(1)
                .foregroundStyle(.white.opacity(0.82))
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(.black.opacity(0.17))
        .clipShape(RoundedRectangle(cornerRadius: 22))
    }
}

private struct SensorLine: Identifiable {
    let name: String
    let value: FathomKit.Measurement<Double>
    let format: (Double) -> String

    var id: String { name }
}
