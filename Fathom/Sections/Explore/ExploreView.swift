import AppKit
import FathomKit
import SwiftUI

struct ExploreView: View {
    @EnvironmentObject private var model: StorageAppModel
    @StateObject private var modifierKeys = ModifierKeyObserver()

    var body: some View {
        Group {
            switch model.state {
            case .idle:
                FathomEmptySection(
                    title: "Explore",
                    subtitle: "Nothing indexed",
                    headline: "We do not guess at a tree we have not read.",
                    detail: "Every node carries both numbers, and the second one needs physical extents, clone families and snapshot-held ranges mapped first. Until the scan runs there is nothing here to sort.",
                    actionTitle: "Run the first Deep Scan",
                    actionCost: "Reads every volume once. Changes nothing.",
                    action: model.scanSelectedVolume
                )
            case .scanning:
                FathomEmptySection(
                    title: "Explore",
                    subtitle: "Indexing",
                    headline: "Reading every node once.",
                    detail: model.scanProgressMessage,
                    actionTitle: "Scanning…",
                    isBusy: true,
                    busySince: model.scanStartedAt,
                    action: {}
                )
            case let .result(presentation):
                result(presentation)
            case let .failed(reason):
                FathomEmptySection(
                    title: "Explore",
                    subtitle: "The scan did not complete",
                    headline: "There is no tree to explore.",
                    detail: reason,
                    actionTitle: "Try again",
                    action: model.reset
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func result(
        _ presentation: StoragePresentation
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            FathomSectionHeader(
                title: "Explore",
                subtitle: "\(presentation.rows.count) top-level nodes indexed",
                isLive: false
            )

            FathomReadoutGrid {
                FathomMeasurementReadout(
                    label: "On disk",
                    measurement: presentation.sizeOnDisk,
                    note: "Everything the scan traversed",
                    format: { ByteString.file($0) }
                )
                FathomMeasurementReadout(
                    label: "Freed if deleted",
                    measurement: presentation.freedIfDeleted,
                    note: "Sorted by this column, not the first",
                    format: { ByteString.file($0) }
                )
            }
            .padding(.bottom, 22)

            Text("EVERY NODE, BOTH NUMBERS")
                .font(.fathomSystem(9, weight: .semibold))
                .tracking(1.44)
                .foregroundStyle(.white.opacity(FathomSurface.minimumTextOpacity))
                .padding(.bottom, 14)

            HStack {
                Text("NAME")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(
                    modifierKeys.optionHeld
                        ? "FREED IF DELETED"
                        : "ON DISK"
                )
                    .frame(
                        width: 150 * FathomType.scale,
                        alignment: .trailing
                    )
                Text(
                    modifierKeys.optionHeld
                        ? "ON DISK"
                        : "FREED IF DELETED"
                )
                    .frame(
                        width: 180 * FathomType.scale,
                        alignment: .trailing
                    )
            }
            .font(.fathomSystem(9, weight: .semibold))
            .tracking(1.26)
            .foregroundStyle(.white.opacity(FathomSurface.minimumTextOpacity))
            .padding(.horizontal, 13)
            .padding(.bottom, 4)

            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(visibleRows(presentation.rows)) { line in
                        ExploreRow(
                            row: line.row,
                            depth: line.depth,
                            isExpanded: model.expandedDirectoryIDs
                                .contains(line.row.id),
                            isLoading: model.loadingDirectoryIDs
                                .contains(line.row.id),
                            loadFailure:
                                model.childLoadFailures[line.row.id],
                            swapsMeasurements:
                                modifierKeys.optionHeld,
                            toggle: {
                                model.toggleDirectory(line.row)
                            }
                        )
                    }
                }
            }

            Text("Hold ⌥ to swap both number columns. Rows are sorted by freed if deleted — the column nobody else shows you.")
                .font(.fathomSystem(11.5))
                .foregroundStyle(.white.opacity(FathomSurface.minimumTextOpacity))
                .padding(.top, 12)
        }
        .padding(EdgeInsets(top: 22, leading: 28, bottom: 40, trailing: 28))
    }

    private func visibleRows(
        _ roots: [ExplorePresentationRow]
    ) -> [ExploreTreeLine] {
        var result: [ExploreTreeLine] = []
        func append(
            _ rows: [ExplorePresentationRow],
            depth: Int
        ) {
            for row in rows {
                result.append(
                    ExploreTreeLine(row: row, depth: depth)
                )
                if
                    model.expandedDirectoryIDs.contains(row.id),
                    let children = model.childrenByParent[row.id]
                {
                    append(children, depth: depth + 1)
                }
            }
        }
        append(roots, depth: 0)
        return result
    }
}

@MainActor
private final class ModifierKeyObserver: ObservableObject {
    @Published private(set) var optionHeld =
        NSEvent.modifierFlags.contains(.option)
    nonisolated(unsafe) private var monitor: Any?

