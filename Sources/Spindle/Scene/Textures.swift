import AppKit
import CoreGraphics
import Foundation

/// Every surface in Spindle is drawn at launch instead of shipped as a file.
/// That keeps the repository free of binary assets, lets a texture follow the
/// scene's palette, and means the wood never repeats between moods.
enum Textures {

    // MARK: - Pixel plumbing

    /// Build a CGImage by evaluating `body` per pixel. Called a handful of
    /// times at startup, so clarity beats cleverness here.
    static func image(width: Int, height: Int,
                      _ body: (_ u: Double, _ v: Double) -> (Double, Double, Double, Double)) -> CGImage {
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            let v = (Double(y) + 0.5) / Double(height)
            for x in 0..<width {
                let u = (Double(x) + 0.5) / Double(width)
                let (r, g, b, a) = body(u, v)
                let i = (y * width + x) * 4
                pixels[i] = clamp8(r * 255)
                pixels[i + 1] = clamp8(g * 255)
                pixels[i + 2] = clamp8(b * 255)
                pixels[i + 3] = clamp8(a * 255)
            }
        }
        return bitmap(width: width, height: height, pixels: pixels)
    }

    static func bitmap(width: Int, height: Int, pixels: [UInt8]) -> CGImage {
        let cs = CGColorSpaceCreateDeviceRGB()
        let info = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        let provider = CGDataProvider(data: Data(pixels) as CFData)!
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: width * 4, space: cs, bitmapInfo: info,
                       provider: provider, decode: nil, shouldInterpolate: true,
                       intent: .defaultIntent)!
    }

    /// Draw into a context with AppKit/CoreGraphics calls instead of per-pixel.
    static func draw(width: Int, height: Int, _ body: (CGContext) -> Void) -> CGImage {
        let cs = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                            bytesPerRow: 0, space: cs,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        body(ctx)
        return ctx.makeImage()!
    }

    static func clamp8(_ v: Double) -> UInt8 {
        v <= 0 ? 0 : v >= 255 ? 255 : UInt8(v)
    }

    // MARK: - Noise

    /// Smooth 2-D value noise. Deterministic for a given seed, so a scene
    /// renders identically at 1440p and at 5K.
    ///
    /// This has to be genuine 2-D noise built on a permutation table. An
    /// earlier version faked it by summing two 1-D lookups along different
    /// directions, and every surface using it came out faintly striped —
    /// which on a painted plinth or a desk top is exactly the kind of
    /// regularity that makes a render read as computer-generated.
    struct Noise {
        private var perm = [Int](repeating: 0, count: 512)
        private var values = [Double](repeating: 0, count: 256)

        init(seed: UInt64) {
            var state = seed &* 6364136223846793005 &+ 1442695040888963407
            func next() -> UInt64 {
                state = state &* 6364136223846793005 &+ 1442695040888963407
                return state >> 17
            }

            for i in 0..<256 {
                perm[i] = i
                values[i] = Double(next() & 0xFFFF) / 65535.0
            }
            // Fisher-Yates, so the table is a real permutation.
            for i in stride(from: 255, to: 0, by: -1) {
                let j = Int(next() % UInt64(i + 1))
                perm.swapAt(i, j)
            }
            for i in 0..<256 { perm[256 + i] = perm[i] }
        }

        private func corner(_ i: Int, _ j: Int) -> Double {
            values[perm[(perm[i & 255] &+ j) & 255]]
        }

        func value(_ x: Double) -> Double {
            let i = Int(floor(x))
            let f = x - floor(x)
            let s = f * f * (3 - 2 * f)
            let a = corner(i, 0)
            let b = corner(i &+ 1, 0)
            return a + (b - a) * s
        }

        func value(_ x: Double, _ y: Double) -> Double {
            let xi = Int(floor(x)), yi = Int(floor(y))
            let xf = x - floor(x), yf = y - floor(y)
            let u = xf * xf * (3 - 2 * xf)
            let v = yf * yf * (3 - 2 * yf)

            let a = corner(xi, yi)
            let b = corner(xi &+ 1, yi)
            let c = corner(xi, yi &+ 1)
            let d = corner(xi &+ 1, yi &+ 1)

            let top = a + (b - a) * u
            let bottom = c + (d - c) * u
            return top + (bottom - top) * v
        }

        func fbm(_ x: Double, _ y: Double, octaves: Int = 4) -> Double {
            var px = x, py = y
            var sum = 0.0, amp = 0.5, freq = 1.0, norm = 0.0
            for _ in 0..<octaves {
                sum += value(px * freq, py * freq) * amp
                norm += amp
                amp *= 0.5
                freq *= 2
                // Rotate each octave so the lattice never lines up with itself.
                (px, py) = (px * 0.8 - py * 0.6, px * 0.6 + py * 0.8)
            }
            return sum / norm
        }
    }

    // MARK: - Normal maps

    /// Turn a height function into a tangent-space normal map.
    ///
    /// Photorealism lives almost entirely in surface imperfection: brushing,
    /// orange peel, fine scratches, felt fibre. Writing those as height fields
    /// and differentiating here is far easier than hand-encoding normals, and
    /// it keeps every material in the library consistent.
    static func normalMap(size: Int,
                          strength: Double = 1.0,
                          tiles: Bool = true,
                          _ heightAt: (Double, Double) -> Double) -> CGImage {
        // Sample the height field once, then difference it, so each point is
        // evaluated a single time no matter how expensive it is.
        var heights = [Double](repeating: 0, count: size * size)
        for y in 0..<size {
            let v = (Double(y) + 0.5) / Double(size)
            for x in 0..<size {
                heights[y * size + x] = heightAt((Double(x) + 0.5) / Double(size), v)
            }
        }

        func sample(_ x: Int, _ y: Int) -> Double {
            if tiles {
                return heights[((y % size + size) % size) * size + ((x % size + size) % size)]
            }
            let cx = min(max(x, 0), size - 1)
            let cy = min(max(y, 0), size - 1)
            return heights[cy * size + cx]
        }

        var pixels = [UInt8](repeating: 0, count: size * size * 4)
        let scale = strength * Double(size) / 256.0
        for y in 0..<size {
            for x in 0..<size {
                let dx = (sample(x + 1, y) - sample(x - 1, y)) * scale
                let dy = (sample(x, y + 1) - sample(x, y - 1)) * scale
                let length = (dx * dx + dy * dy + 1).squareRoot()
                let i = (y * size + x) * 4
                pixels[i] = clamp8(((-dx / length) * 0.5 + 0.5) * 255)
                pixels[i + 1] = clamp8(((-dy / length) * 0.5 + 0.5) * 255)
                pixels[i + 2] = clamp8(((1 / length) * 0.5 + 0.5) * 255)
                pixels[i + 3] = 255
            }
        }
        return bitmap(width: size, height: size, pixels: pixels)
    }

    /// Single-channel map (roughness, metalness, ambient occlusion).
    static func grayscale(size: Int, _ body: (_ u: Double, _ v: Double) -> Double) -> CGImage {
        image(width: size, height: size) { u, v in
            let g = body(u, v)
            return (g, g, g, 1)
        }
    }

    // MARK: - Wood

    /// Plank-grain diffuse for the desk.
    ///
    /// Real timber is boards, not one continuous field: each plank gets its own
    /// ring phase and spacing, and a dark seam separates them. Without that the
    /// grain reads as corduroy.
    static func wood(base: RGB, grain: RGB, seed: UInt64 = 7, size: Int = 2048) -> CGImage {
        let n = Noise(seed: seed)
        let planks = 5.0
        return image(width: size, height: size / 2) { u, v in
            let board = floor(v * planks)
            let localV = v * planks - board
            // Per-board character, so no two planks match.
            let phase = n.value(board * 37.0) * 20.0
            let spacing = 11.0 + n.value(board * 13.0 + 5.0) * 11.0
            let warp = n.fbm(u * 2.4, v * 1.6, octaves: 4) - 0.5

            // Ring spacing drifts along the board: evenly spaced rings are
            // the giveaway that wood was generated rather than grown.
            let drift = n.fbm(localV * 3.0 + board * 11.0, u * 0.8, octaves: 3)
            let rings = sin((localV * spacing * (0.7 + drift * 0.6)
                             + phase + warp * 3.0) * .pi)
            // And every few rings is a latewood band, much darker than the rest.
            let band = n.value(localV * spacing * 0.5 + board * 23.0)
            var t = pow(abs(rings), 1.6 + band * 1.6) * (0.55 + band * 0.6)

            // Occasional cathedral figure where the saw crossed a knot.
            // Cathedral figure, where the saw crossed the grain at an angle.
            let figure = n.fbm(u * 1.1 + board * 7.0, localV * 1.7, octaves: 4)
            t += (figure - 0.5) * 0.42

            var r = Double(base.r) + (Double(grain.r) - Double(base.r)) * t
            var g = Double(base.g) + (Double(grain.g) - Double(base.g)) * t
            var b = Double(base.b) + (Double(grain.b) - Double(base.b)) * t

            // Open pores: short dark ticks running the length of the board.
            let pore = n.value(u * 520.0, board * 3.0 + localV * 6.0)
            if pore > 0.74 { r *= 0.78; g *= 0.78; b *= 0.81 }

            // The seam between boards.
            let seam = smooth(min(localV, 1 - localV), 0.0, 0.015)
            let shade = 0.45 + seam * 0.55
            return (r * shade, g * shade, b * shade, 1)
        }
    }

    /// Roughness companion for `wood` — pores read as matte, rings as satin.
    static func woodRoughness(seed: UInt64 = 7, size: Int = 1024) -> CGImage {
        let n = Noise(seed: seed &+ 11)
        let planks = 5.0
        return image(width: size, height: size / 2) { u, v in
            let board = floor(v * planks)
            let localV = v * planks - board
            let spacing = 11.0 + n.value(board * 13.0 + 5.0) * 11.0
            let rings = abs(sin((localV * spacing + n.value(board * 37.0) * 20.0) * .pi))
            let r = 0.38 + rings * 0.20 + n.value(u * 300, v * 7) * 0.06
            return (r, r, r, 1)
        }
    }

    // MARK: - Vinyl

    /// Near-black lacquer. Barely varies — the grooves do the talking.
    static func vinylDiffuse(size: Int = 512) -> CGImage {
        let n = Noise(seed: 42)
        return image(width: size, height: size) { u, v in
            let dx = u - 0.5, dy = v - 0.5
            let r = sqrt(dx * dx + dy * dy) * 2
            guard r <= 1.02 else { return (0, 0, 0, 0) }
            // Pressing marks: very faint, very fine.
            let speck = n.value(u * 900, v * 900) * 0.012
            let base = 0.030 + speck + (r > 0.96 ? 0.02 : 0)
            return (base, base * 0.98, base * 1.06, 1)
        }
    }

    /// Normal map for the groove spiral. This is what makes the record catch
    /// the key light in a band instead of looking like a black disc.
    static func vinylNormal(size: Int = 2048, grooves: Double = 96) -> CGImage {
        return image(width: size, height: size) { u, v in
            let dx = u - 0.5, dy = v - 0.5
            let r = sqrt(dx * dx + dy * dy) * 2          // 0 at spindle, 1 at rim
            guard r > 0.0001 else { return (0.5, 0.5, 1, 1) }

            // Grooves only exist between the label and the run-out.
            let inner = 0.33, outer = 0.97
            guard r > inner, r < outer else { return (0.5, 0.5, 1, 1) }

            // Height field is a triangle wave in radius: a V-shaped cut.
            let phase = (r - inner) / (outer - inner) * grooves
            let saw = phase - floor(phase)
            let slope = (saw < 0.5 ? 1.0 : -1.0) * 1.35

            // Tilt the normal along the radial direction.
            let nx = -slope * (dx / (r * 0.5))
            let ny = -slope * (dy / (r * 0.5))
            let len = sqrt(nx * nx + ny * ny + 1)
            return ((nx / len) * 0.5 + 0.5, (ny / len) * 0.5 + 0.5, (1 / len) * 0.5 + 0.5, 1)
        }
    }

    /// Slightly rougher in the groove band so the sheen reads as a soft arc.
    static func vinylRoughness(size: Int = 512) -> CGImage {
        image(width: size, height: size) { u, v in
            let dx = u - 0.5, dy = v - 0.5
            let r = sqrt(dx * dx + dy * dy) * 2
            let grooved = r > 0.33 && r < 0.97
            let g = grooved ? 0.24 : 0.12
            return (g, g, g, 1)
        }
    }

    // MARK: - Metal

    /// Concentric brushing for the platter top.
    static func brushedMetal(tint: RGB, size: Int = 512) -> CGImage {
        let n = Noise(seed: 303)
        return image(width: size, height: size) { u, v in
            let dx = u - 0.5, dy = v - 0.5
            let a = atan2(dy, dx)
            let r = sqrt(dx * dx + dy * dy) * 2
            let brush = n.value(a * 180.0 + r * 3.0) * 0.1 - 0.05
            return (Double(tint.r) + brush, Double(tint.g) + brush, Double(tint.b) + brush, 1)
        }
    }

    // MARK: - Environment and backdrop

    /// Equirectangular map for `scene.lightingEnvironment`. Gives the chrome
    /// and lacquer something to reflect; without it PBR surfaces look dead.
    static func environment(preset: ScenePreset, size: Int = 512) -> CGImage {
        let tint = preset.environmentTint
        let floorTone = preset.deskBase
        let keyU = 0.5 - atan2(Double(preset.key.position.x), Double(preset.key.position.z)) / (2 * .pi)
        return image(width: size * 2, height: size) { u, v in
            // v: 0 = zenith, 1 = nadir.
            let sky = max(0, 1 - v * 1.6)
            var r = Double(tint.r) * (0.25 + sky * 0.75)
            var g = Double(tint.g) * (0.25 + sky * 0.72)
            var b = Double(tint.b) * (0.28 + sky * 0.70)

            // The key light as a soft blob, so highlights have a shape.
            var du = abs(u - keyU.truncatingRemainder(dividingBy: 1.0))
            if du > 0.5 { du = 1 - du }
            let dv = v - 0.18
            let d = sqrt(du * du * 4 + dv * dv)
            let blob = max(0, 1 - d / 0.33)
            let glow = pow(blob, 2.2) * 0.85
            r += Double(preset.key.color.r) * glow
            g += Double(preset.key.color.g) * glow
            b += Double(preset.key.color.b) * glow

            // Bounce off the desk below.
            if v > 0.55 {
                let t = (v - 0.55) / 0.45
                r += Double(floorTone.r) * t * 0.5
                g += Double(floorTone.g) * t * 0.5
                b += Double(floorTone.b) * t * 0.5
            }
            return (r, g, b, 1)
        }
    }

    /// Vertical gradient behind everything, so the frame never shows void.
    static func backdrop(preset: ScenePreset, size: Int = 256) -> CGImage {
        let top = preset.wallTop, bottom = preset.wallBottom
        return image(width: 8, height: size) { _, v in
            let t = pow(v, 0.85)
            return (Double(top.r + (bottom.r - top.r) * t),
                    Double(top.g + (bottom.g - top.g) * t),
                    Double(top.b + (bottom.b - top.b) * t), 1)
        }
    }

    /// Plaster wall: flat colour plus enough tooth to catch raking light.
    static func plaster(preset: ScenePreset, size: Int = 512) -> CGImage {
        let n = Noise(seed: 881)
        let top = preset.wallTop, bottom = preset.wallBottom
        return image(width: size, height: size) { u, v in
            let t = pow(v, 0.9)
            let tooth = (n.fbm(u * 60, v * 60, octaves: 3) - 0.5) * 0.035
            return (Double(top.r + (bottom.r - top.r) * t) + tooth,
                    Double(top.g + (bottom.g - top.g) * t) + tooth,
                    Double(top.b + (bottom.b - top.b) * t) + tooth, 1)
        }
    }

    /// A window, as seen by a spot light.
    ///
    /// SceneKit multiplies a spot light by its gobo, so this turns a bare cone
    /// into panes of daylight falling across the room. Soft edges keep it from
    /// looking like a stencil.
    static func windowGobo(panes: Int = 2, rows: Int = 3, size: Int = 512) -> CGImage {
        image(width: size, height: size) { u, v in
            // Frame the window inside the cone, with falloff at the cone edge.
            let inset = 0.12
            let fu = (u - inset) / (1 - inset * 2)
            let fv = (v - inset) / (1 - inset * 2)
            guard fu > 0, fu < 1, fv > 0, fv < 1 else { return (0.06, 0.06, 0.06, 1) }

            // Mullion bars between panes.
            let barU = abs((fu * Double(panes)).truncatingRemainder(dividingBy: 1) - 0.5)
            let barV = abs((fv * Double(rows)).truncatingRemainder(dividingBy: 1) - 0.5)
            let edge = min(barU, barV)
            let bar = smooth(edge, 0.03, 0.09)

            // Soften the outer border so the light does not end on a hard line.
            let border = min(min(fu, 1 - fu), min(fv, 1 - fv))
            let frame = smooth(border, 0.0, 0.07)

            let value = 0.10 + bar * frame * 0.74
            return (value, value, value, 1)
        }
    }

    static func smooth(_ x: Double, _ a: Double, _ b: Double) -> Double {
        let t = min(max((x - a) / (b - a), 0), 1)
        return t * t * (3 - 2 * t)
    }

    // MARK: - Helpers

    static func solid(_ c: RGB) -> NSColor {
        NSColor(srgbRed: c.r, green: c.g, blue: c.b, alpha: 1)
    }

    static func nsImage(_ cg: CGImage) -> NSImage {
        NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }
}
