import CoreGraphics
import Testing
@testable import FathomKit

private let canvas = CGRect(x: 0, y: 0, width: 800, height: 400)

private func area(_ rect: CGRect) -> Double { rect.width * rect.height }

@Test func everyTileGetsAreaProportionalToItsWeight() {
    let weights: [(id: String, weight: Double)] = [
        ("developer", 142.2), ("applications", 94.7), ("photos", 88.1),
        ("library", 66.6), ("system", 12.1), ("other", 16.5),
    ]
    let total = weights.reduce(0) { $0 + $1.weight }
    let tiles = TreemapLayout.tiles(weights, in: canvas)
    let canvasArea = area(canvas)

    for tile in tiles {
        let weight = weights.first { $0.id == tile.id }!.weight
        let expected = canvasArea * (weight / total)
        // Area is the whole claim the panel makes, so this is tight.
        #expect(abs(area(tile.rect) - expected) < 0.5)
    }
}

@Test func tilesFillTheCanvasExactly() {
    let weights: [(id: Int, weight: Double)] = (0..<7).map { ($0, Double($0 + 1)) }
    let tiles = TreemapLayout.tiles(weights, in: canvas)
    let covered = tiles.reduce(0.0) { $0 + area($1.rect) }
    // No gap, and nothing spilling outside: a treemap that loses area under-
    // reports whatever it dropped.
    #expect(abs(covered - area(canvas)) < 0.5)
    for tile in tiles {
        #expect(canvas.contains(tile.rect) || canvas.union(tile.rect) == canvas)
    }
}

@Test func tilesDoNotOverlap() {
    let weights: [(id: Int, weight: Double)] = [
        (0, 40), (1, 25), (2, 15), (3, 10), (4, 6), (5, 4),
    ]
    let tiles = TreemapLayout.tiles(weights, in: canvas)
    for i in tiles.indices {
        for j in tiles.indices where j > i {
            let overlap = tiles[i].rect.intersection(tiles[j].rect)
            // Shared edges are fine; shared area double-counts a byte.
            #expect(overlap.isNull || area(overlap) < 0.001)
        }
    }
}

@Test func oneRegionTakesTheWholeRectangle() {
    let tiles = TreemapLayout.tiles([(id: "only", weight: 1)], in: canvas)
    #expect(tiles.count == 1)
    #expect(tiles[0].rect == canvas)
}

@Test func aZeroWeightRegionStillAppears() {
    let weights: [(id: String, weight: Double)] = [
        ("big", 100), ("empty", 0), ("small", 10),
    ]
    let tiles = TreemapLayout.tiles(weights, in: canvas)
    // Dropping it would make the panel silently shorter than the data.
    #expect(tiles.count == 3)
    #expect(tiles.contains { $0.id == "empty" })
    let empty = tiles.first { $0.id == "empty" }!
    #expect(area(empty.rect) < 0.5)
}

@Test func everythingWeighingNothingYieldsEmptyTilesRatherThanNaN() {
    let weights: [(id: Int, weight: Double)] = [(0, 0), (1, 0)]
    let tiles = TreemapLayout.tiles(weights, in: canvas)
    #expect(tiles.count == 2)
    for tile in tiles {
        #expect(tile.rect == .zero)
        #expect(!tile.rect.width.isNaN)
    }
}

@Test func anEmptyCanvasProducesNoInfinities() {
    let weights: [(id: Int, weight: Double)] = [(0, 3), (1, 1)]
    let tiles = TreemapLayout.tiles(weights, in: .zero)
    #expect(tiles.count == 2)
    for tile in tiles { #expect(tile.rect == .zero) }
}

@Test func negativeWeightsAreTreatedAsNothingNotAsNegativeArea() {
    let weights: [(id: String, weight: Double)] = [
        ("real", 50), ("bogus", -20),
    ]
    let tiles = TreemapLayout.tiles(weights, in: canvas)
    let real = tiles.first { $0.id == "real" }!
    #expect(abs(area(real.rect) - area(canvas)) < 0.5)
    for tile in tiles { #expect(tile.rect.width >= 0 && tile.rect.height >= 0) }
}

@Test func layoutIsStableForTheSameInput() {
    let weights: [(id: Int, weight: Double)] = [(0, 5), (1, 3), (2, 2)]
    let first = TreemapLayout.tiles(weights, in: canvas)
    let second = TreemapLayout.tiles(weights, in: canvas)
    #expect(first.map(\.rect) == second.map(\.rect))
}
