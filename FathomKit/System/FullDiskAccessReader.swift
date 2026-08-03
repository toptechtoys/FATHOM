import Darwin
import Foundation

public struct FullDiskAccessReader: Sendable {
    public init() {}

    public func read(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> Measurement<Bool> {
        let canary = homeDirectory
            .appendingPathComponent("Library/Application Support/com.apple.TCC")
            .appendingPathComponent("TCC.db")
        let descriptor = canary.path.withCString {
            open($0, O_RDONLY | O_CLOEXEC)
        }
        if descriptor >= 0 {
            close(descriptor)
            return .known(true, source: .fullDiskAccessCanary)
        }
        switch errno {
        case EACCES, EPERM:
            return .known(false, source: .fullDiskAccessCanary)
        case ENOENT:
            return .notPublished(reason: "The Full Disk Access canary does not exist")
        default:
            return .notPublished(reason: "The Full Disk Access canary failed with errno \(errno)")
        }
    }
}
