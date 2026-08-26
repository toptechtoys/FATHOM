import FathomKit
import Foundation
import UserNotifications

@MainActor
enum ConsequenceAlertScheduler {
    static let directoryPreferenceKey = "alerts.directory20GB"
    private static let directoryRequestPrefix =
        "com.exhibinaut.fathom.directory-growth."
    private static let lastDirectoryNotificationScanKey =
        "alerts.directory20GB.lastNotifiedScanID"

    static func evaluateDirectoryGrowth(
        presentation: StoragePresentation,
        center: UNUserNotificationCenter = .current()
    ) async -> FathomKit.Measurement<String> {
        do {
            let index = try StorageIndex(url: presentation.indexURL)
            let result: FathomKit.Measurement<[DirectoryGrowthFinding]>
            do {
                result = try await index.directoryGrowthFindings(
                    scanID: presentation.scanID
                )
                await index.close()
            } catch {
                // close() is what checkpoints the write-ahead log, so a throw
                // between open and close used to leave the log to
                // non-deterministic ARC release.
                await index.close()
                throw error
            }
            switch result {
            case let .known(findings, source):
                guard let largest = findings.first else {
                    return .known(
                        "No directory crossed the 20 GB daily-growth consequence",
                        source: source
                    )
                }
                if UserDefaults.standard.object(
                    forKey: lastDirectoryNotificationScanKey
                ) != nil,
                   UserDefaults.standard.integer(
                    forKey: lastDirectoryNotificationScanKey
                   ) == Int(presentation.scanID) {
                    return .known(
                        "Evaluated: this scan's consequence was already notified",
                        source: source
                    )
                }
                let content = UNMutableNotificationContent()
                content.title = "FATHOM directory growth"
                content.body = findings.count == 1
                    ? "A directory gained \(hardwareByteString(largest.growthBytes)) within 24 hours. Open FATHOM for the evidence."
                    : "\(findings.count) directories crossed 20 GB growth within 24 hours; the largest gained \(hardwareByteString(largest.growthBytes)). Open FATHOM for the evidence."
                content.sound = .default
                try await center.add(
                    UNNotificationRequest(
                        identifier: directoryRequestPrefix
                            + String(presentation.scanID),
                        content: content,
                        trigger: nil
                    )
                )
                UserDefaults.standard.set(
                    presentation.scanID,
                    forKey: lastDirectoryNotificationScanKey
                )
                return .known(
                    "Evaluated: \(findings.count) consequence\(findings.count == 1 ? "" : "s")",
                    source: source
                )
            case let .notPublished(reason):
                return .notPublished(reason: reason)
            case .notAttributable:
                return .notPublished(
                    reason: "Directory growth is not attributable"
                )
            }
        } catch {
            return .notPublished(
                reason: "Directory growth evaluation failed: \(error)"
            )
        }
    }

    static func removePendingDirectoryAlert(
        scanID: Int64,
        center: UNUserNotificationCenter = .current()
    ) {
        center.removePendingNotificationRequests(
            withIdentifiers: [directoryRequestPrefix + String(scanID)]
        )
    }
}
