import FathomKit
import SwiftUI

struct CommandPaletteView: View {
    @EnvironmentObject private var storage: StorageAppModel
    @Environment(\.dismiss) private var dismiss
    @Binding var selection: AppSection
    @StateObject private var model = CommandPaletteModel()
    @State private var query = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField(
                    "Search sections, paths, ‘over 1 GB’, ‘changed this week’, or ‘clones’",
                    text: $query
                )
                .textFieldStyle(.plain)
                .font(.fathomSystem(16))
                .focused($isFocused)
                Button {
                    dismiss()
                } label: {
                    Text("esc").font(.fathomSystem(10, design: .monospaced))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
            }
            .padding(16)

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    sectionMatches
                    fileMatches
                }
                .padding(12)
            }
            .frame(minHeight: 280, maxHeight: 430)
        }
        .frame(width: 680)
        .background(.regularMaterial)
        .onAppear { isFocused = true }
        .onChange(of: query) { _, value in
            model.search(value, storage: storagePresentation)
        }
    }

    private var storagePresentation: StoragePresentation? {
        if case let .result(presentation) = storage.state { return presentation }
        return nil
    }

    @ViewBuilder
    private var sectionMatches: some View {
        let matches = query.isEmpty ? AppSection.allCases : AppSection.allCases.filter {
            $0.rawValue.localizedCaseInsensitiveContains(query)
        }
        if !matches.isEmpty {
            Text("SECTIONS")
                .font(.fathomSystem(10, weight: .bold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
            ForEach(matches.prefix(query.isEmpty ? 6 : 20)) { section in
                Button {
                    selection = section
                    dismiss()
                } label: {
                    Label(section.rawValue, systemImage: section.symbol)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(9)
                }
                .buttonStyle(.plain)
                .background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    @ViewBuilder
    private var fileMatches: some View {
        if !query.isEmpty {
            Text("FILES")
                .font(.fathomSystem(10, weight: .bold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.top, 8)
            switch model.state {
            case .idle:
                EmptyView()
            case .loading:
                ProgressView().padding(10)
            case let .failed(reason):
                unavailable(reason)
            case let .result(measurement):
                switch measurement {
                case let .known(rows, source):
                    if rows.isEmpty {
                        Text("No indexed match").foregroundStyle(.secondary).padding(10)
                    } else {
                        ForEach(rows) { row in
                            Button {
                                selection = .explore
                                dismiss()
                            } label: {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(row.path).lineLimit(1).truncationMode(.middle)
                                    HStack(spacing: 14) {
                                        Text("On disk \(measurementText(row.sizeOnDisk))")
                                        Text("Freed \(measurementText(row.freedIfDeleted))")
                                    }
                                    .font(.fathomSystem(11, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(9)
                            }
                            .buttonStyle(.plain)
                            .help(source.rawValue)
                            .accessibilityHint("Source \(source.rawValue)")
                            .background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 8))
                        }
                    }
                case let .notPublished(reason): unavailable(reason)
                case .notAttributable: unavailable("Search results are not attributable")
                }
            }
        }
    }

    private func unavailable(_ reason: String) -> some View {
        Text("not published — \(reason)")
            .font(.fathomSystem(12))
            .foregroundStyle(.secondary)
            .padding(10)
    }

    private func measurementText(_ value: FathomKit.Measurement<UInt64>) -> String {
        switch value {
        case let .known(bytes, _): hardwareByteString(bytes)
        case .notPublished: "not published"
        case let .notAttributable(measured, explained):
            "not attributable (\(hardwareByteString(measured)) / \(hardwareByteString(explained)))"
        }
    }
}
