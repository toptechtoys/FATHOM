import FathomKit
import SwiftUI

struct StorageView: View {
    @EnvironmentObject private var model: StorageAppModel
    let openExplore: () -> Void

    var body: some View {
        Group {
            switch model.state {
            case .idle:
                poster(isScanning: false)
            case .scanning:
                poster(isScanning: true)
            case let .result(presentation):
                result(presentation)
            case let .failed(reason):
                failure(reason)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func poster(isScanning: Bool) -> some View {
        FathomPoster(
            title: "Storage",
            message: isScanning
                ? model.scanProgressMessage
                : "The true number, not the one Finder tells you. And what you would actually get back.",
            symbol: "externaldrive.fill",
            world: .storage,
            shape: AnyShape(Ellipse()),
            isScanning: isScanning,
            action: model.scanSelectedVolume
        )
    }

    private func result(
        _ presentation: StoragePresentation
    ) -> some View {
        ScrollView {
            VStack(spacing: 26) {
                Text("Storage")
                    .font(.fathomDisplay(38))
                    .tracking(-1.2)

                Text(presentation.volumePath)
                    .font(.fathomPath(12))
                    .foregroundStyle(.white.opacity(0.82))

                HardwareMeasurementView(
                    measurement: model.changeMonitoring,
                    format: { $0 }
                )
                .font(.fathomSystem(11.5, weight: .medium))

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 280), spacing: 18)],
                    spacing: 18
                ) {
                    SummaryCard(label: "ACTUALLY FREE, RIGHT NOW", measurement: presentation.actuallyFree)
                    SummaryCard(label: "RECLAIMABLE", measurement: presentation.freedIfDeleted)
                }
                .frame(maxWidth: 760)

                DiskThroughputPanel()
                    .frame(maxWidth: 760)

                capacityNote(presentation)
                    .frame(maxWidth: 760)

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 280), spacing: 18)],
                    spacing: 18
                ) {
                    SummaryCard(
                        label: "SCANNED ON DISK",
                        measurement: presentation.sizeOnDisk,
                        compact: true
                    )
                    SummaryCard(
                        label: "PURGEABLE INCLUDED BY FINDER",
                        measurement: presentation.purgeable,
                        compact: true
                    )
                }
                .frame(maxWidth: 760)

                snapshotNote(
                    presentation.snapshotInventory,
                    coverage: presentation.snapshotCoverage
                )
                    .frame(maxWidth: 760)

                if presentation.issueCount > 0 {
                    Text(
                        "\(presentation.issueCount) items could not be inspected. This result is partial."
                    )
                    .font(.fathomSystem(12))
                    .foregroundStyle(Color(hex: 0xFCD98A))
                }

                HStack(spacing: 12) {
                    Button("Scan again", action: model.reset)
                    Button("Explore the tree", action: openExplore)
                        .buttonStyle(.borderedProminent)
                        .tint(.white)
                        .foregroundStyle(Color(hex: 0x04263A))
                }
                .controlSize(.large)
            }
            .padding(40)
        }
    }

    @ViewBuilder
    private func capacityNote(
        _ presentation: StoragePresentation
    ) -> some View {
        switch (
            presentation.actuallyFree,
            presentation.finderAvailable
        ) {
        case let (.known(actual, _), .known(finder, _)):
            if finder == actual {
                Text(
                    "Finder and the important-usage capacity API currently agree."
                )
            } else {
                Text(
                    "Finder reports \(formattedBytes(finder)); macOS says only \(formattedBytes(actual)) is available for an important write right now."
                )
            }
        case let (.notPublished(reason), _),
             let (_, .notPublished(reason)):
            Text("Capacity comparison is not published. \(reason)")
        case (.notAttributable, _), (_, .notAttributable):
            Text("Capacity comparison is not attributable.")
        }
    }

    @ViewBuilder
    private func snapshotNote(
        _ inventory: FathomKit.Measurement<[LocalSnapshot]>,
        coverage: FathomKit.Measurement<[String]>
    ) -> some View {
        switch inventory {
        case let .known(snapshots, _):
            if snapshots.isEmpty {
                Text("No local snapshots currently hold old extents.")
            } else {
                switch coverage {
                case .known:
                    Text(
                        "\(snapshots.count) local snapshots were mapped. Freeable values exclude every extent they still reference."
                    )
                case let .notPublished(reason):
                    Text(
                        "\(snapshots.count) local snapshots exist. Their held extents are not published. \(reason)"
                    )
                case .notAttributable:
                    Text(
                        "\(snapshots.count) local snapshots exist. Their held extents are not attributable."
                    )
                }
            }
        case let .notPublished(reason):
            Text("Snapshot inventory is not published. \(reason)")
        case .notAttributable:
            Text("Snapshot inventory is not attributable.")
        }
    }

    private func failure(_ reason: String) -> some View {
        VStack(spacing: 18) {
            Text("The scan did not complete")
                .font(.fathomDisplay(34))
            Text(reason)
                .font(.fathomSystem(13))
                .foregroundStyle(.white.opacity(0.82))
                .textSelection(.enabled)
            Button("Try again", action: model.reset)
        }
        .padding(40)
    }
}

