import Foundation

public struct InterruptedReclaimIntent: Sendable, Equatable, Identifiable {
    public let recipeIdentifier: String
    public let recipeVersion: UInt64
    public let path: String
    public let recordedAt: Date?

    public var id: String {
        "\(recipeIdentifier):\(recipeVersion):\(path)"
    }

    public init(
        recipeIdentifier: String,
        recipeVersion: UInt64,
        path: String,
        recordedAt: Date?
    ) {
        self.recipeIdentifier = recipeIdentifier
        self.recipeVersion = recipeVersion
        self.path = path
        self.recordedAt = recordedAt
    }
}

public enum ReclaimJournalRecoveryReader {
    public static func read(
        at url: URL
    ) -> Measurement<[InterruptedReclaimIntent]> {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return .known([], source: .reclaimJournalReplay)
        }
        do {
            let data = try Data(contentsOf: url)
            var pending: [String: InterruptedReclaimIntent] = [:]
            for (lineIndex, line) in data.split(
                separator: 0x0A,
                omittingEmptySubsequences: true
            ).enumerated() {
                guard let object = try JSONSerialization.jsonObject(
                    with: Data(line)
                ) as? [String: Any] else {
                    return .notPublished(
                        reason: "Reclaim journal line \(lineIndex + 1) is not an object"
                    )
                }
                guard let phase = object["phase"] as? String else {
                    continue
                }
                guard phase == "intent" || phase == "outcome",
                      let path = object["path"] as? String,
                      let recipe = object["recipe"] as? [String: Any],
                      let identifier = recipe["identifier"] as? String,
                      let versionNumber = recipe["version"] as? NSNumber
                else {
                    return .notPublished(
                        reason: "Reclaim journal line \(lineIndex + 1) lacks an intent/outcome identity"
                    )
                }
                let version = versionNumber.uint64Value
                let key = "\(identifier):\(version):\(path)"
                if phase == "intent" {
                    let timestamp = (object["timestamp"] as? NSNumber).map {
                        Date(timeIntervalSinceReferenceDate: $0.doubleValue)
                    }
                    pending[key] = InterruptedReclaimIntent(
                        recipeIdentifier: identifier,
                        recipeVersion: version,
                        path: path,
                        recordedAt: timestamp
                    )
                } else {
                    pending[key] = nil
                }
            }
            return .known(
                pending.values.sorted {
                    if $0.recordedAt != $1.recordedAt {
                        return ($0.recordedAt ?? .distantPast) <
                            ($1.recordedAt ?? .distantPast)
                    }
                    return $0.path < $1.path
                },
                source: .reclaimJournalReplay
            )
        } catch {
            return .notPublished(
                reason: "The reclaim journal cannot be replayed: \(error)"
            )
        }
    }
}
