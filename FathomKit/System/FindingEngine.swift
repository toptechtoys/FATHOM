import Foundation

/// Something worth a look, with the reason it is worth looking at.
///
/// Home is allowed to say nothing is wrong, and it says so by this engine
/// returning an empty array. That is the expected result on a healthy Mac, not
/// a failure to find anything — rule 7 forbids manufacturing urgency, and
/// padding this list to look busy is exactly that.
public struct Finding: Sendable, Equatable, Identifiable {
    /// Which claim the finding is making. Never the only carrier of meaning:
    /// every finding also states it in words.
    public enum Kind: Sendable, Equatable {
        /// This space actually comes back.
        case freeable
        /// Real, but conditional — it needs care or it costs something.
        case conditional
        /// Big, and deleting it returns nothing. The product's signature.
        case freesNothing
        /// Worth knowing, no action implied.
        case informational
    }

    /// Where the evidence is. The app maps this to a section.
    public enum Subject: Sendable, Equatable {
        case storage, reclaim, explore, endurance, maintenance, deepScan
    }

    public let id: String
    public let kind: Kind
    /// States the fact. "Xcode left 48.2 GB behind."
    public let title: String
    /// One sentence saying why it is worth a look.
    public let detail: String
    /// The number, formatted.
    public let value: String
    public let subject: Subject
    /// What the ranking used. Bytes, or a count promoted to bytes-equivalent
    /// so one comparison orders the whole list.
    public let weight: UInt64

    public init(
        id: String,
        kind: Kind,
        title: String,
        detail: String,
        value: String,
        subject: Subject,
        weight: UInt64
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.detail = detail
        self.value = value
        self.subject = subject
        self.weight = weight
    }
}

/// What the engine needs. Deliberately the measured values rather than a
/// presentation type, so this stays in FathomKit and stays testable.
public struct FindingInput: Sendable {
    public struct Entry: Sendable {
        public let name: String
        public let path: String
        public let sizeOnDisk: Measurement<UInt64>
        public let freedIfDeleted: Measurement<UInt64>

        public init(
            name: String,
            path: String,
            sizeOnDisk: Measurement<UInt64>,
            freedIfDeleted: Measurement<UInt64>
        ) {
            self.name = name
            self.path = path
            self.sizeOnDisk = sizeOnDisk
            self.freedIfDeleted = freedIfDeleted
        }
    }

    public let entries: [Entry]
    public let actuallyFree: Measurement<UInt64>
    public let finderAvailable: Measurement<UInt64>
    public let purgeable: Measurement<UInt64>
    public let snapshotCount: Measurement<Int>
    /// Items the scan could not inspect. A partial result says so.
    public let uninspectedCount: Int

    public init(
        entries: [Entry],
        actuallyFree: Measurement<UInt64>,
        finderAvailable: Measurement<UInt64>,
        purgeable: Measurement<UInt64>,
        snapshotCount: Measurement<Int>,
        uninspectedCount: Int
    ) {
        self.entries = entries
        self.actuallyFree = actuallyFree
        self.finderAvailable = finderAvailable
        self.purgeable = purgeable
        self.snapshotCount = snapshotCount
        self.uninspectedCount = uninspectedCount
    }
}

/// Turns measurements into things worth a look.
///
/// Every finding traces to a value the caller measured. The engine adds no
/// numbers of its own — what it adds is a threshold, which is a judgement about
/// what deserves attention, and those are named constants here rather than
/// magic numbers buried in a condition, because a threshold is the one place
/// this could quietly become a nag.
public enum FindingEngine {
    /// Below this, freeable space is not worth interrupting anyone about.
    /// Five gigabytes is roughly a large app or an afternoon of build output —
    /// enough that acting on it changes what you can do next.
    public static let freeableThreshold: UInt64 = 5 * 1_000_000_000

    /// A large item that returns nothing is the product's signature finding, so
    /// the bar is lower: the point is the surprise, not the size.
    public static let freesNothingThreshold: UInt64 = 2 * 1_000_000_000

    /// Finder over-reporting by less than this is noise, not a finding.
    public static let finderGapThreshold: UInt64 = 5 * 1_000_000_000

    /// The design shows four. More than that stops being a summary.
    public static let maximumFindings = 4

