import Combine
import FathomKit
import Foundation
import UserNotifications

@MainActor
final class DigestNotificationModel: ObservableObject {
    @Published private(set) var state: FathomKit.Measurement<String> =
        .notPublished(reason: "Weekly notifications are disabled")
    @Published private(set) var isWorking = false
    @Published private(set) var isEnabled: Bool
    @Published private(set) var directoryAlertState:
        FathomKit.Measurement<String> = .notPublished(
            reason: "Directory growth alerts are disabled"
        )

    private static let requestID = "com.exhibinaut.fathom.weekly-digest"
    private let center = UNUserNotificationCenter.current()

    init() {
        isEnabled = UserDefaults.standard.bool(forKey: "digest.enabled")
    }

    func setEnabled(_ enabled: Bool, change: FathomKit.Measurement<Int64>) {
        isWorking = true
        Task {
            if enabled {
                do {
                    let granted = try await center.requestAuthorization(options: [.alert, .sound])
                    guard granted else {
                        setStoredEnabled(false)
                        state = .known("Denied in System Settings", source: .userNotificationCenter)
                        isWorking = false
                        return
                    }
                    setStoredEnabled(true)
                    await schedule(change: change)
                } catch {
                    setStoredEnabled(false)
                    state = .notPublished(reason: "Notification permission failed: \(error)")
                }
            } else {
                setStoredEnabled(false)
                center.removePendingNotificationRequests(withIdentifiers: [Self.requestID])
                state = .notPublished(reason: "Weekly notifications are disabled")
            }
            isWorking = false
        }
    }

    private func setStoredEnabled(_ enabled: Bool) {
        isEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "digest.enabled")
    }

    func refresh(change: FathomKit.Measurement<Int64>) {
        guard isEnabled else { return }
        Task { await schedule(change: change) }
    }

    func setDirectoryAlert(
        _ enabled: Bool,
        presentation: StoragePresentation,
        completion: @escaping @MainActor (Bool) -> Void
    ) {
        isWorking = true
        Task {
            if enabled {
                do {
                    let granted = try await center.requestAuthorization(
                        options: [.alert, .sound]
                    )
                    guard granted else {
                        UserDefaults.standard.set(
                            false,
                            forKey: ConsequenceAlertScheduler.directoryPreferenceKey
                        )
                        directoryAlertState = .known(
                            "Denied in System Settings",
                            source: .userNotificationCenter
                        )
                        completion(false)
                        isWorking = false
                        return
                    }
                    UserDefaults.standard.set(
                        true,
                        forKey: ConsequenceAlertScheduler.directoryPreferenceKey
                    )
                    completion(true)
                    directoryAlertState =
                        await ConsequenceAlertScheduler.evaluateDirectoryGrowth(
                            presentation: presentation,
                            center: center
                        )
                } catch {
                    UserDefaults.standard.set(
                        false,
                        forKey: ConsequenceAlertScheduler.directoryPreferenceKey
                    )
                    directoryAlertState = .notPublished(
                        reason: "Notification permission failed: \(error)"
                    )
                    completion(false)
                }
            } else {
                UserDefaults.standard.set(
                    false,
                    forKey: ConsequenceAlertScheduler.directoryPreferenceKey
                )
                ConsequenceAlertScheduler.removePendingDirectoryAlert(
                    scanID: presentation.scanID,
                    center: center
                )
                directoryAlertState = .notPublished(
                    reason: "Directory growth alerts are disabled"
                )
                completion(false)
            }
            isWorking = false
        }
    }

    func refreshDirectoryAlert(presentation: StoragePresentation) {
        guard UserDefaults.standard.bool(
            forKey: ConsequenceAlertScheduler.directoryPreferenceKey
        ) else { return }
        Task {
            directoryAlertState =
                await ConsequenceAlertScheduler.evaluateDirectoryGrowth(
                    presentation: presentation,
                    center: center
                )
        }
    }

    private func schedule(change: FathomKit.Measurement<Int64>) async {
        center.removePendingNotificationRequests(withIdentifiers: [Self.requestID])
        switch WeeklyDigestPlanner.plan(changeInFreeBytes: change, now: Date()) {
        case let .known(plan, _):
            let content = UNMutableNotificationContent()
            content.title = plan.title
            content.body = plan.body
            content.sound = .default
            let components = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute],
                from: plan.fireDate
            )
            let request = UNNotificationRequest(
                identifier: Self.requestID,
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            )
            do {
                try await center.add(request)
                state = .known(
                    "Next: \(plan.fireDate.formatted(date: .abbreviated, time: .shortened))",
                    source: .userNotificationCenter
                )
            } catch {
                state = .notPublished(reason: "Notification scheduling failed: \(error)")
            }
        case let .notPublished(reason): state = .notPublished(reason: reason)
        case .notAttributable: state = .notPublished(reason: "The digest is not attributable")
        }
    }
}
