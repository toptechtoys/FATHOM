import FathomKit
import SwiftUI

struct ApplicationsView: View {
    @EnvironmentObject private var storage: StorageAppModel
    @EnvironmentObject private var applications: ApplicationsAppModel

    var body: some View {
        Group {
            switch storage.state {
            case .idle:
                FathomEmptySection(
                    title: "Applications",
                    subtitle: "Nothing counted yet",
                    headline: "An app is bigger than its bundle.",
                    detail: "Footprints are computed during the first scan, including what each app left in the six other places macOS lets it write. Leftovers are matched by exact bundle identifier, never by guessing at a name prefix.",
                    actionTitle: "Run the first Deep Scan",
                    actionCost: "Reads every volume once. Changes nothing.",
                    action: storage.scanSelectedVolume
                )
            case .scanning:
                FathomEmptySection(
                    title: "Applications",
                    subtitle: "Reading",
                    headline: "Accounting for bundles and leftovers.",
                    detail: storage.scanProgressMessage,
                    actionTitle: "Scanning…",
                    isBusy: true,
                    action: {}
                )
            case let .failed(reason):
                FathomEmptySection(
                    title: "Applications",
                    subtitle: "The pass did not complete",
                    headline: "Nothing here is measured yet.",
                    detail: reason,
                    actionTitle: "Try again",
                    action: storage.reset
                )
            case let .result(presentation):
                content(presentation)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func content(_ presentation: StoragePresentation) -> some View {
        switch applications.state {
        case .idle:
            ProgressView().onAppear { applications.load(from: presentation) }
        case .loading:
            ProgressView("Reading application metadata…")
        case let .failed(reason):
            FathomEmptySection(
                title: "Applications",
                subtitle: "Metadata could not be read",
                headline: "The bundles are there; the accounting is not.",
                detail: reason
            )
        case let .result(records):
            list(records)
        }
    }

    private func list(_ records: [ApplicationPresentation]) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                FathomSectionHeader(
                    title: "Applications",
                    subtitle: "\(records.count) applications",
                    isLive: false
                )

                FathomReadoutGrid {
                    FathomMeasurementReadout(
                        label: "Applications",
                        measurement: FathomKit.Measurement<Int>.known(
                            records.count,
                            source: .fts
                        ),
                        note: "Bundles found on this volume",
                        format: { $0.formatted() }
                    )
                    FathomMeasurementReadout(
                        label: "Footprint",
                        measurement: total(records) { $0.sizeOnDisk },
                        note: "The bundles themselves",
                        format: bytes
                    )
                    FathomMeasurementReadout(
                        label: "Leftovers",
                        measurement: total(records) { $0.leftoverSizeOnDisk },
                        note: "Matched by exact bundle identifier",
                        format: bytes
                    )
                }
                .padding(.bottom, 22)

                FathomPanel(label: "Largest, counting all six places") {
                    FathomTwoNumberTable(
                        rows: rows(records),
                        hint: "The second column is what deletion actually returns. An app whose leftovers free nothing says so."
                    )
                }

                FathomNote(
                    headline: "Leftovers are matched, never guessed.",
                    detail: "A folder is only credited to an app when its bundle identifier matches exactly. Prefix matching would sweep up a second app with a similar name, and the whole point of the second column is that you can act on it."
                )
            }
            .padding(EdgeInsets(top: 22, leading: 28, bottom: 40, trailing: 28))
        }
    }

    /// The twelve largest, by what the bundle and its leftovers occupy.
    ///
    /// Capped because a list of every application is not a finding. The note
    /// says the list is largest-first so nobody reads it as complete.
    private func rows(
        _ records: [ApplicationPresentation]
    ) -> [FathomTwoNumberTable.Row] {
        records
            .map { record -> (ApplicationPresentation, UInt64) in
                (record, known(record.sizeOnDisk) + known(record.leftoverSizeOnDisk))
            }
            .sorted { $0.1 > $1.1 }
            .prefix(12)
            .map { record, _ in
                let freed = known(record.freedIfDeleted)
                    + known(record.leftoverFreedIfDeleted)
                let onDisk = known(record.sizeOnDisk)
                    + known(record.leftoverSizeOnDisk)
                return FathomTwoNumberTable.Row(
                    name: name(of: record),
                    onDisk: bytes(onDisk),
                    freed: freed == 0 ? nil : bytes(freed),
                    annotation: annotation(for: record),
                    isPath: false
                )
            }
    }

    private func name(of record: ApplicationPresentation) -> String {
        if case let .known(name, _) = record.record.name, !name.isEmpty {
            return name
        }
        return record.record.url.lastPathComponent
    }

    /// Names why the two columns differ, when they do.
    private func annotation(
        for record: ApplicationPresentation
    ) -> String? {
        let leftovers = known(record.leftoverSizeOnDisk)
        guard leftovers > 0 else { return nil }
        return "\(bytes(leftovers)) of it is leftovers"
    }

    private func total(
        _ records: [ApplicationPresentation],
        _ value: (ApplicationPresentation) -> FathomKit.Measurement<UInt64>
    ) -> FathomKit.Measurement<UInt64> {
        let sum = records.reduce(UInt64(0)) { $0 + known(value($1)) }
        let missing = records.count { record in
            if case .known = value(record) { return false }
            return true
        }
        guard missing == 0 else {
            // A total that quietly omits the rows it could not read is a
            // smaller number wearing the same label.
            return .notAttributable(
                measured: sum,
                explained: sum
            )
        }
        return .known(sum, source: .fts)
    }

    private func known(_ measurement: FathomKit.Measurement<UInt64>) -> UInt64 {
        guard case let .known(value, _) = measurement else { return 0 }
        return value
    }

    private func bytes(_ value: UInt64) -> String {
        value.formatted(.byteCount(style: .file))
    }
}
