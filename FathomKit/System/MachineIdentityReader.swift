import Foundation

/// What machine these numbers came from.
///
/// The section header carries this so a screenshot in a bug report identifies
/// itself. See *Machine identity* in `FATHOM-DATA-SOURCES.md` for why the model
/// identifier is shown rather than a marketing name.
public struct MachineIdentity: Sendable, Equatable {
    /// `hw.model`, e.g. `Mac16,11`.
    public let model: Measurement<String>
    /// `hw.memsize`.
    public let physicalMemoryBytes: Measurement<UInt64>

    public init(
        model: Measurement<String>,
        physicalMemoryBytes: Measurement<UInt64>
    ) {
        self.model = model
        self.physicalMemoryBytes = physicalMemoryBytes
    }

    /// The header line, assembled from whatever is actually published.
    ///
    /// Each part is dropped rather than replaced with a placeholder when its
    /// sysctl says nothing: a header reading `Unknown · 0 GB` claims two
    /// readings that were never taken.
    ///
    /// - Parameter daysRecorded: how many days the local history holds. Pass
    ///   `nil` before the store has been read; pass `0` when it has been read
    ///   and holds nothing, which is a different statement.
    public func headerLine(daysRecorded: Int?) -> String {
        var parts: [String] = []
        if case let .known(model, _) = model { parts.append(model) }
        if case let .known(bytes, _) = physicalMemoryBytes {
            parts.append(
                ByteString.memoryGigabytes(bytes)
            )
        }
        switch daysRecorded {
        case .none:
            break
        case .some(0):
            parts.append("recording since today")
        case let .some(days):
            parts.append("\(days) day\(days == 1 ? "" : "s") recorded")
        }
        return parts.joined(separator: " · ")
    }
}

public struct MachineIdentityReader: Sendable {
    public init() {}

    public func read() -> MachineIdentity {
        MachineIdentity(
            model: Self.string("hw.model"),
            physicalMemoryBytes: Self.integer("hw.memsize")
        )
    }

    private static func string(_ name: String) -> Measurement<String> {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else {
            return .notPublished(reason: "sysctl \(name) did not publish a size")
        }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else {
            return .notPublished(reason: "sysctl \(name) did not publish a value")
        }
        let value = String(cString: buffer)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            return .notPublished(reason: "sysctl \(name) published an empty value")
        }
        return .known(value, source: .sysctlMachineModel)
    }

    private static func integer(_ name: String) -> Measurement<UInt64> {
        var value: UInt64 = 0
        var size = MemoryLayout<UInt64>.size
        guard sysctlbyname(name, &value, &size, nil, 0) == 0, value > 0 else {
            return .notPublished(
                reason: "sysctl \(name) did not publish physical memory"
            )
        }
        return .known(value, source: .sysctlPhysicalMemory)
    }
}
