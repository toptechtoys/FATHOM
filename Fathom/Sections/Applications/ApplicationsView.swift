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
                    busySince: storage.scanStartedAt,
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
            .sorted { sortKey($0) > sortKey($1) }
            .prefix(12)
            .map { record in
                FathomTwoNumberTable.Row(
                    name: name(of: record),
                    onDisk: footprint(
                        record.sizeOnDisk,
                        record.leftoverSizeOnDisk
                    ).described(bytes),
                    freed: .cell(
                        footprint(
                            record.freedIfDeleted,
                            record.leftoverFreedIfDeleted
                        ),
                        format: bytes
                    ),
                    annotation: annotation(for: record),
                    isPath: false
                )
            }
    }

    /// Bundle plus leftovers with the three states intact: one unpublished
    /// half makes the pair unpublished, rather than quietly shrinking the
    /// rendered footprint by whatever the missing half was.
    private func footprint(
        _ bundle: FathomKit.Measurement<UInt64>,
        _ leftovers: FathomKit.Measurement<UInt64>
    ) -> FathomKit.Measurement<UInt64> {
        FathomKit.Measurement.sum([bundle, leftovers], source: .fts) { _, _ in
            "Part of this app's footprint was not sized by the completed scan."
        }
    }

    private func name(of record: ApplicationPresentation) -> String {
        if case let .known(name, _) = record.record.name, !name.isEmpty {
            return name
        }
        return record.record.url.lastPathComponent
    }

    /// Names why the two columns differ, when they do — and says when the
    /// difference is unknowable, rather than staying silent about a row
    /// whose leftovers were never sized.
    private func annotation(
        for record: ApplicationPresentation
    ) -> String? {
        switch record.leftoverSizeOnDisk {
        case let .known(leftovers, _):
            guard leftovers > 0 else { return nil }
            return "\(bytes(leftovers)) of it is leftovers"
        case .notPublished:
            return "leftovers were not sized by this scan"
        case .notAttributable:
            return "leftovers only partly attributed"
        }
    }

    private func total(
        _ records: [ApplicationPresentation],
        _ value: (ApplicationPresentation) -> FathomKit.Measurement<UInt64>
    ) -> FathomKit.Measurement<UInt64> {
        FathomKit.Measurement.sum(
            records.map(value),
            source: .fts
        ) { missing, count in
            "\(missing) of \(count) applications did not publish a size."
        }
    }

    /// Ordering only, never rendered: an unpublished half orders as zero, the
    /// pair saturates rather than trapping, and no figure from this reaches
    /// a screen.
    private func sortKey(_ record: ApplicationPresentation) -> UInt64 {
        let (sum, overflow) = sortKey(record.sizeOnDisk)
            .addingReportingOverflow(sortKey(record.leftoverSizeOnDisk))
        return overflow ? .max : sum
    }

    private func sortKey(
        _ measurement: FathomKit.Measurement<UInt64>
    ) -> UInt64 {
        guard case let .known(value, _) = measurement else { return 0 }
        return value
    }

    private func bytes(_ value: UInt64) -> String {
        ByteString.file(value)
    }
}
