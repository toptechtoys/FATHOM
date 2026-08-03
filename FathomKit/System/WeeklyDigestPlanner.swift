import Foundation

public struct WeeklyDigestNotificationPlan: Sendable, Equatable {
    public let fireDate: Date
    public let title: String
    public let body: String

    public init(fireDate: Date, title: String, body: String) {
        self.fireDate = fireDate
        self.title = title
        self.body = body
    }
}

public enum WeeklyDigestPlanner {
    public static func plan(
        changeInFreeBytes: Measurement<Int64>,
        now: Date,
        calendar: Calendar = .current
    ) -> Measurement<WeeklyDigestNotificationPlan> {
        let delta: Int64
        switch changeInFreeBytes {
        case let .known(value, _): delta = value
        case let .notPublished(reason): return .notPublished(reason: reason)
        case .notAttributable:
            return .notPublished(reason: "The weekly change is not attributable")
        }
        guard delta != 0 else {
            return .notPublished(reason: "The week is quiet; no notification is scheduled")
        }
        var components = DateComponents()
        components.weekday = 1
        components.hour = 9
        components.minute = 0
        components.second = 0
        guard let fireDate = calendar.nextDate(
            after: now,
            matching: components,
            matchingPolicy: .nextTime,
            direction: .forward
        ) else {
            return .notPublished(reason: "The next Sunday at 09:00 is not published")
        }
        let bytes = UInt64(delta.magnitude)
        let amount = ByteCountFormatter.string(
            fromByteCount: Int64(clamping: bytes),
            countStyle: .file
        )
        let finding = delta < 0
            ? "Your disk is \(amount) fuller than the earlier completed scan."
            : "Your disk has \(amount) more free space than the earlier completed scan."
        return .known(
            WeeklyDigestNotificationPlan(
                fireDate: fireDate,
                title: "FATHOM weekly digest",
                body: "\(finding) Open FATHOM to inspect the evidence."
            ),
            source: .persistedStorageHistoryDelta
        )
    }
}