    public static func findings(for input: FindingInput) -> [Finding] {
        var found: [Finding] = []
        found.append(contentsOf: freeableFindings(input))
        found.append(contentsOf: freesNothingFindings(input))
        if let gap = finderGapFinding(input) { found.append(gap) }
        if let snapshots = snapshotFinding(input) { found.append(snapshots) }
        if let partial = partialScanFinding(input) { found.append(partial) }

        // Heaviest first, then by id so the order cannot wobble between runs
        // on equal weights. A list that reshuffles looks like new news.
        return Array(
            found
                .sorted { ($0.weight, $1.id) > ($1.weight, $0.id) }
                .prefix(maximumFindings)
        )
    }

    private static func freeableFindings(_ input: FindingInput) -> [Finding] {
        input.entries.compactMap { entry in
            guard case let .known(freed, _) = entry.freedIfDeleted,
                  freed >= freeableThreshold
            else { return nil }
            return Finding(
                id: "freeable:\(entry.path)",
                kind: .freeable,
                title: "\(entry.name) holds \(bytes(freed)) you can have back",
                detail: "All of it frees. The second number and the first agree here, which is not always true.",
                value: bytes(freed),
                subject: .reclaim,
                weight: freed
            )
        }
    }

    /// Large on disk, returns nothing when deleted.
    ///
    /// This is the finding no other tool makes, so it says why rather than just
    /// reporting the zero — a bare zero reads as a bug.
    private static func freesNothingFindings(_ input: FindingInput) -> [Finding] {
        input.entries.compactMap { entry in
            guard case let .known(size, _) = entry.sizeOnDisk,
                  case let .known(freed, _) = entry.freedIfDeleted,
                  size >= freesNothingThreshold,
                  freed == 0
            else { return nil }
            return Finding(
                id: "freesnothing:\(entry.path)",
                kind: .freesNothing,
                title: "\(entry.name) holds \(bytes(size)) and frees none of it",
                detail: "Clones, snapshots or sparse allocation mean its size on disk is not what deletion returns. Removing it would buy you nothing.",
                value: "0 bytes",
                subject: .explore,
                // Ranked by what it would appear to free, because that is the
                // size of the misunderstanding being corrected.
                weight: size
            )
        }
    }

    private static func finderGapFinding(_ input: FindingInput) -> Finding? {
        guard case let .known(actual, _) = input.actuallyFree,
              case let .known(finder, _) = input.finderAvailable,
              finder > actual,
              finder - actual >= finderGapThreshold
        else { return nil }
        let gap = finder - actual
        return Finding(
            id: "findergap",
            kind: .conditional,
            title: "Finder claims \(bytes(gap)) more than a write would get",
            detail: "It counts purgeable space macOS may not be able to release. The honest figure is what a write would actually see.",
            value: bytes(gap),
            subject: .storage,
            weight: gap
        )
    }

    private static func snapshotFinding(_ input: FindingInput) -> Finding? {
        guard case let .known(count, _) = input.snapshotCount, count > 0
        else { return nil }
        let held: String
        var weight: UInt64 = 1_000_000_000
        if case let .known(purgeable, _) = input.purgeable, purgeable > 0 {
            held = bytes(purgeable)
            weight = purgeable
        } else {
            held = "an amount macOS does not publish"
        }
        return Finding(
            id: "snapshots",
            kind: .conditional,
            title: "\(count) local snapshot\(count == 1 ? "" : "s") holding \(held)",
            detail: "Deleting files frees nothing until the snapshots referencing them go. macOS lets these grow considerably before it reclaims them.",
            value: "\(count)",
            subject: .maintenance,
            weight: weight
        )
    }

    /// A partial scan is worth saying out loud, because every other number on
    /// the screen is a floor rather than a total.
    private static func partialScanFinding(_ input: FindingInput) -> Finding? {
        guard input.uninspectedCount > 0 else { return nil }
        return Finding(
            id: "partialscan",
            kind: .informational,
            title: "\(input.uninspectedCount) items could not be inspected",
            detail: "Every total on this screen is therefore a floor, not a sum. The scan says so rather than rounding up.",
            value: "\(input.uninspectedCount)",
            subject: .deepScan,
            // Ranked above routine freeable space: knowing the numbers are
            // incomplete changes how you read all of them.
            weight: UInt64.max
        )
    }

    private static func bytes(_ value: UInt64) -> String {
        value.formatted(.byteCount(style: .file))
    }
}
