import CFathomStorage
import Foundation

public struct OpenFileReferenceInventory: Sendable, Equatable {
    /// Useful diagnostic subset even when another process denied enumeration.
    public let observedIdentities: Set<FileIdentity>
    public let completeIdentities: Measurement<Set<FileIdentity>>
    public let inaccessibleProcessCount: UInt32

    public init(
        observedIdentities: Set<FileIdentity>,
        completeIdentities: Measurement<Set<FileIdentity>>,
        inaccessibleProcessCount: UInt32
    ) {
        self.observedIdentities = observedIdentities
        self.completeIdentities = completeIdentities
        self.inaccessibleProcessCount = inaccessibleProcessCount
    }
}

public enum OpenFileReferenceError: Error, Sendable, Equatable {
    case cannotEnumerate(errorNumber: Int32)
}

public struct OpenFileReferenceReader: Sendable {
    public init() {}

    public func inventory() throws -> OpenFileReferenceInventory {
        let state = OpenFileState()
        let retainedState = Unmanaged.passRetained(state)
        defer { retainedState.release() }

        var inaccessibleProcessCount: UInt32 = 0
        var errorNumber: Int32 = 0
        let result = fathom_open_file_identities(
            openFileCallback,
            retainedState.toOpaque(),
            &inaccessibleProcessCount,
            &errorNumber
        )
        guard result == 0 else {
            throw OpenFileReferenceError.cannotEnumerate(
                errorNumber: errorNumber
            )
        }

        let completeIdentities: Measurement<Set<FileIdentity>>
        if inaccessibleProcessCount == 0 {
            completeIdentities = .known(
                state.identities,
                source: .procOpenFileDescriptors
            )
        } else {
            completeIdentities = .notPublished(
                reason: "\(inaccessibleProcessCount) live processes did not publish their open files"
            )
        }
        return OpenFileReferenceInventory(
            observedIdentities: state.identities,
            completeIdentities: completeIdentities,
            inaccessibleProcessCount: inaccessibleProcessCount
        )
    }
}

private final class OpenFileState {
    var identities: Set<FileIdentity> = []
}

private let openFileCallback: @convention(c) (
    UInt64,
    UInt64,
    UnsafeMutableRawPointer?
) -> Int32 = { device, inode, context in
    guard let context else {
        return 1
    }
    let state = Unmanaged<OpenFileState>
        .fromOpaque(context)
        .takeUnretainedValue()
    state.identities.insert(
        FileIdentity(device: device, inode: inode)
    )
    return 0
}
