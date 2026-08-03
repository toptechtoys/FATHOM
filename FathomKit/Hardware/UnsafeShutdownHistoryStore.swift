import Foundation

public struct UnsafeShutdownWindow: Sendable, Codable, Equatable {
    public let count: UInt64
    public let start: Date
    public let end: Date

    public init(count: UInt64, start: Date, end: Date) {
        self.count = count
        self.start = start
        self.end = end
    }
}

public actor UnsafeShutdownHistoryStore {
    private struct Observation: Sendable, Codable, Equatable {
        let timestamp: Date
        let count: UInt64
    }

    private let url: URL
    private let calendar: Calendar

    public init(url: URL, calendar: Calendar = .current) {
        self.url = url
        self.calendar = calendar
    }

    public func record(
        _ measurement: Measurement<UInt64>,
        now: Date = Date()
    ) -> Measurement<UnsafeShutdownWindow> {
        let current: UInt64
        switch measurement {
        case let .known(value, _): current = value
        case let .notPublished(reason): return .notPublished(reason: reason)
        case .notAttributable:
            return .notPublished(reason: "The unsafe-shutdown counter is not attributable")
        }

        var observations = load().filter {
            $0.timestamp <= now &&
                $0.timestamp >= now.addingTimeInterval(-120 * 24 * 60 * 60)
        }
        observations.append(Observation(timestamp: now, count: current))
        observations.sort { $0.timestamp < $1.timestamp }
        do {
            try save(observations)
        } catch {
            return .notPublished(reason: "Unsafe-shutdown history could not persist: \(error)")
        }

        guard let threshold = calendar.date(byAdding: .day, value: -30, to: now),
              let baseline = observations.last(where: { $0.timestamp <= threshold }) else {
            return .notPublished(reason: "Thirty days of unsafe-shutdown history are required")
        }
        guard current >= baseline.count else {
            return .notPublished(reason: "The unsafe-shutdown counter reset")
        }
        return .known(
            UnsafeShutdownWindow(
                count: current - baseline.count,
                start: baseline.timestamp,
                end: now
            ),
            source: .persistedSMARTCounterDelta
        )
    }

    private func load() -> [Observation] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([Observation].self, from: data)) ?? []
    }

    private func save(_ observations: [Observation]) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try JSONEncoder().encode(observations).write(to: url, options: .atomic)
    }
}
