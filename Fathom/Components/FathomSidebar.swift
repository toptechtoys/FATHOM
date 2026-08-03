import SwiftUI
import FathomKit

struct FathomSidebar: View {
    @Binding var selection: AppSection
    let compact: Bool
    @EnvironmentObject private var publicIP: PublicIPAppModel
    @State private var showsPrivacy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear
                .frame(height: 55)
                .accessibilityHidden(true)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    sidebarGroup("SURFACE", sections: [.menuBar])
                    sidebarGroup("OVERVIEW", sections: [.home, .deepScan])
                        .padding(.top, 13)
                    sidebarGroup(
                        "STORAGE",
                        sections: [.storage, .timeline, .explore, .reclaim]
                    )
                        .padding(.top, 13)
                    sidebarGroup(
                        "SYSTEM",
                        sections: [.cpu, .gpu, .memory, .network, .bluetooth, .sensors]
                    )
                        .padding(.top, 13)
                    sidebarGroup(
                        "FORESIGHT",
                        sections: [.endurance, .attribution, .digest]
                    )
                        .padding(.top, 13)
                    sidebarGroup("HARDWARE", sections: [.ssdHealth])
                        .padding(.top, 13)
                    sidebarGroup(
                        "MANAGE",
                        sections: [.applications, .cloud, .maintenance]
                    )
                        .padding(.top, 13)
                        .padding(.bottom, 12)
                }
            }
            .scrollIndicators(.hidden)

            Divider()
                .overlay(.white.opacity(0.1))
                .padding(.bottom, 11)

            Button {
                showsPrivacy.toggle()
            } label: {
                if compact {
                    Image(systemName: "hand.raised.fill")
                        .frame(maxWidth: .infinity)
                        .foregroundStyle(.white.opacity(0.82))
                } else {
                    VStack(alignment: .leading, spacing: 7) {
                        publicIPRow
                        HStack(spacing: 8) {
                            Circle()
                                .fill(.white.opacity(0.35))
                                .frame(width: 6, height: 6)
                            Text("Idle cost not published")
                                .font(.fathomSystem(11))
                                .foregroundStyle(.white.opacity(0.82))
                                .lineLimit(1)
                        }
                    }
                }
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
            .accessibilityLabel("Privacy and public IP settings")
            .padding(.horizontal, 10)
            .padding(.bottom, 15)
            .popover(isPresented: $showsPrivacy, arrowEdge: .trailing) {
                privacySheet
            }
        }
        .padding(.horizontal, compact ? 6 : 10)
        .frame(width: compact ? 64 : 244)
        .background(.black.opacity(0.20))
        .background(.ultraThinMaterial.opacity(0.18))
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(.white.opacity(0.11))
                .frame(width: 0.5)
        }
    }

    @ViewBuilder
    private var publicIPRow: some View {
        switch publicIP.measurement {
        case let .known(snapshot, source):
            HStack(spacing: 7) {
                CountryFlagView(countryCode: snapshot.countryCode)
                Text(snapshot.address)
                    .font(.fathomSystem(11, design: .monospaced))
                    .lineLimit(1)
                Spacer(minLength: 2)
                Text(snapshot.countryCode)
                    .font(.fathomSystem(9, weight: .bold))
                    .foregroundStyle(.white.opacity(0.82))
            }
            .help(source.rawValue)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                "Public IP \(snapshot.address), country \(snapshot.countryCode)"
            )
        case let .notPublished(reason):
            HStack(spacing: 8) {
                Image(systemName: "network.slash")
                Text("Public IP not published")
                    .lineLimit(1)
            }
            .font(.fathomSystem(11))
            .foregroundStyle(.white.opacity(0.82))
            .help(reason)
        case .notAttributable:
            Text("Public IP not attributable")
                .font(.fathomSystem(11))
                .foregroundStyle(.white.opacity(0.82))
        }
    }

    private var privacySheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Privacy").font(.headline)
            Text("Public IP and country is FATHOM's only outbound request. When enabled, one request goes to Cloudflare and is cached for six hours. It carries no account, device identifier, cookies, or credentials.")
                .font(.fathomSystem(12.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Toggle("Show public IP and country", isOn: $publicIP.isEnabled)
            if publicIP.isEnabled {
                Button("Refresh if cache expired") { publicIP.refresh() }
                    .disabled(publicIP.isRefreshing)
            }
        }
        .padding(20)
        .frame(width: 330)
    }


    @ViewBuilder
    private func sidebarGroup(
        _ title: String,
        sections: [AppSection]
    ) -> some View {
        if !compact {
            Text(title)
                .font(.fathomSystem(10, weight: .bold))
                .tracking(1)
                .foregroundStyle(.white.opacity(0.82))
                .padding(.horizontal, 22)
                .padding(.bottom, 5)
        }

        ForEach(sections) { section in
            Button {
                selection = section
            } label: {
                Group {
                    if compact {
                        Image(systemName: section.symbol)
                            .frame(maxWidth: .infinity)
                    } else {
                        Label(section.rawValue, systemImage: section.symbol)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                    .font(.fathomSystem(13.5, weight: .medium))
                    .padding(.horizontal, compact ? 6 : 12)
                    .padding(.vertical, compact ? 7 : 8.5)
                    .background(
                        selection == section
                            ? .white.opacity(0.19)
                            : .clear,
                        in: RoundedRectangle(cornerRadius: 10)
                    )
            }
            .buttonStyle(.plain)
            .help(section.rawValue)
            .accessibilityLabel(section.rawValue)
            .foregroundStyle(
                selection == section
                    ? .white
                    : .white.opacity(0.75)
            )
            .accessibilityAddTraits(
                selection == section ? .isSelected : []
            )
        }
    }
}
