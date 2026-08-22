import FathomKit
import SwiftUI

struct CloudView: View {
    @EnvironmentObject private var model: CloudAppModel
    @State private var confirmedPlan: CloudEvictionPlan?

    var body: some View {
        Group {
            switch model.state {
            case .idle:
                FathomEmptySection(
                    title: "Cloud",
                    subtitle: "iCloud Drive not read yet",
                    headline: "Finder shows the claim, not the occupancy.",
                    detail: "iCloud reports what a folder contains. This reads what is actually on this disk, what is only in the cloud, and what evicting the local copies would return. The claim and the truth usually differ.",
                    actionTitle: "Read iCloud occupancy",
                    actionCost: "Reads status only. File contents are never opened.",
                    action: model.scan
                )
            case .scanning:
                FathomEmptySection(
                    title: "Cloud",
                    subtitle: "Reading",
                    headline: "Reading iCloud status.",
                    detail: "Without opening file contents, which would download every evicted file it touched.",
                    actionTitle: "Reading…",
                    isBusy: true,
                    action: {}
                )
            case let .result(records):
                recordsView(records)
            case let .review(plan):
                review(plan)
            case .executing:
                FathomEmptySection(
                    title: "Cloud",
                    subtitle: "Evicting",
                    headline: "Evicting the reviewed local copies.",
                    detail: "The files stay in iCloud and download again when opened.",
                    actionTitle: "Evicting…",
                    isBusy: true,
                    action: {}
                )
            case let .report(outcomes):
                report(outcomes)
            case let .failed(reason):
                FathomEmptySection(
                    title: "Cloud",
                    subtitle: "iCloud status could not be read",
                    headline: "Nothing here is measured yet.",
                    detail: reason,
                    actionTitle: "Try again",
                    action: model.reset
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .confirmationDialog(
            "Evict reviewed local copies?",
            isPresented: Binding(
                get: { confirmedPlan != nil },
                set: { if !$0 { confirmedPlan = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let plan = confirmedPlan {
                Button("Evict \(freeable(plan))") {
                    confirmedPlan = nil
                    model.execute(plan)
                }
            }
            Button("Cancel", role: .cancel) { confirmedPlan = nil }
        } message: {
            Text("The files remain in iCloud and download again when opened. Network transfer cost is not published.")
        }
    }

    private func recordsView(_ records: [CloudItemRecord]) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                FathomSectionHeader(
                    title: "Cloud",
                    subtitle: "iCloud Drive · \(records.count) items",
                    isLive: false
                )

                FathomReadoutGrid {
                    FathomMeasurementReadout(
                        label: "Really on disk",
                        measurement: total(records) { $0.sizeOnDisk },
                        note: "What these items actually occupy here",
                        format: bytes
                    )
                    FathomMeasurementReadout(
                        label: "Freed by evicting",
                        measurement: total(records) { $0.freedIfEvicted },
                        note: "The files stay in iCloud",
                        format: bytes
                    )
                    FathomMeasurementReadout(
                        label: "Items",
                        measurement: FathomKit.Measurement<Int>.known(
                            records.count,
                            source: .fts
                        ),
                        note: "Read without opening contents",
                        format: { $0.formatted() }
                    )
                }
                .padding(.bottom, 22)

                FathomPanel(label: "Largest local copies") {
                    FathomTwoNumberTable(
                        rows: rows(records),
                        hint: "An item that frees nothing is pinned, downloading, or already evicted — the annotation says which."
                    )
                }

                FathomAction(
                    title: "Prepare eviction dry run",
                    cost: "Nothing is evicted until you review the list.",
                    action: { model.prepare(records) }
                )

                FathomNote(
                    headline: "Evicting is not deleting.",
                    detail: "The file stays in iCloud and comes back when you open it. What you lose is offline access, and the wait. The network cost of downloading it again is not something we can publish, so we do not pretend to."
                )
                .padding(.top, 26)
            }
            .padding(EdgeInsets(top: 22, leading: 28, bottom: 40, trailing: 28))
        }
    }

    private func review(_ plan: CloudEvictionPlan) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                FathomSectionHeader(
                    title: "Eviction dry run",
                    subtitle: "Nothing has been evicted",
                    isLive: false
                )

                FathomReadoutGrid {
                    FathomMeasurementReadout(
                        label: "Would free",
                        measurement: plan.knownFreeableBytes.map {
                            FathomKit.Measurement<UInt64>.known($0, source: .fts)
                        } ?? .notPublished(
                            reason: "No item in this plan published a freeable size."
                        ),
                        note: "If you proceed",
                        format: bytes
                    )
                    FathomMeasurementReadout(
                        label: "Items",
                        measurement: FathomKit.Measurement<Int>.known(
                            plan.items.count,
                            source: .fts
                        ),
                        note: "Reviewed, not yet evicted",
                        format: { $0.formatted() }
                    )
                }
                .padding(.bottom, 22)

                FathomPanel(label: "Every item in the plan") {
                    FathomTwoNumberTable(rows: rows(plan.items))
                }

                HStack(spacing: 14) {
                    FathomAction(
                        title: "Review cost and evict",
                        cost: "Files stay in iCloud and download again when opened.",
                        action: { confirmedPlan = plan }
                    )
                    .disabled(plan.knownFreeableBytes == nil || plan.items.isEmpty)
                    FathomAction(
                        title: "Back",
                        isProminent: false,
                        action: model.reset
                    )
                }
            }
            .padding(EdgeInsets(top: 22, leading: 28, bottom: 40, trailing: 28))
        }
    }

