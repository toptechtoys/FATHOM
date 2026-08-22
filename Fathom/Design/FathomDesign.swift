import SwiftUI

struct FathomColorWorld: Equatable {
    let top: Color
    let middle: Color
    let bottom: Color
    let objectLight: Color
    let objectDark: Color

    static let storage = FathomColorWorld(
        top: Color(hex: 0x04263A),
        middle: Color(hex: 0x0C6B90),
        bottom: Color(hex: 0x2BB6D4),
        objectLight: Color(hex: 0xB6EEFA),
        objectDark: Color(hex: 0x0B6A85)
    )

    static let menuBar = FathomColorWorld(
        top: Color(hex: 0x062737),
        middle: Color(hex: 0x0C6076),
        bottom: Color(hex: 0x1FA3B8),
        objectLight: Color(hex: 0xB9EEF5),
        objectDark: Color(hex: 0x0B6273)
    )

    static let home = FathomColorWorld(
        top: Color(hex: 0x08133A),
        middle: Color(hex: 0x1B3E86),
        bottom: Color(hex: 0x3F79CE),
        objectLight: Color(hex: 0xC6DBFB),
        objectDark: Color(hex: 0x1C3E82)
    )

    static let deepScan = FathomColorWorld(
        top: Color(hex: 0x1B0E42),
        middle: Color(hex: 0x4E23A0),
        bottom: Color(hex: 0x8B5CF6),
        objectLight: Color(hex: 0xDDD1FE),
        objectDark: Color(hex: 0x5B21B6)
    )

    static let explore = FathomColorWorld(
        top: Color(hex: 0x0C1445),
        middle: Color(hex: 0x243397),
        bottom: Color(hex: 0x5566DC),
        objectLight: Color(hex: 0xC7D0FF),
        objectDark: Color(hex: 0x26339B)
    )

    static let endurance = FathomColorWorld(
        top: Color(hex: 0x051E2C),
        middle: Color(hex: 0x0F5A72),
        bottom: Color(hex: 0x33A2B4),
        objectLight: Color(hex: 0xAFEBEE),
        objectDark: Color(hex: 0x0D6D7C)
    )

    static let ssdHealth = FathomColorWorld(
        top: Color(hex: 0x0A1F2E),
        middle: Color(hex: 0x1D5570),
        bottom: Color(hex: 0x4A93AE),
        objectLight: Color(hex: 0xC3E6F2),
        objectDark: Color(hex: 0x1B5570)
    )

    static let sensors = FathomColorWorld(
        top: Color(hex: 0x3A1206),
        middle: Color(hex: 0x96380A),
        bottom: Color(hex: 0xDE7A17),
        objectLight: Color(hex: 0xFDDCAE),
        objectDark: Color(hex: 0x9A4109)
    )

    static let cpu = FathomColorWorld(
        top: Color(hex: 0x04203A),
        middle: Color(hex: 0x0B5296),
        bottom: Color(hex: 0x2E8BE0),
        objectLight: Color(hex: 0xBCDDFB),
        objectDark: Color(hex: 0x0C4E8C)
    )

    static let memory = FathomColorWorld(
        top: Color(hex: 0x12063A),
        middle: Color(hex: 0x3B1D9E),
        bottom: Color(hex: 0x6F4BE0),
        objectLight: Color(hex: 0xD2C6FE),
        objectDark: Color(hex: 0x3A1F94)
    )

    static let gpu = FathomColorWorld(
        top: Color(hex: 0x2A0838),
        middle: Color(hex: 0x6D1580),
        bottom: Color(hex: 0xB040C8),
        objectLight: Color(hex: 0xF3C8FC),
        objectDark: Color(hex: 0x6B1A7E)
    )

    static let network = FathomColorWorld(
        top: Color(hex: 0x03302C),
        middle: Color(hex: 0x0A7A72),
        bottom: Color(hex: 0x2CB9AC),
        objectLight: Color(hex: 0xB3F5EE),
        objectDark: Color(hex: 0x087269)
    )

    static let bluetooth = FathomColorWorld(
        top: Color(hex: 0x062B1E),
        middle: Color(hex: 0x0D7A4E),
        bottom: Color(hex: 0x2CBE7C),
        objectLight: Color(hex: 0xB9F8D8),
        objectDark: Color(hex: 0x0A7350)
    )

    static let reclaim = FathomColorWorld(
        top: Color(hex: 0x032A1F),
        middle: Color(hex: 0x0A7150),
        bottom: Color(hex: 0x26B87C),
        objectLight: Color(hex: 0xB4F7D6),
        objectDark: Color(hex: 0x08704F)
    )

    static let applications = FathomColorWorld(
        top: Color(hex: 0x141046),
        middle: Color(hex: 0x3A2AA8),
        bottom: Color(hex: 0x7059E8),
        objectLight: Color(hex: 0xD5CDFF),
        objectDark: Color(hex: 0x3B2CA4)
    )

