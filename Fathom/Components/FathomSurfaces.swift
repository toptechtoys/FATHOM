import FathomKit
import SwiftUI

/// The menu bar widget at the size macOS actually gives it.
///
/// Actual size is the point: every item costs width you cannot get back, and a
/// preview drawn larger than the real thing would hide that. 22pt is the height
/// the system grants; the 26pt capsule is the widget's own bounds within it.
struct FathomMenuBarPreview: View {
    struct Item: Identifiable {
        let id = UUID()
        let text: String
        var isEmphasised = false
    }

    let items: [Item]

    var body: some View {
        HStack(spacing: 14) {
            ForEach(items) { item in
                Text(item.text)
                    .font(
                        .fathomSystem(
                            11.5,
                            weight: item.isEmphasised ? .semibold : .regular
                        )
                    )
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 26)
        .background(.black.opacity(0.42))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "Menu bar preview, actual size: "
                + items.map(\.text).joined(separator: ", ")
        )
    }
}

/// The weekly digest, rendered as the thing that will actually arrive.
///
/// A light card on the dark field, because the digest is a document rather than
/// a readout. It is allowed to say nothing: if the week was quiet the closing
/// line is the whole message, and it never invents a finding to justify
/// arriving.
///
/// The card is its own light surface, so its text is dark and the plate's
/// contrast rules do not apply — these pairings are measured against the card,
/// not the field.
struct FathomDigestCard: View {
    struct Line: Identifiable {
        let id = UUID()
        let name: String
        let value: String
        let direction: Direction

        enum Direction {
            case grew, shrank, neutral
        }
    }

    let headline: String
    let dateline: String
    let lines: [Line]
    let summary: String
    var closing = "Nothing needs you. This is the whole message."

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(headline)
                .font(.fathomDisplay(19))
                .tracking(-0.38)
                .foregroundStyle(Color(hex: 0x1A1A1A))
            Text(dateline)
                .font(.fathomSystem(11))
                .foregroundStyle(Color(hex: 0x6B6B6B))
                .padding(.top, 3)
                .padding(.bottom, 14)

            ForEach(lines) { line in
                HStack(alignment: .firstTextBaseline) {
                    Text(line.name)
                        .foregroundStyle(Color(hex: 0x1A1A1A))
                    Spacer(minLength: 14)
                    Text(line.value)
                        .fontWeight(.semibold)
                        .monospacedDigit()
                        .foregroundStyle(color(for: line.direction))
                }
                .font(.fathomSystem(12.5))
                .padding(.vertical, 6)
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(Color(hex: 0xE2E0DD))
                        .frame(height: 1)
                }
                .accessibilityElement(children: .combine)
            }

            Text(summary)
                .font(.fathomSystem(12.5))
                .foregroundStyle(Color(hex: 0x3A3A3A))
                .lineSpacing(3)
                .padding(.top, 14)
                .fixedSize(horizontal: false, vertical: true)

            Text(closing)
                .font(.fathomSystem(12.5, weight: .semibold))
                .foregroundStyle(Color(hex: 0x1A1A1A))
                .padding(.top, 12)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(EdgeInsets(top: 22, leading: 24, bottom: 22, trailing: 24))
        .frame(maxWidth: 520, alignment: .leading)
        .background(Color(hex: 0xF4F3F1))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    /// Dark on the light card: 5.93:1 for grew, 5.13:1 for shrank. Direction is
    /// also stated by the sign on the value, never by colour alone.
    private func color(for direction: Line.Direction) -> Color {
        switch direction {
        case .grew: Color(hex: 0xB42318)
        case .shrank: Color(hex: 0x067647)
        case .neutral: Color(hex: 0x1A1A1A)
        }
    }
}

/// Area is size on disk. Every rectangle names its own numbers.
///
/// A treemap is only honest if the areas are proportional and nothing is
/// omitted to make the picture tidy, so the caller passes a remainder segment
/// where one exists rather than letting the largest tiles absorb it.
struct FathomTreemap: View {
    struct Region: Identifiable {
        let id = UUID()
        let name: String
        let detail: String
        let fraction: Double
    }

    let regions: [Region]

    var body: some View {
        GeometryReader { geometry in
            let tiles = TreemapLayout.tiles(
                regions.map { (id: $0.id, weight: $0.fraction) },
                in: CGRect(origin: .zero, size: geometry.size)
            )
            let byID = Dictionary(
                uniqueKeysWithValues: tiles.map { ($0.id, $0.rect) }
            )
            ZStack(alignment: .topLeading) {
                ForEach(Array(regions.enumerated()), id: \.element.id) { index, region in
                    let rect = byID[region.id] ?? .zero
                    VStack(alignment: .leading, spacing: 2) {
                        Text(region.name)
                            .font(.fathomSystem(11.5, weight: .semibold))
                            .lineLimit(1)
                        Text(region.detail)
                            .font(.fathomSystem(10))
                            .foregroundStyle(
                                .white.opacity(FathomSurface.minimumTextOpacity)
                            )
                            .lineLimit(1)
                    }
                    .padding(EdgeInsets(top: 9, leading: 11, bottom: 9, trailing: 11))
                    .frame(width: rect.width, height: rect.height, alignment: .topLeading)
                    .background(.black.opacity(0.10 + Double(index) * 0.02))
                    .overlay {
                        Rectangle().stroke(.white.opacity(0.14), lineWidth: 1)
                    }
                    .clipped()
                    .offset(x: rect.minX, y: rect.minY)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(region.name), \(region.detail)")
                }
            }
        }
        .frame(height: 230)
        .accessibilityElement(children: .contain)
    }
}
