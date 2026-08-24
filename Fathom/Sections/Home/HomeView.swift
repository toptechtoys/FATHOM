import FathomKit
import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var storage: StorageAppModel
    @EnvironmentObject private var hardware: HardwareAppModel
    @EnvironmentObject private var system: SystemMonitorModel
    let openStorage: () -> Void
    let openSSDHealth: () -> Void
    var open: (AppSection) -> Void = { _ in }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                FathomSectionHeader(
                    title: "Home",
                    subtitle: "All systems sampled",
                    isLive: false
                )

                FathomReadoutGrid {
                    FathomMeasurementReadout(
                        label: "Actually free",
                        measurement: actuallyFree,
                        note: "The number a write would really see",
                        format: bytes
                    )
                    FathomMeasurementReadout(
                        label: "Freed if selected",
                        measurement: freedIfDeleted,
                        note: "What deletion would actually return",
                        format: bytes
                    )
                    FathomMeasurementReadout(
                        label: "Root volume",
                        measurement: encryption,
                        note: "Foundation reports encryption, not the named FileVault policy",
                        format: { $0 }
                    )
                    FathomMeasurementReadout(
                        label: "NVMe warning",
                        measurement: criticalWarning,
                        note: "The controller's own flag",
                        format: { $0 }
                    )
                }
                .padding(.bottom, 22)

                FathomPanel(label: "Every section, one number each") {
                    FathomSectionGrid(entries: entries, open: open)
                }

                if !findings.isEmpty {
                    FathomPanel(label: "Worth a look") {
                        FathomFeed(findings: findings) { subject in
                            open(section(for: subject))
                        }
                    }
                }

                FathomNote(
                    headline: statementHeadline,
                    detail: statementDetail
                )
            }
            .padding(EdgeInsets(top: 22, leading: 28, bottom: 40, trailing: 28))
        }
        .onAppear {
            if case .idle = hardware.state { hardware.readSSD() }
        }
    }

    /// One line per section that already has a number worth showing.
    ///
    /// A section whose value is not published yet is left out rather than shown
    /// as a dash: this grid is a set of findings, and a grid of dashes is not
    /// a summary of anything.
    private var entries: [FathomSectionGrid.Entry] {
        var result: [FathomSectionGrid.Entry] = []
        if case let .known(value, _) = actuallyFree {
            result.append(
                .init(
                    section: .storage,
                    value: bytes(value),
                    detail: "actually free"
                )
            )
        }
        if case let .known(value, _) = freedIfDeleted, value > 0 {
            result.append(
                .init(
                    section: .reclaim,
                    value: bytes(value),
                    detail: "freeable, dry run"
                )
            )
        }
        if case let .result(snapshot) = hardware.state,
           case let .known(used, _) = snapshot.percentageUsed {
            result.append(
                .init(
                    section: .endurance,
                    value: "\(used)%",
                    detail: "endurance consumed"
                )
            )
        }
        if let cpu = system.cpuHistory.latest {
            result.append(
                .init(
                    section: .cpu,
                    value: cpu.formatted(.number.precision(.fractionLength(0)))
                        + "%",
                    detail: "load across all cores"
                )
            )
        }
        return result
    }

    /// Nothing is wrong is a valid answer, so an empty list renders no panel
    /// at all rather than an empty one headed "worth a look".
    private var findings: [Finding] {
        guard case let .result(presentation) = storage.state else { return [] }
        return FindingEngine.findings(
            for: FindingInput(
                entries: presentation.rows.map {
                    FindingInput.Entry(
                        name: $0.name,
                        path: $0.path,
                        sizeOnDisk: $0.sizeOnDisk,
                        freedIfDeleted: $0.freedIfDeleted
                    )
                },
                actuallyFree: presentation.actuallyFree,
                finderAvailable: presentation.finderAvailable,
                purgeable: presentation.purgeable,
                snapshotCount: presentation.snapshotInventory.map { $0.count },
                uninspectedCount: presentation.issueCount
            )
        )
    }

    private func section(for subject: Finding.Subject) -> AppSection {
        switch subject {
        case .storage: .storage
        case .reclaim: .reclaim
        case .explore: .explore
        case .endurance: .endurance
        case .maintenance: .maintenance
        case .deepScan: .deepScan
        }
    }

    private var actuallyFree: FathomKit.Measurement<UInt64> {
        guard case let .result(presentation) = storage.state else {
            return .notPublished(
                reason: "No completed scan yet. Run a Deep Scan and this becomes the real number."
            )
        }
        return presentation.actuallyFree
    }

    private var freedIfDeleted: FathomKit.Measurement<UInt64> {
        guard case let .result(presentation) = storage.state else {
            return .notPublished(
                reason: "Nothing has been evaluated. Reclaim never proposes what a scan has not verified."
            )
        }
        return presentation.freedIfDeleted
    }

    private var encryption: FathomKit.Measurement<String> {
        VolumeEncryptionReader()
            .read(volumeURL: URL(fileURLWithPath: "/"))
            .map { $0 ? "Encrypted" : "Not encrypted" }
    }

    private var criticalWarning: FathomKit.Measurement<String> {
        guard case let .result(snapshot) = hardware.state else {
            return .notPublished(reason: "The SMART log has not been read yet.")
        }
        return snapshot.criticalWarning.map {
            $0 == 0 ? "None" : "0x\(String($0, radix: 16))"
        }
    }

    /// The Home screen is allowed to say nothing is wrong, and is not allowed
    /// to say anything broader than what it can prove.
    private var statementHeadline: String {
        guard case let .result(snapshot) = hardware.state,
              case let .known(warning, _) = snapshot.criticalWarning,
              warning == 0
        else {
            return "There is no overall score, and there will not be one."
        }
        return findings.isEmpty
            ? "Nothing is wrong."
            : "Nothing is wrong. \(findings.count == 1 ? "One thing is" : "\(findings.count) things are") worth a look."
    }

    private var statementDetail: String {
        guard case let .result(snapshot) = hardware.state,
              case let .known(warning, _) = snapshot.criticalWarning,
              warning == 0
        else {
            return "Every value keeps its source and its state, and a value macOS does not publish says so rather than being filled in. No number here is combined with another to produce a grade."
        }
        let count = findings.count
        guard count > 0 else {
            return "The SSD controller reports no critical warning, and nothing on this volume is worth interrupting you about. FATHOM makes no broader health claim than that. A full disk is not an emergency."
        }
        return "The SSD controller reports no critical warning, and FATHOM makes no broader health claim from that fact. \(count == 1 ? "One thing is" : "\(count) things are") worth a look above, and each one links to the screen that produced it. A full disk is not an emergency."
    }

    private func bytes(_ value: UInt64) -> String {
        ByteString.file(value)
    }
}
