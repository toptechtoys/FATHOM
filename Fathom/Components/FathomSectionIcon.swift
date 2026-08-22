import AppKit
import SwiftUI

/// One of the twenty bundled stroke icons, tinted by the current foreground.
///
/// The icons ship as SVGs in `Resources/NavIcons` rather than an asset catalog,
/// matching how `CountryFlagView` loads its flags. They are marked as template
/// images so AppKit tints them from the alpha channel and the rail can render
/// the same file at 82% white when inactive and full white when selected.
///
/// The image is decorative here. Every caller already labels the control it
/// sits inside, and a second label would make VoiceOver say the section name
/// twice.
struct FathomSectionIcon: View {
    let section: AppSection
    var size: CGFloat = 19

    var body: some View {
        Group {
            if let image = Self.image(named: section.icon) {
                Image(nsImage: image)
                    .resizable()
                    .renderingMode(.template)
                    .interpolation(.high)
                    .aspectRatio(1, contentMode: .fit)
            } else {
                // A missing icon file is a build problem, not a runtime state
                // worth explaining to the user. Hold the space so the rail does
                // not reflow, and let the tooltip and label still identify it.
                Color.clear
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    /// Loaded once per name. The rail renders twenty of these on every
    /// selection change, and re-decoding an SVG each time is measurable
    /// against the idle-cost budget in `AGENTS.md`.
    private static let cache = NSCache<NSString, NSImage>()

    private static func image(named name: String) -> NSImage? {
        if let cached = cache.object(forKey: name as NSString) {
            return cached
        }
        let url = Bundle.main.url(
            forResource: name,
            withExtension: "svg",
            subdirectory: "NavIcons"
        ) ?? Bundle.main.url(forResource: name, withExtension: "svg")
        guard let url, let image = NSImage(contentsOf: url) else { return nil }
        image.isTemplate = true
        cache.setObject(image, forKey: name as NSString)
        return image
    }
}