    static let cloud = FathomColorWorld(
        top: Color(hex: 0x07234A),
        middle: Color(hex: 0x12559E),
        bottom: Color(hex: 0x3691E0),
        objectLight: Color(hex: 0xC0DFFB),
        objectDark: Color(hex: 0x11529A)
    )

    static let maintenance = FathomColorWorld(
        top: Color(hex: 0x331A05),
        middle: Color(hex: 0x8A4A0B),
        bottom: Color(hex: 0xD08A1D),
        objectLight: Color(hex: 0xFBE1B4),
        objectDark: Color(hex: 0x8B4C0C)
    )

    static let timeline = FathomColorWorld(
        top: Color(hex: 0x26063E),
        middle: Color(hex: 0x6B1AA0),
        bottom: Color(hex: 0xB23FD4),
        objectLight: Color(hex: 0xF0CBFB),
        objectDark: Color(hex: 0x6D1D9C)
    )

    static let attribution = FathomColorWorld(
        top: Color(hex: 0x101334),
        middle: Color(hex: 0x333A80),
        bottom: Color(hex: 0x6B74CE),
        objectLight: Color(hex: 0xCDD2FF),
        objectDark: Color(hex: 0x3A4299)
    )

    static let digest = FathomColorWorld(
        top: Color(hex: 0x28211A),
        middle: Color(hex: 0x6F5936),
        bottom: Color(hex: 0xBE9A56),
        objectLight: Color(hex: 0xFAEAC6),
        objectDark: Color(hex: 0x7E6534)
    )
}

/// The surface body text sits on.
///
/// Body text is white at 82%. Directly on the colour worlds that lands between
/// 2.05:1 (bluetooth) and 4.32:1 (memory), short of the 4.5:1 `AGENTS.md`
/// requires on every surface. White-tinted cards made it worse, because they
/// lighten the field the text is trying to contrast against.
///
/// Every surface carrying body text uses this scrim instead. At 40% the worst
/// world reaches 4.56:1, still clear of the rule with the white 15% radial
/// highlight `FathomWorldBackground` paints across the upper field. The colour
/// worlds themselves are untouched. `scripts/check-contrast.py` reads this
/// value and the worlds from source and proves the result, so the two cannot
/// drift.
///
/// 40% is the Instrument Panel readout-cell value, chosen deliberately over the
/// 45% that shipped before it: the flatter cell is the point of that direction.
/// It leaves 0.06 of margin, and break-even is 39.4%, so this is the shallowest
/// scrim the rule permits at 82% white. A world with a brighter bottom stop than
/// bluetooth's `#2CBE7C` would fail the gate — check before adding one.
enum FathomSurface {
    static let textScrimOpacity: Double = 0.40

    /// Cards and tiles that carry body text.
    static var card: Color { .black.opacity(textScrimOpacity) }

    /// Small badges and pills that carry body text over the same field.
    static var badge: Color { .black.opacity(textScrimOpacity) }
}

extension Animation {
    static let fathomWorld = Animation.timingCurve(
        0.16,
        1,
        0.3,
        1,
        duration: 0.55
    )
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

extension Font {
    static func fathomSystem(
        _ size: CGFloat,
        weight: Font.Weight = .regular,
        design: Font.Design = .default
    ) -> Font {
        let name = design == .monospaced
            ? ".AppleSystemUIFontMonospaced"
            : ".AppleSystemUIFont"
        return .custom(
            name,
            size: size,
            relativeTo: fathomRelativeStyle(for: size)
        )
        .weight(weight)
    }

    static func fathomDisplay(
        _ size: CGFloat,
        weight: Font.Weight = .semibold
    ) -> Font {
        .custom(
            "Bricolage Grotesque 96pt ExtraBold",
            size: size,
            relativeTo: fathomRelativeStyle(for: size)
        )
            .weight(weight)
    }

    static func fathomData(
        _ size: CGFloat,
        weight: Font.Weight = .regular
    ) -> Font {
        .custom(
            "Instrument Sans",
            size: size,
            relativeTo: fathomRelativeStyle(for: size)
        )
            .weight(weight)
            .monospacedDigit()
    }

    static func fathomPath(_ size: CGFloat) -> Font {
        .custom(
            "JetBrains Mono",
            size: size,
            relativeTo: fathomRelativeStyle(for: size)
        )
    }

    private static func fathomRelativeStyle(for size: CGFloat) -> Font.TextStyle {
        switch size {
        case 0..<10: .caption2
        case 10..<12: .caption
        case 12..<14: .footnote
        case 14..<16: .subheadline
        case 16..<20: .body
        case 20..<28: .title3
        case 28..<34: .title2
        case 34..<44: .title
        default: .largeTitle
        }
    }
}
