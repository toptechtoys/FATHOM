import Dispatch
import Foundation

/// What the menu bar widget draws, decided where it can be tested.
///
/// This used to live in `FathomBar/FathomBarSampler.swift`, beside the
/// `NSStatusItem` that renders it, and nothing in the repository exercised it:
/// both schemes declare `testTargets: []`, so 428 lines of widget — including
/// every rule below about what a gap renders as — were checked by the compiler
/// and by nothing else. `AGENTS.md` is explicit that presentation logic making
/// a claim belongs in FathomKit, and every branch here makes one: what a
/// not-published reading looks like, which sensor counts as the hottest, and
/// what a caller is allowed to pair a self-measurement with.
public struct FathomBarPresentation: Sendable, Equatable {
    /// The status item's title. Short forms, joined by two spaces.
    public let title: String
    /// What VoiceOver says instead of reading "— GB" as an em dash.
    public let accessibilityLabel: String
    /// How many items this actually put in the menu bar.
    ///
    /// The idle-cost budget in rule 8 is stated for four items, so the figure
    /// the widget publishes about itself has to carry the count that was on
    /// screen while it was measured. Reading the count back out of the
    /// configuration at publish time answers a subtly different question — what
    /// is configured now — so the count travels with the thing that was drawn.
    public let itemCount: Int

    public init(
        configuration: FathomBarConfiguration,
        capacity: VolumeCapacitySnapshot,
        cpu: CPULoadSnapshot,
        network: NetworkSnapshot,
        temperatures: Measurement<[TemperatureSensorReading]>
    ) {
        let free = Self.freeText(capacity)
        let heat = Self.temperatureText(temperatures)
        let down = Self.networkText(network)
        let load = Self.cpuText(cpu)
        var items: [(short: String, long: String)] = []
        if configuration.showsFreeSpace { items.append(free) }
        if configuration.showsHottestSensor { items.append(heat) }
        if configuration.showsNetworkThroughput { items.append(down) }
        if configuration.showsCPULoad { items.append(load) }
        title = items.isEmpty ? "FATHOM" : items.map(\.short)
            .joined(separator: "  ")
        accessibilityLabel = items.isEmpty
            ? "FATHOM menu bar"
            : items.map(\.long)
            .joined(separator: ", ")
        itemCount = items.count
    }

    private init(title: String, accessibilityLabel: String, itemCount: Int) {
        self.title = title
        self.accessibilityLabel = accessibilityLabel
        self.itemCount = itemCount
    }

    /// Before the first sample lands there is nothing measured to show.
    ///
    /// The widget is on screen from the moment it launches, so this state is
    /// real and reachable, and it is a not-published state like any other: an
    /// em dash, and a spoken label that says why rather than reading the dash.
    public static let notYetSampled = FathomBarPresentation(
        title: "FATHOM —",
        accessibilityLabel: "FATHOM measurements not yet published",
        itemCount: 0
    )

    private static func freeText(
        _ snapshot: VolumeCapacitySnapshot
    ) -> (short: String, long: String) {
        switch snapshot.actuallyFree {
        case let .known(value, _):
            let text = ByteString.file(value)
            return (text, "\(text) actually free")
        case .notPublished:
            return ("— GB", "free space not published")
        case .notAttributable:
            return ("— GB", "free space not attributable")
        }
    }

    private static func temperatureText(
        _ measurement: Measurement<[TemperatureSensorReading]>
    ) -> (short: String, long: String) {
        guard case let .known(readings, _) = measurement else {
            return ("—°", "hottest sensor not published")
        }
        let values = readings.compactMap { reading -> Double? in
            guard case let .known(value, _) = reading.celsius else { return nil }
            return value
        }
        guard let hottest = values.max() else {
            return ("—°", "hottest sensor not published")
        }
        let text = hottest.formatted(.number.precision(.fractionLength(0)))
        return ("\(text)°", "hottest sensor \(text) degrees Celsius")
    }

    private static func networkText(
        _ snapshot: NetworkSnapshot
    ) -> (short: String, long: String) {
        guard case let .known(interfaces, _) = snapshot.interfaces else {
            return ("—/s", "network throughput not published")
        }
        let known = interfaces.compactMap { interface -> Double? in
            guard case let .known(value, _) = interface.receivedBytesPerSecond
            else {
                return nil
            }
            return value
        }
        guard !known.isEmpty else {
            return ("—/s", "network throughput not published")
        }
        let total = known.reduce(0, +)
        let text = ByteString.file(rounding: total)
        return ("↓\(text)/s", "download \(text) per second")
    }

    private static func cpuText(
        _ snapshot: CPULoadSnapshot
    ) -> (short: String, long: String) {
        guard case let .known(value, _) = snapshot.aggregateBusy else {
            return ("—%", "CPU load not published")
        }
        let text = (value * 100).formatted(
            .number.precision(.fractionLength(0))
        )
        return ("\(text)%", "CPU load \(text) percent")
    }

    /// The two lines and the spoken label for one draw of the status item.
    ///
    /// Only the `NSAttributedString` construction stays in the widget; which
    /// words appear, and in what order VoiceOver hears them, is decided here.
    public func buttonContent(
        pressure: FathomBarMemoryPressure? = nil
    ) -> FathomBarButtonContent {
        guard let pressure else {
            return FathomBarButtonContent(
                title: title,
                pressureLine: nil,
                accessibilityLabel: accessibilityLabel
            )
        }
        return FathomBarButtonContent(
            title: title,
            pressureLine: pressure.label,
            accessibilityLabel: accessibilityLabel + ", "
                + pressure.label.lowercased()
        )
    }
}

/// One draw of the status item button, as text.
public struct FathomBarButtonContent: Sendable, Equatable {
    public let title: String
    /// The second line, drawn under the title, or nil when there is no
    /// pressure event to report. Rule 7 forbids manufactured urgency, so this
    /// is nil for `.normal` — a machine under no memory pressure gets no badge.
    public let pressureLine: String?
    public let accessibilityLabel: String

    public init(
        title: String,
        pressureLine: String?,
        accessibilityLabel: String
    ) {
        self.title = title
        self.pressureLine = pressureLine
        self.accessibilityLabel = accessibilityLabel
    }
}

/// The memory pressure level the widget is willing to draw.
///
/// `DispatchSource.MemoryPressureEvent` is an option set and a single event can
/// carry more than one bit, so the order of these tests is load-bearing: a
/// reading that is both warning and critical is critical. The mapping lives
/// here rather than inside the event handler so that precedence is a testable
/// fact and not a line of AppKit nobody can reach.
public enum FathomBarMemoryPressure: Sendable, Equatable, CaseIterable {
    case warning
    case critical

    public var label: String {
        switch self {
        case .warning: "MEMORY WARNING"
        case .critical: "MEMORY CRITICAL"
        }
    }

    public static func from(
        events: DispatchSource.MemoryPressureEvent
    ) -> FathomBarMemoryPressure? {
        if events.contains(.critical) { return .critical }
        if events.contains(.warning) { return .warning }
        return nil
    }
}
