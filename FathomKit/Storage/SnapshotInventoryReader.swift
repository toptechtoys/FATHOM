import CFathomStorage
import Foundation

public struct LocalSnapshot: Sendable, Equatable {
    public let name: String

    public init(name: String) {
        self.name = name
    }
}

public enum SnapshotInventoryError: Error, Sendable, Equatable {
    case cannotEnumerate(path: String, errorNumber: Int32)
}

/// Enumerates snapshot names without mounting, deleting, or mutating them.
public struct SnapshotInventoryReader: Sendable {
    public init() {}

    public func inventory(
        forVolumeAt volumeURL: URL
    ) throws -> Measurement<[LocalSnapshot]> {
        let state = SnapshotState()
        let retainedState = Unmanaged.passRetained(state)
        defer { retainedState.release() }

        var errorNumber: Int32 = 0
        let result = volumeURL.withUnsafeFileSystemRepresentation { path in
            guard let path else {
                errorNumber = EINVAL
                return Int32(-1)
            }
            return fathom_snapshot_list(
                path,
                snapshotCallback,
                retainedState.toOpaque(),
                &errorNumber
            )
        }

        guard result == 0 else {
            switch errorNumber {
            case EPERM, EACCES:
                return .notPublished(
                    reason: "Snapshot inventory requires privileges and an entitlement macOS did not grant"
                )
            case ENOTSUP:
                return .notPublished(
                    reason: "This filesystem does not publish snapshots"
                )
            default:
                throw SnapshotInventoryError.cannotEnumerate(
                    path: volumeURL.path,
                    errorNumber: errorNumber
                )
            }
        }

        return .known(
            state.snapshots.sorted { $0.name < $1.name },
            source: .fsSnapshotList
        )
    }
}

private final class SnapshotState {
    var snapshots: [LocalSnapshot] = []
}

private let snapshotCallback: @convention(c) (
    UnsafePointer<CChar>?,
    UInt32,
    UnsafeMutableRawPointer?
) -> Int32 = { name, nameLength, context in
    guard let name, let context else {
        return 1
    }
    let state = Unmanaged<SnapshotState>
        .fromOpaque(context)
        .takeUnretainedValue()
    let bytes = UnsafeRawPointer(name)
        .assumingMemoryBound(to: UInt8.self)
    let buffer = UnsafeBufferPointer(
        start: bytes,
        count: Int(nameLength)
    )
    state.snapshots.append(
        LocalSnapshot(name: String(decoding: buffer, as: UTF8.self))
    )
    return 0
}
