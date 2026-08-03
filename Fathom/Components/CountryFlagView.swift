import AppKit
import SwiftUI

struct CountryFlagView: View {
    let countryCode: String

    var body: some View {
        Group {
            if let image = bundledImage {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(4 / 3, contentMode: .fit)
            } else {
                Text(countryCode)
                    .font(.fathomSystem(8, weight: .bold))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 20, height: 14)
        .clipShape(RoundedRectangle(cornerRadius: 2))
        .accessibilityHidden(true)
    }

    private var bundledImage: NSImage? {
        let name = countryCode.lowercased()
        let url = Bundle.main.url(
            forResource: name,
            withExtension: "svg",
            subdirectory: "CountryFlags"
        ) ?? Bundle.main.url(forResource: name, withExtension: "svg")
        return url.flatMap { NSImage(contentsOf: $0) }
    }
}
