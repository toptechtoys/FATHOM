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
/// The fix is one plate, not a plate per element. Everything that carries text
/// — the whole content column, and the rail beside it — sits on `scrimOpacity`
/// black. The Instrument Panel's own materials then layer on top of that plate
/// at exactly the values the design specifies: the readout cell is still 16%,
/// the data row still 7%, its hover still 13%. Their *relative* flatness, which
/// is the point of that direction, is preserved; what changed is the ground
/// underneath them.
///
/// This is why the materials are black rather than the design's white. On a
/// plate, a white tint lightens back toward the field the plate exists to
/// escape — the same mistake the white 10.5% cards made, and the reason
/// FATHOM-DESIGN.md records that hover deepens and never lightens. The design's
/// magnitudes are kept; only the sign is flipped.
///
/// The worst worlds are bluetooth `#2CBE7C` and storage `#2BB6D4`, within 0.002
/// of each other on every surface. On either: plate alone 4.60:1 at 82% white
/// and 5.95:1 for a display title at full white, cell 5.75:1, row 5.07:1, row
/// hover 5.51:1 — each composited with the brightest speckle the grain's band
/// permits, which is what separates these figures from the pre-grain ones they
/// replace. `scripts/check-contrast.py` composites these stacks from source and
/// fails the build if any drops below 4.5:1, so the model here and the one the
/// app renders cannot drift.
///
/// Text never goes below 82% white on these surfaces. There is no quieter tier:
/// at 60% the plate would need 58%, and 45% cannot reach 4.5:1 at any depth.
enum FathomSurface {
    /// The plate under the content column and the rail.
    static let scrimOpacity: Double = 0.45

    /// Readout cells, cards and tiles — the design's 16%, over the plate.
    static let cardOpacity: Double = 0.16

    /// Data rows — the design's 7%, over the plate.
    static let rowOpacity: Double = 0.07

    /// Row hover — the design's 13%, deepening rather than lightening.
    static let rowHoverOpacity: Double = 0.13

    /// The minimum text alpha any of these surfaces will carry.
    static let minimumTextOpacity: Double = 0.82

    /// The plate behind the scrolling content column.
    static var contentPlate: Color { .black.opacity(scrimOpacity) }

    /// The plate behind the navigation rail.
    static var rail: Color { .black.opacity(scrimOpacity) }

    /// Cards, tiles and readout cells that carry body text.
    static var card: Color { .black.opacity(cardOpacity) }

    /// Small badges and pills that carry body text.
    static var badge: Color { .black.opacity(cardOpacity) }

    /// Data rows inside panels.
    static var row: Color { .black.opacity(rowOpacity) }

    /// Data rows under the pointer.
    static var rowHover: Color { .black.opacity(rowHoverOpacity) }
}

/// Colour that carries meaning, never decoration.
///
/// Never used alone: a freeable figure is always accompanied by the word or the
/// number, so the meaning survives for anyone who cannot separate these hues.
///
/// `blocked` and `informational` are not the values the Instrument Panel
/// handoff drew. As text on a data row its `#FFAFAF` measured 3.88:1 and its
/// `#A9CBFF` 4.10:1, both short of the rule, so each was lightened until it
/// clears with the margin the rest of the system keeps. The hue is unchanged.
///
/// `live` is the exception and is **not a text colour**: 4.32:1 on a row is
/// fine for the pulsing dot and switch fill it is used for, since non-text
/// graphics need 3:1, and not fine for a word.
enum FathomSemantic {
    /// This space actually comes back.
    static let freeable = Color(hex: 0x8DF3C4)
    /// Real but conditional — needs care.
    static let caution = Color(hex: 0xFCD98A)
    /// Frees nothing, or a genuine risk.
    static let blocked = Color(hex: 0xFFCACA)
    /// Worth knowing, no action.
    static let informational = Color(hex: 0xBFD9FF)
    /// Sampling right now. Dots and switches only.
    static let live = Color(hex: 0x5CE6A8)
}

extension Animation {
    /// A section arriving. Paired with a 12pt rise, per FATHOM-DESIGN.md.
    static let fathomEnter = Animation.timingCurve(0.16, 1, 0.3, 1, duration: 0.45)

    /// Hover on a rail item, cell or row.
    static let fathomHover = Animation.timingCurve(0.16, 1, 0.3, 1, duration: 0.22)

    /// Press feedback. Confirms an action, so Reduce Motion keeps it.
    static let fathomPress = Animation.timingCurve(0.16, 1, 0.3, 1, duration: 0.17)

    /// A core bar changing height on the 1 Hz tick. The only thing that
    /// animates on a tick — a number that eases into place cannot be read.
    static let fathomCoreBar = Animation.timingCurve(0.16, 1, 0.3, 1, duration: 0.6)

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

/// The native-feel pass, 25 August 2026.
///
/// The owner watched the app run and called the type too small — the
/// prototype's scale was drawn for a mockup, not read off a screen. Every
/// stated size in this codebase still matches the prototype's numbers; the
/// helpers below multiply them by this factor at render time, so the whole
/// scale moves together and the factor is one reviewable number. When the
/// factor settles, it gets baked into the prototype and FATHOM-DESIGN.md as
/// the recorded sizes.
enum FathomType {
    /// 1.2 was reviewed on screen and still read small; 1.32 is the second
    /// review's ask (another 10%).
    static let scale: CGFloat = 1.45
}

extension Font {
    /// UI and numerals.
    ///
    /// Archivo at its normal width. The Instrument Panel handoff asks for
    /// `wdth 104`, which only a variable font can hit — Archivo ships as static
    /// instances at 62, 75, 87.5, 100, 112.5 and 125, so 100 is the nearest and
    /// 104 is not reachable without the variable file. See *Type* in
    /// FATHOM-DESIGN.md.
    static func fathomSystem(
        _ size: CGFloat,
        weight: Font.Weight = .regular,
        design: Font.Design = .default
    ) -> Font {
        let size = size * FathomType.scale
        guard design != .monospaced else {
            return .custom(
                ".AppleSystemUIFontMonospaced",
                size: size,
                relativeTo: fathomRelativeStyle(for: size)
            )
            .weight(weight)
        }
        return .custom(
            "Archivo",
            size: size,
            relativeTo: fathomRelativeStyle(for: size)
        )
        .weight(weight)
    }

    /// Section titles and readout values.
    ///
    /// Archivo SemiExpanded, which measures width class 6 — 112.5% of normal,
    /// against the handoff's `wdth 112`. Close enough to be the same face.
    static func fathomDisplay(
        _ size: CGFloat,
        weight: Font.Weight = .semibold
    ) -> Font {
        let size = size * FathomType.scale
        return .custom(
            "Archivo SemiExpanded",
            size: size,
            relativeTo: fathomRelativeStyle(for: size)
        )
            .weight(weight)
    }

    /// Figures in a column that can be compared.
    ///
    /// Archivo, like the rest of the UI — the handoff specifies one family for
    /// UI and numerals both, and Instrument Sans belonged to the earlier
    /// direction. `monospacedDigit` makes the numerals tabular, which
    /// FATHOM-DESIGN.md calls non-negotiable.
    static func fathomData(
        _ size: CGFloat,
        weight: Font.Weight = .regular
    ) -> Font {
        let size = size * FathomType.scale
        return .custom(
            "Archivo",
            size: size,
            relativeTo: fathomRelativeStyle(for: size)
        )
            .weight(weight)
            .monospacedDigit()
    }

    static func fathomPath(_ size: CGFloat) -> Font {
        let size = size * FathomType.scale
        return .custom(
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
