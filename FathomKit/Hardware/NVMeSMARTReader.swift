import CFathomHardware
import Foundation

public struct NVMeSMARTSnapshot: Sendable, Equatable {
    public let bytesRead: Measurement<UInt64>
    public let bytesWritten: Measurement<UInt64>
    public let percentageUsed: Measurement<UInt64>
    public let availableSparePercent: Measurement<UInt64>
    public let powerOnHours: Measurement<UInt64>
    public let powerCycles: Measurement<UInt64>
    public let unsafeShutdowns: Measurement<UInt64>
    public let mediaErrors: Measurement<UInt64>
    public let criticalWarning: Measurement<UInt64>
    public let temperatureCelsius: Measurement<Double>
    public let lifetimeBytesWrittenPerHour: Measurement<Double>
    public let linearPowerOnHoursAtHundredPercent: Measurement<Double>

    public init(
        bytesRead: Measurement<UInt64>,
        bytesWritten: Measurement<UInt64>,
        percentageUsed: Measurement<UInt64>,
        availableSparePercent: Measurement<UInt64>,
        powerOnHours: Measurement<UInt64>,
        powerCycles: Measurement<UInt64>,
        unsafeShutdowns: Measurement<UInt64>,
        mediaErrors: Measurement<UInt64>,
        criticalWarning: Measurement<UInt64>,
        temperatureCelsius: Measurement<Double>,
        lifetimeBytesWrittenPerHour: Measurement<Double>,
        linearPowerOnHoursAtHundredPercent: Measurement<Double>
    ) {
        self.bytesRead = bytesRead
        self.bytesWritten = bytesWritten
        self.percentageUsed = percentageUsed
        self.availableSparePercent = availableSparePercent
        self.powerOnHours = powerOnHours
        self.powerCycles = powerCycles
        self.unsafeShutdowns = unsafeShutdowns
        self.mediaErrors = mediaErrors
        self.criticalWarning = criticalWarning
        self.temperatureCelsius = temperatureCelsius
        self.lifetimeBytesWrittenPerHour = lifetimeBytesWrittenPerHour
        self.linearPowerOnHoursAtHundredPercent =
            linearPowerOnHoursAtHundredPercent
    }
}

public struct NVMeSMARTReader: Sendable {
    public init() {}

    public func read() -> NVMeSMARTSnapshot {
        var raw = fathom_nvme_smart_data()
        var errorCode: Int32 = 0
        var controllersSeen: UInt32 = 0
        guard fathom_nvme_smart_read(
            &raw,
            &errorCode,
            &controllersSeen
        ) == 0 else {
            let reason: String
            if controllersSeen == 0 {
                reason = "No NVMe SMART-capable controller was published"
            } else {
                reason =
                    "macOS denied or failed the read-only NVMe SMART user client (IOReturn \(errorCode))"
            }
            return Self.notPublished(reason: reason)
        }
        return Self.parse(raw)
    }

