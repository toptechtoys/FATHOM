import FathomKit
import SwiftUI

/// Public IP, country, and the control that turns the lookup off.
///
/// This lived in the sidebar until the rail became icon-only. It belongs in
/// Network anyway: it reports an address, and the other addresses are here.
///
/// It is the one screen in FATHOM behind the only outbound request the app
/// ever makes, so the privacy control sits beside the value rather than in a
/// settings screen the user has to go looking for.
struct PublicIPPanel: View {
    @EnvironmentObject private var publicIP: PublicIPAppModel
    @State private var showsPrivacy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("PUBLIC ADDRESS")
                .font(.fathomSystem(9, weight: .semibold))
                .tracking(1.44)
                .foregroundStyle(.white.opacity(FathomSurface.minimumTextOpacity))

            row

            Button("Privacy and lookup settings") {
                showsPrivacy.toggle()
            }
            .buttonStyle(.plain)
            .font(.fathomSystem(11.5))
            .foregroundStyle(FathomSemantic.informational)
            .popover(isPresented: $showsPrivacy, arrowEdge: .bottom) {
                privacySheet
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(FathomSurface.card)
    }

    @ViewBuilder
    private var row: some View {
        switch publicIP.measurement {
        case let .known(snapshot, source):
            HStack(spacing: 9) {
                CountryFlagView(countryCode: snapshot.countryCode)
                Text(snapshot.address)
                    .font(.fathomPath(13))
                    .lineLimit(1)
                Text(snapshot.countryCode)
                    .font(.fathomSystem(9, weight: .bold))
                    .tracking(0.9)
                    .foregroundStyle(.white.opacity(FathomSurface.minimumTextOpacity))
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                "Public IP \(snapshot.address), country "
                    + "\(snapshot.countryCode), source \(source.rawValue)"
            )
        case let .notPublished(reason):
            VStack(alignment: .leading, spacing: 4) {
                Text("not published")
                    .font(.fathomDisplay(21))
                Text(reason)
                    .font(.fathomSystem(11.5))
                    .foregroundStyle(.white.opacity(FathomSurface.minimumTextOpacity))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Public IP not published. \(reason)")
        case .notAttributable:
            Text("not attributable")
                .font(.fathomDisplay(21))
                .accessibilityLabel("Public IP not attributable")
        }
    }

    private var privacySheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            // `.headline` is 13pt system and never sees FathomType.scale, so
            // this heading rendered smaller than the paragraph under it once
            // the paragraph reached 12.5 x 1.45 = 18.1pt. It was one of only
            // two `.font` calls in Fathom/ that did not route through a
            // helper.
            Text("Privacy").font(.fathomSystem(13.5, weight: .semibold))
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
        // 330 left 290pt of measure, which at 18.1pt is about thirty
        // characters a line — a four-sentence privacy statement set as a
        // column. This is a popover with nothing else in it, so it can simply
        // take the room the type now needs.
        .frame(width: 330 * FathomType.scale)
    }
}
