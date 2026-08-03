import Foundation

public struct VolumeEncryptionReader: Sendable {
    public init() {}

    public func read(volumeURL: URL) -> Measurement<Bool> {
        do {
            let values = try volumeURL.resourceValues(
                forKeys: [.volumeIsEncryptedKey]
            )
            guard let encrypted = values.volumeIsEncrypted else {
                return .notPublished(
                    reason: "Foundation did not publish volume encryption state"
                )
            }
            return .known(encrypted, source: .volumeIsEncrypted)
        } catch {
            return .notPublished(
                reason: "Volume encryption state failed: \(error)"
            )
        }
    }
}