    static func parse(
        _ raw: fathom_nvme_smart_data
    ) -> NVMeSMARTSnapshot {
        let unitsRead = uint128Low(
            low: raw.data_units_read_low,
            high: raw.data_units_read_high,
            field: "data units read"
        )
        let unitsWritten = uint128Low(
            low: raw.data_units_written_low,
            high: raw.data_units_written_high,
            field: "data units written"
        )
        let bytesRead = dataUnitBytes(unitsRead, field: "bytes read")
        let bytesWritten = dataUnitBytes(
            unitsWritten,
            field: "bytes written"
        )
        let hours = uint128Low(
            low: raw.power_on_hours_low,
            high: raw.power_on_hours_high,
            field: "power-on hours"
        )
        let percentage = UInt64(raw.percentage_used)

        let writeRate: Measurement<Double>
        switch (bytesWritten, hours) {
        case let (.known(bytes, _), .known(powerOnHours, _)):
            if powerOnHours > 0 {
                writeRate = .known(
                    Double(bytes) / Double(powerOnHours),
                    source: .nvmeSMARTLifetimeDerivation
                )
            } else {
                writeRate = .notPublished(
                    reason: "The controller reports zero power-on hours"
                )
            }
        case let (.notPublished(reason), _),
             let (_, .notPublished(reason)):
            writeRate = .notPublished(reason: reason)
        case (.notAttributable, _), (_, .notAttributable):
            writeRate = .notPublished(
                reason: "Lifetime write rate is not attributable"
            )
        }

        let projection: Measurement<Double>
        switch hours {
        case let .known(powerOnHours, _):
            if percentage > 0 {
                projection = .known(
                    Double(powerOnHours) / (Double(percentage) / 100),
                    source: .nvmeSMARTLifetimeDerivation
                )
            } else {
                projection = .notPublished(
                    reason: "The controller reports zero percent used; a finite projection cannot be justified"
                )
            }
        case let .notPublished(reason):
            projection = .notPublished(reason: reason)
        case .notAttributable:
            projection = .notPublished(
                reason: "Power-on hours are not attributable"
            )
        }

        let temperature: Measurement<Double>
        if raw.temperature_kelvin == 0 ||
            raw.temperature_kelvin == UInt16.max
        {
            temperature = .notPublished(
                reason: "The controller did not publish a valid temperature"
            )
        } else {
            temperature = .known(
                Double(raw.temperature_kelvin) - 273.15,
                source: .nvmeSMARTLogPage
            )
        }

        return NVMeSMARTSnapshot(
            bytesRead: bytesRead,
            bytesWritten: bytesWritten,
            percentageUsed: .known(
                percentage,
                source: .nvmeSMARTLogPage
            ),
            availableSparePercent: .known(
                UInt64(raw.available_spare),
                source: .nvmeSMARTLogPage
            ),
            powerOnHours: hours,
            powerCycles: uint128Low(
                low: raw.power_cycles_low,
                high: raw.power_cycles_high,
                field: "power cycles"
            ),
            unsafeShutdowns: uint128Low(
                low: raw.unsafe_shutdowns_low,
                high: raw.unsafe_shutdowns_high,
                field: "unsafe shutdowns"
            ),
            mediaErrors: uint128Low(
                low: raw.media_errors_low,
                high: raw.media_errors_high,
                field: "media errors"
            ),
            criticalWarning: .known(
                UInt64(raw.critical_warning),
                source: .nvmeSMARTLogPage
            ),
            temperatureCelsius: temperature,
            lifetimeBytesWrittenPerHour: writeRate,
            linearPowerOnHoursAtHundredPercent: projection
        )
    }

    private static func uint128Low(
        low: UInt64,
        high: UInt64,
        field: String
    ) -> Measurement<UInt64> {
        guard high == 0 else {
            return .notPublished(
                reason: "NVMe \(field) exceeds FATHOM's 64-bit display range"
            )
        }
        return .known(low, source: .nvmeSMARTLogPage)
    }

    private static func dataUnitBytes(
        _ units: Measurement<UInt64>,
        field: String
    ) -> Measurement<UInt64> {
        switch units {
        case let .known(value, _):
            let (bytes, overflow) = value.multipliedReportingOverflow(
                by: 512_000
            )
            guard !overflow else {
                return .notPublished(
                    reason: "NVMe \(field) exceeds FATHOM's byte range"
                )
            }
            return .known(bytes, source: .nvmeSMARTLogPage)
        case let .notPublished(reason):
            return .notPublished(reason: reason)
        case let .notAttributable(measured, explained):
            return .notAttributable(
                measured: measured,
                explained: explained
            )
        }
    }

    private static func notPublished(
        reason: String
    ) -> NVMeSMARTSnapshot {
        NVMeSMARTSnapshot(
            bytesRead: .notPublished(reason: reason),
            bytesWritten: .notPublished(reason: reason),
            percentageUsed: .notPublished(reason: reason),
            availableSparePercent: .notPublished(reason: reason),
            powerOnHours: .notPublished(reason: reason),
            powerCycles: .notPublished(reason: reason),
            unsafeShutdowns: .notPublished(reason: reason),
            mediaErrors: .notPublished(reason: reason),
            criticalWarning: .notPublished(reason: reason),
            temperatureCelsius: .notPublished(reason: reason),
            lifetimeBytesWrittenPerHour: .notPublished(reason: reason),
            linearPowerOnHoursAtHundredPercent:
                .notPublished(reason: reason)
        )
    }
}