    init() {
        monitor = NSEvent.addLocalMonitorForEvents(
            matching: .flagsChanged
        ) { [weak self] event in
            self?.optionHeld = event.modifierFlags.contains(.option)
            return event
        }
    }

    deinit {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}

private struct ExploreTreeLine: Identifiable {
    let row: ExplorePresentationRow
    let depth: Int

    var id: Int64 { row.id }
}

private struct ExploreRow: View {
    let row: ExplorePresentationRow
    let depth: Int
    let isExpanded: Bool
    let isLoading: Bool
    let loadFailure: String?
    let swapsMeasurements: Bool
    let toggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 16) {
                HStack(spacing: 8) {
                    if row.kind == .directory {
                        Button(action: toggle) {
                            Group {
                                if isLoading {
                                    ProgressView()
                                        .controlSize(.mini)
                                } else {
                                    Image(
                                        systemName: isExpanded
                                            ? "chevron.down"
                                            : "chevron.right"
                                    )
                                }
                            }
                            .frame(width: 16, height: 16)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(
                            isExpanded
                                ? "Collapse \(row.name)"
                                : "Expand \(row.name)"
                        )
                    } else {
                        Color.clear
                            .frame(width: 16, height: 16)
                    }
                    Image(systemName: symbol)
                        .frame(width: 19)
                        .foregroundStyle(.white.opacity(0.82))
                        // Not hidden: nothing else in the row says whether
                        // this is a folder, a file or a symlink, and a
                        // symlink's two numbers mean something different
                        // from a file's. Written beside `symbol` below so
                        // the glyph and the word cannot drift apart.
                        .accessibilityLabel(kindName)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(row.name.isEmpty ? "/" : row.name)
                            .font(.fathomSystem(13.5, weight: .medium))
                        Text(row.path)
                            .font(.fathomPath(10))
                            .foregroundStyle(.white.opacity(0.82))
                            .lineLimit(1)
                    }
                }
                .padding(.leading, CGFloat(depth) * 18)
                .frame(maxWidth: .infinity, alignment: .leading)

                // The spoken role follows the value through the swap: which
                // column a number sits in is invisible to VoiceOver, and the
                // two-number distinction is the product.
                MeasurementValueView(
                    measurement: swapsMeasurements
                        ? row.freedIfDeleted
                        : row.sizeOnDisk,
                    spokenRole: swapsMeasurements
                        ? "freed if deleted"
                        : "on disk"
                )
                    // "not attributable" at fathomData(15) x 1.45 = 21.75pt
                    // measures 147.6pt in a 150pt column. The two columns and
                    // the two header cells above must all take the factor or
                    // the Option swap changes the layout under the reader.
                    .frame(width: 150 * FathomType.scale, alignment: .trailing)
                MeasurementValueView(
                    measurement: swapsMeasurements
                        ? row.sizeOnDisk
                        : row.freedIfDeleted,
                    spokenRole: swapsMeasurements
                        ? "on disk"
                        : "freed if deleted"
                )
                    .frame(width: 180 * FathomType.scale, alignment: .trailing)
            }
            if let loadFailure {
                Text(loadFailure)
                    .font(.fathomSystem(10.5))
                    .foregroundStyle(.white.opacity(0.82))
                    .padding(.leading, CGFloat(depth) * 18 + 43)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(FathomSurface.card)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .contain)
    }

    private var symbol: String {
        switch row.kind {
        case .directory:
            "folder.fill"
        case .regularFile:
            "doc.fill"
        case .symbolicLink:
            "link"
        case .other:
            "questionmark.square"
        }
    }

    /// What `symbol` draws, in words. The same switch, deliberately adjacent:
    /// a glyph and its spoken name that live apart drift apart.
    private var kindName: String {
        switch row.kind {
        case .directory:
            "folder"
        case .regularFile:
            "file"
        case .symbolicLink:
            "symbolic link"
        case .other:
            "item of unknown kind"
        }
    }
}
