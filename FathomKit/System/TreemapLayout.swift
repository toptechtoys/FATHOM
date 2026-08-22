import CoreGraphics
import Foundation

/// Splits a rectangle into tiles whose areas are proportional to their weights.
///
/// This lives in FathomKit rather than beside the view because the treemap's
/// entire claim is *area is size on disk*. If the arithmetic is wrong the panel
/// misrepresents the volume as confidently as a wrong number would, and that is
/// the one thing this product may not do — so it is testable, and tested.
///
/// Slice-and-dice: at each step the list is split near its halfway point by
/// weight and the rectangle is cut along its longer axis, which keeps tiles
/// closer to square without ever trading away proportionality.
public enum TreemapLayout {
    public struct Tile<ID: Hashable & Sendable>: Sendable {
        public let id: ID
        public let rect: CGRect

        public init(id: ID, rect: CGRect) {
            self.id = id
            self.rect = rect
        }
    }

    /// - Parameter weights: identifier and weight, in the order to lay out.
    ///   Zero and negative weights get an empty rectangle rather than being
    ///   dropped, so a caller iterating tiles still sees every item.
    public static func tiles<ID: Hashable & Sendable>(
        _ weights: [(id: ID, weight: Double)],
        in rect: CGRect
    ) -> [Tile<ID>] {
        guard !weights.isEmpty else { return [] }
        let total = weights.reduce(0) { $0 + max(0, $1.weight) }
        guard total > 0, rect.width > 0, rect.height > 0 else {
            return weights.map { Tile(id: $0.id, rect: .zero) }
        }
        return split(weights, total: total, in: rect)
    }

    private static func split<ID: Hashable & Sendable>(
        _ weights: [(id: ID, weight: Double)],
        total: Double,
        in rect: CGRect
    ) -> [Tile<ID>] {
        if weights.count == 1 {
            return [Tile(id: weights[0].id, rect: rect)]
        }

        var running = 0.0
        var index = 1
        for (offset, entry) in weights.enumerated() {
            let weight = max(0, entry.weight)
            if running + weight / 2 >= total / 2 {
                index = max(1, offset)
                break
            }
            running += weight
            index = offset + 1
        }
        index = min(max(index, 1), weights.count - 1)

        let head = Array(weights[..<index])
        let tail = Array(weights[index...])
        let headTotal = head.reduce(0) { $0 + max(0, $1.weight) }
        let tailTotal = total - headTotal
        let share = headTotal / total

        let first: CGRect
        let second: CGRect
        if rect.width >= rect.height {
            let width = rect.width * share
            first = CGRect(
                x: rect.minX, y: rect.minY, width: width, height: rect.height
            )
            second = CGRect(
                x: rect.minX + width, y: rect.minY,
                width: rect.width - width, height: rect.height
            )
        } else {
            let height = rect.height * share
            first = CGRect(
                x: rect.minX, y: rect.minY, width: rect.width, height: height
            )
            second = CGRect(
                x: rect.minX, y: rect.minY + height,
                width: rect.width, height: rect.height - height
            )
        }

        return split(head, total: headTotal, in: first)
            + split(tail, total: max(tailTotal, .leastNonzeroMagnitude), in: second)
    }
}
