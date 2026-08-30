import CFathomHardware
import Foundation

public enum IOReportSamplerError: Error, Sendable, Equatable {
    case cannotCreate(code: Int32)
    case cannotPrime(code: Int32)
    case cannotSample(code: Int32)
    case invalidPayload(reason: String)
}

public struct IOReportStateResidency: Sendable, Equatable {
    public let name: String
    public let residency: Int64

    public init(name: String, residency: Int64) {
        self.name = name
        self.residency = residency
    }
}

public struct IOReportChannelSample: Sendable, Equatable {
    public let group: String
    public let subgroup: String
    public let channel: String
    public let unit: String
    public let integerValue: Measurement<Int64>
    public let states: Measurement<[IOReportStateResidency]>

    public init(
        group: String,
        subgroup: String,
        channel: String,
        unit: String,
        integerValue: Measurement<Int64>,
        states: Measurement<[IOReportStateResidency]>
    ) {
        self.group = group
        self.subgroup = subgroup
        self.channel = channel
        self.unit = unit
        self.integerValue = integerValue
        self.states = states
    }
}

public struct IOReportDeltaSnapshot: Sendable, Equatable {
    public let elapsedSeconds: Double
    public let channels: [IOReportChannelSample]

    public init(
        elapsedSeconds: Double,
        channels: [IOReportChannelSample]
    ) {
        self.elapsedSeconds = elapsedSeconds
        self.channels = channels
    }
}

public struct IOReportPowerReading: Sendable, Equatable, Identifiable {
    public let group: String
    public let subgroup: String
    public let channel: String
    public let watts: Measurement<Double>

    public var id: String { channel }

    public init(
        group: String = "Energy Model",
        subgroup: String = "",
        channel: String,
        watts: Measurement<Double>
    ) {
        self.group = group
        self.subgroup = subgroup
        self.channel = channel
        self.watts = watts
    }
}