private struct DiskThroughputPanel: View {
    @State private var measurement:
        FathomKit.Measurement<DiskThroughputSnapshot> = .notPublished(
            reason: "A disk counter sample has not run"
        )

    var body: some View {
        HardwareResultCard(label: "LIVE DISK THROUGHPUT") {
            switch measurement {
            case let .known(snapshot, source):
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 180), spacing: 18)],
                    alignment: .leading,
                    spacing: 12
                ) {
                    rate("READ", snapshot.readBytesPerSecond)
                    rate("WRITE", snapshot.writtenBytesPerSecond)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("PUBLISHING DRIVERS")
                            .font(.fathomSystem(10, weight: .bold))
                            .foregroundStyle(.white.opacity(0.82))
                        Text(snapshot.driverCount.formatted())
                            .font(.fathomData(16, weight: .semibold))
                    }
                }
                .help(source.rawValue)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(
                    "\(snapshot.driverCount) publishing drivers, source \(source.rawValue)"
                )
            case let .notPublished(reason):
                Text("not published")
                    .font(.fathomData(16, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.82))
                    .help(reason)
                    .accessibilityLabel("Disk throughput not published. \(reason)")
            case let .notAttributable(measured, explained):
                Text("not attributable")
                    .help("Measured \(measured.bytesRead) read bytes; explained \(explained.bytesRead)")
            }
        }
        .task {
            let sampler = DiskThroughputSampler()
            _ = await sampler.sample()
            do {
                try await Task.sleep(for: .milliseconds(250))
            } catch {
                return
            }
            while !Task.isCancelled {
                measurement = await sampler.sample()
                do {
                    try await Task.sleep(for: .seconds(1))
                } catch {
                    return
                }
            }
        }
    }

    private func rate(
        _ label: String,
        _ measurement: FathomKit.Measurement<Double>
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.fathomSystem(10, weight: .bold))
                .foregroundStyle(.white.opacity(0.82))
            HardwareMeasurementView(
                measurement: measurement,
                format: { "\(hardwareByteString($0))/s" }
            )
        }
    }
}

private struct SummaryCard: View {
    let label: String
    let measurement: FathomKit.Measurement<UInt64>
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(label)
                .font(.fathomSystem(10.5, weight: .bold))
                .tracking(1.05)
                .foregroundStyle(.white.opacity(0.82))
            MeasurementValueView(
                measurement: measurement,
                prominent: !compact
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(24)
        .background(FathomSurface.card)
        .background(.ultraThinMaterial.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .stroke(.white.opacity(0.20), lineWidth: 0.5)
        }
    }
}

private func formattedBytes(_ value: UInt64) -> String {
    value.formatted(
        .byteCount(
            style: .file,
            allowedUnits: [.gb, .mb],
            spellsOutZero: false,
            includesActualByteCount: false
        )
    )
}
