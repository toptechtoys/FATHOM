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
                FathomEmptySection(
                    title: "Reclaim",
                    subtitle: "No rules evaluated",
                    headline: "Nothing is deleted.",
                    detail: "Everything goes to the Trash, and every rule is one you can read. Reclaim never proposes what a scan has not verified, so the rules stay empty until the first pass completes.",
                    actionTitle: "Run the first Deep Scan",
                    actionCost: "Reads every volume once. Changes nothing.",
                    action: storage.scanSelectedVolume
                )
            case .scanning:
                FathomEmptySection(
                    title: "Reclaim",
                    subtitle: "Building the reference map",
                    headline: "Nothing is proposed until the map is complete.",
                    detail: storage.scanProgressMessage,
                    actionTitle: "Scanning…",
                    isBusy: true,
                    action: {}
                )
            case let .failed(reason):
                FathomEmptySection(
                    title: "Reclaim",
                    subtitle: "The pass did not complete",
                    headline: "No rules have been evaluated.",
                    detail: reason,
                    actionTitle: "Try again",
                    action: storage.reset
                )
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
            FathomEmptySection(
                title: "Reclaim",
                subtitle: "Recipes could not be matched",
                headline: "No rules have been evaluated.",
                detail: reason,
                actionTitle: "Reset",
                action: reclaim.reset
            )
        }
    }

    private func groupList(
        _ groups: [ReclaimGroupPresentation]
    ) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                FathomSectionHeader(
                    title: "Reclaim",
                    subtitle: "Dry run · nothing moved",
                    isLive: false
                )

                FathomReadoutGrid {
                    FathomMeasurementReadout(
                        label: "Available",
                        measurement: total(groups) { $0.freedIfDeleted },
                        note: "Across \(groups.count) validated rules",
                        format: { $0.formatted(.byteCount(style: .file)) }
                    )
                    FathomReadout(
                        label: "Destination",
                        note: "Nothing is deleted"
                    ) {
                        Text("Trash")
                            .font(.fathomDisplay(34))
                            .tracking(-1.02)
                    }
                    FathomReadout(
                        label: "Rules",
                        note: "Every one, in plain text"
                    ) {
                        Text("Readable")
                            .font(.fathomDisplay(34))
                            .tracking(-1.02)
                    }
                }
                .padding(.bottom, 22)

                FathomPanel(label: "Each rule states its cost before it runs") {
                    VStack(spacing: 3) {
                        ForEach(groups) { group in
                            ruleRow(group)
                        }
                    }
                }

                FathomNote(
                    headline: "Nothing is deleted.",
                    detail: "Everything goes to the Trash, and the space is not reclaimed until you empty it. The cost column is stated before anything runs, not after, and a rule we cannot cost honestly is marked report-only rather than offered."
                )
            }
            .padding(EdgeInsets(top: 22, leading: 28, bottom: 40, trailing: 28))
        }
    }

    private func ruleRow(_ group: ReclaimGroupPresentation) -> some View {
        FathomDataRow(
            leading: {
                VStack(alignment: .leading, spacing: 3) {
                    Text(group.recipe.identifier)
                        .font(.fathomSystem(13, weight: .semibold))
                    Text(
                        group.recipe.regenerationCost + " · "
                            + safetyLabel(group.recipe.safetyClass).lowercased()
                    )
                    .font(.fathomSystem(11.5))
                    .foregroundStyle(
                        .white.opacity(FathomSurface.minimumTextOpacity)
                    )
                }
            },
            trailing: {
                HStack(spacing: 14) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(freed(group))
                            .font(.fathomSystem(13, weight: .medium))
                            .monospacedDigit()
                            .foregroundStyle(
                                group.entries.isEmpty
                                    ? .white.opacity(
                                        FathomSurface.minimumTextOpacity
                                    )
                                    : FathomSemantic.freeable
                            )
                        Text(onDisk(group) + " on disk")
                            .font(.fathomSystem(10.5))
                            .foregroundStyle(
                                .white.opacity(
                                    FathomSurface.minimumTextOpacity
                                )
                            )
                    }
                    .frame(width: 150, alignment: .trailing)

                    Button(
                        group.recipe.safetyClass == .reportOnly
                            ? "Review report"
                            : "Dry run"
                    ) {
                        confirmedRiskyPaths = []
                        reclaim.prepare(group)
                    }
                    .buttonStyle(.plain)
                    .font(.fathomSystem(12, weight: .semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(.white.opacity(0.14))
                    .clipShape(RoundedRectangle(cornerRadius: 15))
                    .disabled(group.entries.isEmpty)
                }
            }
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            "\(group.recipe.identifier), frees \(freed(group)), costs \(group.recipe.regenerationCost)"
        )
    }

    private func freed(_ group: ReclaimGroupPresentation) -> String {
        guard case let .known(value, _) = group.freedIfDeleted else {
            return "not published"
        }
        return value.formatted(.byteCount(style: .file))
    }

    private func onDisk(_ group: ReclaimGroupPresentation) -> String {
        guard case let .known(value, _) = group.sizeOnDisk else {
            return "not published"
        }
        return value.formatted(.byteCount(style: .file))
    }

    /// Sums only what every rule published. A total that quietly omits the
    /// rules it could not read is a smaller number wearing the same label.
    private func total(
        _ groups: [ReclaimGroupPresentation],
        _ value: (ReclaimGroupPresentation) -> FathomKit.Measurement<UInt64>
    ) -> FathomKit.Measurement<UInt64> {
        var sum: UInt64 = 0
        var missing = false
        for group in groups {
            if case let .known(bytes, _) = value(group) {
                sum += bytes
            } else {
                missing = true
            }
        }
        guard !missing else {
            return .notAttributable(measured: sum, explained: sum)
        }
        return .known(sum, source: .fts)
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
        case .known:
            // Known and empty: nothing was interrupted, so there is nothing to
            // say. This is the one state that renders no banner, and it is
            // spelled out rather than swallowed by a `default:`.
            EmptyView()
        case let .notAttributable(measured, explained):
            // The journal held entries we could not all account for. On a
            // screen about recovering from an interrupted file-moving
            // operation, that is the most important of the three states and
            // the one a `default:` used to hide.
            HStack(spacing: 12) {
                Image(systemName: "clock.arrow.circlepath")
                Text(unattributedSentence(measured: measured, explained: explained))
                    .font(.fathomSystem(12, weight: .semibold))
                Spacer()
                Button("Review", action: { showsRecovery = true })
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)
            .accessibilityElement(children: .combine)
        }
    }

    /// Says how much of the journal was accounted for, and does not round the
    /// remainder away. Rule 2: an unattributed remainder gets its own words.
    private func unattributedSentence(
        measured: [InterruptedReclaimIntent],
        explained: [InterruptedReclaimIntent]
    ) -> String {
        let missing = max(0, measured.count - explained.count)
        return "\(measured.count) journalled reclaim operation\(measured.count == 1 ? "" : "s"), "
            + "\(explained.count) accounted for. "
            + "\(missing) cannot be attributed and completion is not assumed."
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