public actor IOReportSampler {
    private let handle: IOReportHandle

    public init() throws {
        var pointer: fathom_ioreport_sampler?
        var errorCode: Int32 = 0
        guard fathom_ioreport_sampler_create(
            &pointer,
            &errorCode
        ) == 0, let pointer else {
            throw IOReportSamplerError.cannotCreate(code: errorCode)
        }
        handle = IOReportHandle(pointer: pointer)
    }

    public func sample(
        after interval: Duration = .milliseconds(200)
    ) async throws -> IOReportDeltaSnapshot {
        var errorCode: Int32 = 0
        guard fathom_ioreport_sampler_prime(
            handle.pointer,
            &errorCode
        ) == 0 else {
            throw IOReportSamplerError.cannotPrime(code: errorCode)
        }
        let clock = ContinuousClock()
        let start = clock.now
        try await Task.sleep(for: interval)
        var bytes: UnsafeMutablePointer<UInt8>?
        var length: UInt64 = 0
        guard fathom_ioreport_sampler_copy_delta(
            handle.pointer,
            &bytes,
            &length,
            &errorCode
        ) == 0, let bytes else {
            throw IOReportSamplerError.cannotSample(code: errorCode)
        }
        defer { fathom_hardware_free(bytes) }
        guard length <= UInt64(Int.max) else {
            throw IOReportSamplerError.invalidPayload(
                reason: "The sample exceeds the process range"
            )
        }
        let elapsed = start.duration(to: clock.now)
        let seconds = Self.seconds(elapsed)
        let data = Data(bytes: bytes, count: Int(length))
        return try Self.decodeDelta(data, elapsedSeconds: seconds)
    }

    /// Decodes a live or recorded delta payload.
    ///
    /// The interval is a parameter rather than something read back out of the
    /// payload because `watts(value:unit:elapsedSeconds:)` divides by it. A
    /// recorded delta replayed against the wrong interval yields a wrong figure
    /// rather than a failure, so the interval has to travel with the bytes.
    public static func decodeDelta(
        _ data: Data,
        elapsedSeconds: Double
    ) throws -> IOReportDeltaSnapshot {
        guard elapsedSeconds > 0 else {
            throw IOReportSamplerError.invalidPayload(
                reason: "The sample interval is zero"
            )
        }
        do {
            let decoded = try PropertyListDecoder().decode(
                [IOReportChannelPayload].self,
                from: data
            )
            return IOReportDeltaSnapshot(
                elapsedSeconds: elapsedSeconds,
                channels: decoded.map(\.sample)
            )
        } catch {
            throw IOReportSamplerError.invalidPayload(
                reason: String(describing: error)
            )
        }
    }

    public func samplePower(
        after interval: Duration = .milliseconds(200)
    ) async throws -> Measurement<[IOReportPowerReading]> {
        let snapshot = try await sample(after: interval)
        let energyChannels = snapshot.channels.filter {
            $0.group == "Energy Model"
        }
        guard !energyChannels.isEmpty else {
            return .notPublished(
                reason: "This Mac publishes no Energy Model channels"
            )
        }
        let readings = energyChannels.map { channel in
            IOReportPowerReading(
                group: channel.group,
                subgroup: channel.subgroup,
                channel: channel.channel,
                watts: Self.watts(
                    value: channel.integerValue,
                    unit: channel.unit,
                    elapsedSeconds: snapshot.elapsedSeconds
                )
            )
        }
        return .known(readings, source: .ioReportEnergyDelta)
    }

    static func watts(
        value: Measurement<Int64>,
        unit: String,
        elapsedSeconds: Double
    ) -> Measurement<Double> {
        guard case let .known(raw, _) = value else {
            switch value {
            case let .notPublished(reason):
                return .notPublished(reason: reason)
            case .notAttributable:
                return .notPublished(
                    reason: "The IOReport energy counter is not attributable"
                )
            case .known:
                preconditionFailure("Handled by the guard")
            }
        }
        let divisor: Double
        switch unit.trimmingCharacters(in: .whitespacesAndNewlines) {
        case "J": divisor = 1
        case "mJ": divisor = 1_000
        case "uJ", "µJ": divisor = 1_000_000
        case "nJ": divisor = 1_000_000_000
        default:
            return .notPublished(
                reason: "IOReport energy unit \(unit) is not supported"
            )
        }
        return .known(
            (Double(raw) / divisor) / elapsedSeconds,
            source: .ioReportEnergyDelta
        )
    }

    private static func seconds(_ duration: Duration) -> Double {
        let parts = duration.components
        return Double(parts.seconds) +
            Double(parts.attoseconds) / 1e18
    }
}

private final class IOReportHandle: @unchecked Sendable {
    let pointer: fathom_ioreport_sampler

    init(pointer: fathom_ioreport_sampler) {
        self.pointer = pointer
    }

    deinit {
        fathom_ioreport_sampler_destroy(pointer)
    }
}

private struct IOReportChannelPayload: Decodable {
    let group: String
    let subgroup: String
    let channel: String
    let unit: String
    let format: Int
    let integerValue: Int64?
    let states: [IOReportStatePayload]?

    var sample: IOReportChannelSample {
        IOReportChannelSample(
            group: group,
            subgroup: subgroup,
            channel: channel,
            unit: unit,
            integerValue: integerValue.map {
                .known($0, source: .ioReportSampleDelta)
            } ?? .notPublished(
                reason: "The channel is not a simple integer counter"
            ),
            states: states.map {
                .known(
                    $0.map(\.sample),
                    source: .ioReportSampleDelta
                )
            } ?? .notPublished(
                reason: "The channel does not publish state residencies"
            )
        )
    }
}

private struct IOReportStatePayload: Decodable {
    let name: String
    let residency: Int64

    var sample: IOReportStateResidency {
        IOReportStateResidency(name: name, residency: residency)
    }
}
