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

        for case let url as URL in enumerator where url.pathExtension == "woff2" {
            CTFontManagerRegisterFontsForURL(
                url as CFURL,
                .process,
                nil
            )
        }
    }
}
