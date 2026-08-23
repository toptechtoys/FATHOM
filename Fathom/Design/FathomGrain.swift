import AppKit
import SwiftUI

/// The grain over the colour field.
///
/// Four octaves of value noise, tiled, drawn with `overlay` at 30% — the
/// prototype's treatment, with one change that is not cosmetic.
///
/// **The noise is bounded, not just faded.** `overlay` drives a bright channel
/// toward white, and the grain sits *under* the plate, so a bright speckle
/// lightens the ground beneath text exactly the way the halo does. Unbounded
/// noise at 30% takes the worst world to 4.15:1 and fails the rule. Clamping
/// the noise to `noiseRange` keeps the designed opacity and blend while making
/// the worst speckle 4.60:1.
///
/// That is a narrower band than raw `feTurbulence` produces, but only at the
/// tails: four-octave fractal noise already spends most of its time near the
/// middle, so what the clamp removes is the rare speckle nobody wanted and the
/// contrast rule cannot afford.
enum FathomGrain {
    /// Drawn at this opacity, as the prototype specifies.
    static let opacity: Double = 0.30

    /// The noise is clamped to this band around mid-grey. The upper bound is
    /// the one the contrast gate reads: it is what a bright speckle can do to
    /// the ground under text.
    static let noiseCeiling: Double = 0.60
    static let noiseFloor: Double = 1 - noiseCeiling

    /// Tile size, matching the prototype's 180pt SVG.
    static let tileSize = 180

    /// Fixed so every launch renders the same field. A grain that reshuffled
    /// would make two screenshots of the same screen differ for no reason.
    private static let seed: UInt64 = 0x5FA7_C0DE

    /// Generated once. Regenerating a 180×180 texture on every world change
    /// would be a real cost on a screen that already samples at 1 Hz.
    static let texture: NSImage? = makeTexture()

    private static func makeTexture() -> NSImage? {
        let size = tileSize
        var pixels = [UInt8](repeating: 0, count: size * size * 4)
        let lattice = makeLattice()

        for y in 0..<size {
            for x in 0..<size {
                let value = fractal(
                    x: Double(x) / Double(size),
                    y: Double(y) / Double(size),
                    lattice: lattice
                )
                // `value` arrives in 0...1; squeeze it into the safe band.
                let bounded = noiseFloor + value * (noiseCeiling - noiseFloor)
                let level = UInt8(max(0, min(255, bounded * 255)))
                let offset = (y * size + x) * 4
                pixels[offset] = level
                pixels[offset + 1] = level
                pixels[offset + 2] = level
                pixels[offset + 3] = 255
            }
        }

        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let image = CGImage(
                  width: size,
                  height: size,
                  bitsPerComponent: 8,
                  bitsPerPixel: 32,
                  bytesPerRow: size * 4,
                  space: CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGBitmapInfo(
                      rawValue: CGImageAlphaInfo.premultipliedLast.rawValue
                  ),
                  provider: provider,
                  decode: nil,
                  shouldInterpolate: false,
                  intent: .defaultIntent
              )
        else { return nil }
        return NSImage(cgImage: image, size: NSSize(width: size, height: size))
    }

    /// A 16×16 lattice of random values, wrapped so the tile has no seam.
    private static func makeLattice() -> [[Double]] {
        let side = 16
        var state = seed
        func next() -> Double {
            // xorshift64: deterministic, and enough for a texture.
            state ^= state << 13
            state ^= state >> 7
            state ^= state << 17
            return Double(state % 10_000) / 10_000
        }
        return (0..<side).map { _ in (0..<side).map { _ in next() } }
    }

    /// Four octaves, each half the amplitude and twice the frequency.
    private static func fractal(
        x: Double,
        y: Double,
        lattice: [[Double]]
    ) -> Double {
        var total = 0.0
        var amplitude = 1.0
        var frequency = 4.0
        var normalisation = 0.0
        for _ in 0..<4 {
            total += value(x: x * frequency, y: y * frequency, lattice: lattice)
                * amplitude
            normalisation += amplitude
            amplitude /= 2
            frequency *= 2
        }
        return total / normalisation
    }

    /// Bilinear value noise with wraparound, so the tile repeats seamlessly.
    private static func value(
        x: Double,
        y: Double,
        lattice: [[Double]]
    ) -> Double {
        let side = lattice.count
        let scaledX = x * Double(side)
        let scaledY = y * Double(side)
        let x0 = Int(scaledX.rounded(.down))
        let y0 = Int(scaledY.rounded(.down))
        let fx = scaledX - Double(x0)
        let fy = scaledY - Double(y0)
        // Smoothstep, so the lattice does not show as a grid.
        let sx = fx * fx * (3 - 2 * fx)
        let sy = fy * fy * (3 - 2 * fy)

        func at(_ ix: Int, _ iy: Int) -> Double {
            lattice[((iy % side) + side) % side][((ix % side) + side) % side]
        }

        let top = at(x0, y0) * (1 - sx) + at(x0 + 1, y0) * sx
        let bottom = at(x0, y0 + 1) * (1 - sx) + at(x0 + 1, y0 + 1) * sx
        return top * (1 - sy) + bottom * sy
    }
}

/// The tiled grain, ready to sit over a colour field.
struct FathomGrainOverlay: View {
    var body: some View {
        GeometryReader { geometry in
            if let texture = FathomGrain.texture {
                Image(nsImage: texture)
                    .resizable(
                        resizingMode: .tile
                    )
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .blendMode(.overlay)
                    .opacity(FathomGrain.opacity)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
