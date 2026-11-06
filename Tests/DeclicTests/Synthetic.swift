import CoreGraphics
import Foundation
@testable import Declic

/// Générateur de contenus factices (niveaux de gris) pour tester l'assemblage.
struct Synthetic {
    var rng = SplitMix(seed: 1)

    /// Document de `height` lignes : lignes de « texte » aléatoires alternant avec des interlignes unies.
    mutating func document(width: Int, height: Int) -> [[UInt8]] {
        (0..<height).map { y in
            if (y / 14) % 2 == 0 {
                return (0..<width).map { _ in UInt8(truncatingIfNeeded: rng.next() % 256) }
            }
            return [UInt8](repeating: 240, count: width)
        }
    }

    mutating func band(width: Int, height: Int, base: UInt8, stripe: Int) -> [[UInt8]] {
        (0..<height).map { _ in (0..<width).map { x in x % stripe == 0 ? 10 : base } }
    }

    static func frame(_ rows: [[UInt8]]) -> RawFrame {
        let h = rows.count, w = rows.first?.count ?? 0
        var data = Data(count: w * h * 4)
        data.withUnsafeMutableBytes { raw in
            let p = raw.bindMemory(to: UInt8.self)
            for y in 0..<h {
                for x in 0..<w {
                    let v = rows[y][x], o = (y * w + x) * 4
                    p[o] = v; p[o + 1] = v; p[o + 2] = v; p[o + 3] = 255
                }
            }
        }
        return RawFrame(width: w, height: h, bytesPerRow: w * 4, data: data)
    }

    /// Niveaux de gris d'une image (canal rouge), ligne par ligne.
    static func gray(_ image: CGImage) -> [[UInt8]] {
        let w = image.width, h = image.height
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CoreStitcher.bitmapInfo) else { return [] }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let base = ctx.data else { return [] }
        let p = base.bindMemory(to: UInt8.self, capacity: w * h * 4)
        return (0..<h).map { y in (0..<w).map { x in p[(y * w + x) * 4 + 2] } }
    }
}

/// Générateur pseudo-aléatoire reproductible.
struct SplitMix {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
