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
                poster(isScanning: false)
            case .scanning:
                poster(isScanning: true)
            case let .result(presentation):
                result(presentation)
            case let .failed(reason):
                Text(reason)
                    .textSelection(.enabled)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func poster(isScanning: Bool) -> some View {
        FathomPoster(
            title: "Explore",
            message: "Every node, both numbers, sorted by the one nobody else shows you.",
            symbol: "square.grid.2x2",
            world: .explore,
            shape: AnyShape(
                RoundedRectangle(cornerRadius: 48)
            ),
            isScanning: isScanning,
            action: model.scanSelectedVolume
        )
    }

    private func result(
        _ presentation: StoragePresentation
    ) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Explore")
                    .font(.fathomDisplay(34))
                    .tracking(-1)
                Text("Every row keeps on-disk and freeable bytes separate.")
                    .font(.fathomSystem(13))
                    .foregroundStyle(.white.opacity(0.82))
            }

            HStack {
                Text("NAME")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(
                    modifierKeys.optionHeld
                        ? "FREED IF DELETED"
                        : "ON DISK"
                )
                    .frame(width: 150, alignment: .trailing)
                Text(
                    modifierKeys.optionHeld
                        ? "ON DISK"
                        : "FREED IF DELETED"
                )
                    .frame(width: 180, alignment: .trailing)
            }
            .font(.fathomSystem(10, weight: .bold))
            .tracking(0.9)
            .foregroundStyle(.white.opacity(0.82))
            .padding(.horizontal, 16)

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

            Text(
                "Hold ⌥ to swap both number columns. Rows are sorted by freed if deleted."
            )
            .font(.fathomSystem(11))
            .foregroundStyle(.white.opacity(0.82))
        }
        .padding(34)
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

                MeasurementValueView(
                    measurement: swapsMeasurements
                        ? row.freedIfDeleted
                        : row.sizeOnDisk
                )
                    .frame(width: 150, alignment: .trailing)
                MeasurementValueView(
                    measurement: swapsMeasurements
                        ? row.sizeOnDisk
                        : row.freedIfDeleted
                )
                    .frame(width: 180, alignment: .trailing)
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
        .background(.white.opacity(0.07))
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
}
