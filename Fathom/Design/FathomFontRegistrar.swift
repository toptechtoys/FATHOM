import CoreText
import Foundation

enum FathomFontRegistrar {
    static func registerBundledFonts() {
        guard let resourceURL = Bundle.main.resourceURL else {
            return
        }
        let fontsURL = resourceURL.appending(path: "Fonts")
        guard
            let enumerator = FileManager.default.enumerator(
                at: fontsURL,
                includingPropertiesForKeys: nil
            )
        else {
            return
        }

        // Archivo ships as static TTF instances; the design-system faces are
        // woff2. Registering only one extension is how a bundled font
        // silently falls back to a system face at runtime.
        let fontExtensions: Set<String> = ["woff2", "ttf", "otf"]
        for case let url as URL in enumerator
        where fontExtensions.contains(url.pathExtension.lowercased()) {
            CTFontManagerRegisterFontsForURL(
                url as CFURL,
                .process,
                nil
            )
        }
    }
}