    private func report(_ outcomes: [CloudEvictionOutcome]) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                FathomSectionHeader(
                    title: "Eviction report",
                    subtitle: "\(outcomes.count(where: { $0.evicted })) of \(outcomes.count) evicted",
                    isLive: false
                )

                FathomPanel(label: "What happened to each item") {
                    VStack(spacing: 3) {
                        ForEach(Array(outcomes.enumerated()), id: \.offset) { _, outcome in
                            FathomDataRow.simple(
                                outcome.path,
                                value: outcome.evicted ? "evicted" : "not evicted",
                                valueColor: outcome.evicted
                                    ? FathomSemantic.freeable
                                    : FathomSemantic.caution,
                                annotation: outcome.detail,
                                isPath: true,
                                isEmphasised: !outcome.evicted
                            )
                        }
                    }
                }

                FathomAction(title: "Done", action: model.reset)
            }
            .padding(EdgeInsets(top: 22, leading: 28, bottom: 40, trailing: 28))
        }
    }

    private func rows(_ items: [CloudItemRecord]) -> [FathomTwoNumberTable.Row] {
        items
            .sorted { known($0.sizeOnDisk) > known($1.sizeOnDisk) }
            .prefix(12)
            .map { item in
                let freed = known(item.freedIfEvicted)
                return FathomTwoNumberTable.Row(
                    name: item.url.path,
                    onDisk: bytes(known(item.sizeOnDisk)),
                    freed: freed == 0 ? nil : bytes(freed),
                    annotation: annotation(for: item)
                )
            }
    }

    /// Why an item frees nothing, when it frees nothing. macOS publishes the
    /// downloading status, so the row can say which case it is instead of
    /// leaving a zero to be interpreted.
    private func annotation(for item: CloudItemRecord) -> String? {
        guard known(item.freedIfEvicted) == 0 else { return nil }
        if case let .known(status, _) = item.downloadingStatus, !status.isEmpty {
            return status
        }
        return "already evicted"
    }

    private func total(
        _ records: [CloudItemRecord],
        _ value: (CloudItemRecord) -> FathomKit.Measurement<UInt64>
    ) -> FathomKit.Measurement<UInt64> {
        let sum = records.reduce(UInt64(0)) { $0 + known(value($1)) }
        let missing = records.count { record in
            if case .known = value(record) { return false }
            return true
        }
        guard missing == 0 else {
            return .notAttributable(measured: sum, explained: sum)
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

    private func freeable(_ plan: CloudEvictionPlan) -> String {
        plan.knownFreeableBytes.map(bytes) ?? "not published"
    }
}
