import Foundation

/// How often a broken FSEvents window is allowed to cost a full Deep Scan.
public struct ContinuityRescanGovernor: Sendable {
    public enum Decision: Equatable, Sendable {
        case rescanNow
        case held(until: Date)
    }

    /// Thirty minutes, from three times the ten minutes a Deep Scan took end
    /// to end on 1 September 2026. The floor has to outlast a scan or the next
    /// trigger lands before the last one finished, which is the loop this type
    /// exists to break. It also caps continuity rescans at two an hour.
    public static let defaultFloor: TimeInterval = 30 * 60

    private let floor: TimeInterval
    private var lastRescanEndedAt: Date?
    private var heldUntil: Date?

    public init(floor: TimeInterval = defaultFloor) {
        self.floor = floor
    }

    public mutating func request(now: Date) -> Decision {
        guard let lastRescanEndedAt else { return .rescanNow }
        let due = lastRescanEndedAt.addingTimeInterval(floor)
        guard now < due else {
            heldUntil = nil
            return .rescanNow
        }
        heldUntil = due
        return .held(until: due)
    }

    public mutating func releaseIfDue(now: Date) -> Decision? {
        guard let heldUntil, now >= heldUntil else { return nil }
        self.heldUntil = nil
        return .rescanNow
    }

    /// Closes a scan out. Any finished scan pays whatever a hold was owed,
    /// including one the owner started by hand, so the hold clears here too.
    public mutating func recordRescanEnded(at moment: Date) {
        lastRescanEndedAt = moment
        heldUntil = nil
    }
}
