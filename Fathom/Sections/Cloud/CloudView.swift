import FathomKit
import SwiftUI

struct CloudView: View {
    @EnvironmentObject private var model: CloudAppModel
    @State private var confirmedPlan: CloudEvictionPlan?

    var body: some View {
        Group {
            switch model.state {
            case .idle:
                FathomPoster(
                    title: "Cloud",
                    message: "What is really on this disk, what is only in iCloud, and what eviction would free.",
                    symbol: "icloud",
                    world: .cloud,
                    shape: AnyShape(Circle()),
                    isScanning: false,
                    action: model.scan
                )
            case .scanning:
                ProgressView("Reading iCloud status without opening file contents…")
            case let .result(records):
                recordsView(records)
            case let .review(plan):
                review(plan)
            case .executing:
                ProgressView("Evicting reviewed local copies…")
            case let .report(outcomes):
                report(outcomes)
            case let .failed(reason):
                VStack(spacing: 14) {
                    Text("not published").font(.fathomDisplay(32))
                    Text(reason).textSelection(.enabled)
                    Button("Try again", action: model.reset)
                }
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
            LazyVStack(alignment: .leading, spacing: 10) {
                Text("Cloud").font(.fathomDisplay(34))
                ForEach(records) { item in
                    HardwareResultCard(label: item.url.path) {
                        HStack(spacing: 28) {
                            metric("ON DISK", item.sizeOnDisk)
                            metric("FREED IF EVICTED", item.freedIfEvicted)
                            HardwareMeasurementView(
                                measurement: item.downloadingStatus,
                                format: { $0 }
                            )
                        }
                    }
                }
                Button("Prepare eviction dry run") {
                    model.prepare(records)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(34)
        }
    }

    private func review(_ plan: CloudEvictionPlan) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Eviction dry run").font(.fathomDisplay(34))
            Text("Would free \(freeable(plan)). Files remain in iCloud.")
            List(plan.items) { item in
                HStack {
                    Text(item.url.path).font(.fathomPath(11))
                    Spacer()
                    HardwareMeasurementView(
                        measurement: item.sizeOnDisk,
                        format: hardwareByteString
                    )
                    HardwareMeasurementView(
                        measurement: item.freedIfEvicted,
                        format: hardwareByteString
                    )
                }
            }
            HStack {
                Button("Back", action: model.reset)
                Button("Review cost and evict") { confirmedPlan = plan }
                    .buttonStyle(.borderedProminent)
                    .disabled(plan.knownFreeableBytes == nil || plan.items.isEmpty)
            }
        }
        .padding(34)
    }

    private func report(_ outcomes: [CloudEvictionOutcome]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Eviction report").font(.fathomDisplay(34))
            ForEach(Array(outcomes.enumerated()), id: \.offset) { _, outcome in
                Text("\(outcome.evicted ? "evicted" : "not evicted"): \(outcome.path) — \(outcome.detail)")
                    .font(.fathomPath(11))
            }
            Button("Done", action: model.reset)
        }
        .padding(34)
    }

    private func metric(
        _ label: String,
        _ measurement: FathomKit.Measurement<UInt64>
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.fathomSystem(9, weight: .bold))
            HardwareMeasurementView(
                measurement: measurement,
                format: hardwareByteString
            )
        }
    }

    private func freeable(_ plan: CloudEvictionPlan) -> String {
        plan.knownFreeableBytes.map(hardwareByteString) ?? "not published"
    }
}
