import FathomKit
import SwiftUI

struct ReclaimView: View {
    @EnvironmentObject private var storage: StorageAppModel
    @EnvironmentObject private var reclaim: ReclaimAppModel
    @State private var pendingExecution: ReclaimDryRun?
    @State private var confirmedRiskyPaths: Set<String> = []
    @State private var showsRecovery = false

    var body: some View {
        Group {
            switch storage.state {
            case .idle:
                FathomPoster(
                    title: "Reclaim",
                    message: "Nothing is deleted. Everything goes to the Trash, and every rule is one you can read.",
                    symbol: "trash",
                    world: .reclaim,
                    shape: AnyShape(RoundedRectangle(cornerRadius: 48)),
                    isScanning: false,
                    action: storage.scanSelectedVolume
                )
            case .scanning:
                ProgressView("Building the whole-volume reference map…")
                    .controlSize(.large)
            case let .failed(reason):
                Text("not published — \(reason)")
            case let .result(presentation):
                reclaimContent(presentation)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .safeAreaInset(edge: .top) {
            recoveryBanner
        }
        .confirmationDialog(
            confirmationTitle,
            isPresented: Binding(
                get: { pendingExecution != nil },
                set: { if !$0 { pendingExecution = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let dryRun = pendingExecution {
                Button("Move exact reviewed items to Trash") {
                    pendingExecution = nil
                    reclaim.execute(dryRun)
                }
            }
            Button("Cancel", role: .cancel) { pendingExecution = nil }
        } message: {
            if let dryRun = pendingExecution {
                Text("Frees \(freeableText(dryRun.manifest)); costs \(dryRun.manifest.recipe.regenerationCost). Space is not reclaimed until Trash is emptied.")
            }
        }
        .sheet(isPresented: $showsRecovery) {
            recoverySheet
        }
    }

    @ViewBuilder
    private func reclaimContent(_ presentation: StoragePresentation) -> some View {
        switch reclaim.state {
        case .idle:
            ProgressView().onAppear { reclaim.load(from: presentation) }
        case .loading:
            ProgressView("Matching validated recipes…")
        case let .result(groups):
            groupList(groups)
        case let .review(dryRun):
            review(dryRun)
        case .executing:
            ProgressView("Moving reviewed items to Trash…")
        case let .report(report):
            executionReport(report)
        case let .failed(reason):
            VStack(spacing: 14) {
                Text("not published").font(.fathomData(18))
                Text(reason).textSelection(.enabled)
                Button("Reset", action: reclaim.reset)
            }
        }
    }

    private func groupList(
        _ groups: [ReclaimGroupPresentation]
    ) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Reclaim").font(.fathomDisplay(34))
                ForEach(groups) { group in
                    HardwareResultCard(label: group.recipe.identifier) {
                        HStack(spacing: 28) {
                            labeled("ON DISK", group.sizeOnDisk)
                            labeled("FREED IF MOVED", group.freedIfDeleted)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("COST").font(.fathomSystem(10, weight: .bold))
                                Text(group.recipe.regenerationCost)
                                    .font(.fathomSystem(12))
                                Text(safetyLabel(group.recipe.safetyClass))
                                    .font(.fathomSystem(10, weight: .bold))
                                    .foregroundStyle(.white.opacity(0.82))
                            }
                            Spacer()
                            Button(
                                group.recipe.safetyClass == .reportOnly
                                    ? "Review report"
                                    : "Dry run"
                            ) {
                                confirmedRiskyPaths = []
                                reclaim.prepare(group)
                            }
                                .disabled(group.entries.isEmpty)
                        }
                    }
                }
            }
            .padding(34)
        }
    }

    private func labeled(
        _ label: String,
        _ value: FathomKit.Measurement<UInt64>
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.fathomSystem(10, weight: .bold))
            HardwareMeasurementView(measurement: value, format: hardwareByteString)
        }
    }

    private func review(_ dryRun: ReclaimDryRun) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Dry run").font(.fathomDisplay(34))
            Text("Cost: \(dryRun.manifest.recipe.regenerationCost)")
            List(dryRun.manifest.items) { item in
                VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        Text(item.path).font(.fathomPath(11))
                        Spacer()
                        HardwareMeasurementView(
                            measurement: item.sizeOnDisk,
                            format: hardwareByteString
                        )
                        HardwareMeasurementView(
                            measurement: item.freedIfDeleted,
                            format: hardwareByteString
                        )
                    }
                    if dryRun.manifest.recipe.safetyClass ==
                        .requiresPerItemConfirmation {
                        Toggle(
                            "I reviewed this exact path and its stated cost",
                            isOn: Binding(
                                get: {
                                    confirmedRiskyPaths.contains(item.path)
                                },
                                set: { confirmed in
                                    if confirmed {
                                        confirmedRiskyPaths.insert(item.path)
                                    } else {
                                        confirmedRiskyPaths.remove(item.path)
                                    }
                                }
                            )
                        )
                        .toggleStyle(.checkbox)
                    }
                }
            }
            if !dryRun.refusals.isEmpty {
                Text("\(dryRun.refusals.count) items refused by the safety policy")
            }
            HStack {
                Button("Back", action: reclaim.reset)
                if dryRun.manifest.recipe.safetyClass == .reportOnly {
                    Text("Report only — this recipe can never move files")
                        .font(.fathomSystem(12, weight: .semibold))
                } else {
                    Button("Review cost and move to Trash") {
                        pendingExecution = dryRun.confirming(
                            itemPaths: confirmedRiskyPaths
                        )
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(
                        dryRun.manifest.knownFreeableBytes == nil ||
                        (dryRun.manifest.recipe.safetyClass ==
                            .requiresPerItemConfirmation &&
                         confirmedRiskyPaths.isEmpty)
                    )
                }
            }
        }
        .padding(34)
    }

    private func executionReport(_ report: ReclaimExecutionReport) -> some View {
        VStack(spacing: 18) {
            Text("Trash move report").font(.fathomDisplay(34))
            ForEach(Array(report.items.enumerated()), id: \.offset) { _, item in
                Text("\(item.outcome.rawValue): \(item.path) — \(item.detail)")
                    .font(.fathomPath(11))
            }
            Button("Done", action: reclaim.reset)
        }
        .padding(34)
    }

    private var confirmationTitle: String {
        guard let dryRun = pendingExecution else { return "Move to Trash?" }
        return "Frees \(freeableText(dryRun.manifest)); costs \(dryRun.manifest.recipe.regenerationCost)"
    }

    private func freeableText(_ manifest: ReclaimManifest) -> String {
        manifest.knownFreeableBytes.map(hardwareByteString) ?? "not published"
    }

    @ViewBuilder
    private var recoveryBanner: some View {
        switch reclaim.recovery {
        case let .known(intents, source) where !intents.isEmpty:
            let sentence = "\(intents.count) reclaim operation\(intents.count == 1 ? "" : "s") stopped after journaling intent. Completion is not assumed."
            HStack(spacing: 12) {
                Image(systemName: "clock.arrow.circlepath")
                Text(sentence)
                .font(.fathomSystem(12, weight: .semibold))
                .accessibilityLabel("\(sentence) Source \(source.rawValue)")
                Spacer()
                Button("Review", action: { showsRecovery = true })
            }
            .help(source.rawValue)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)
        case let .notPublished(reason):
            Text("Journal recovery not published — \(reason)")
                .font(.fathomSystem(12))
                .padding(10)
                .background(.ultraThinMaterial)
        default:
            EmptyView()
        }
    }

    private var recoverySheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Interrupted reclaim operation")
                .font(.fathomDisplay(28))
            Text("An intent was durably recorded, but no matching outcome was. FATHOM cannot honestly infer whether the item reached the Trash. Inspect the exact paths and the Trash before taking another action.")
                .font(.fathomSystem(12.5))
                .foregroundStyle(.white.opacity(0.82))
            if case let .known(intents, _) = reclaim.recovery {
                List(intents) { intent in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(intent.path).font(.fathomPath(11))
                        Text(
                            "Recipe \(intent.recipeIdentifier) v\(intent.recipeVersion) · \(intent.recordedAt?.formatted(date: .abbreviated, time: .shortened) ?? "time not published")"
                        )
                        .font(.fathomSystem(10.5))
                        .foregroundStyle(.white.opacity(0.82))
                    }
                }
            }
            HStack {
                Button("Check journal again", action: reclaim.refreshRecovery)
                Spacer()
                Button("Done", action: { showsRecovery = false })
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(minWidth: 640, minHeight: 400)
    }

    private func safetyLabel(_ value: ReclaimSafetyClass) -> String {
        switch value {
        case .safe: "SAFE · GROUP REVIEW"
        case .requiresPerItemConfirmation: "PER-ITEM CONFIRMATION REQUIRED"
        case .reportOnly: "REPORT ONLY · NO ACTION"
        }
    }
}
