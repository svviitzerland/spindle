import AppKit
import CoreGraphics
import Foundation

/// Spindle ships no album covers.
///
/// When nothing is playing, the sleeve and label show artwork drawn from a
/// seed at launch: abstract, deterministic, and nobody's intellectual
/// property but yours.
enum GenerativeCover {

    struct Palette {
        let paper: RGB
        let ink: RGB
        let hues: [RGB]
    }

    private static let palettes: [Palette] = [
        Palette(paper: RGB(0.937, 0.890, 0.824), ink: RGB(0.106, 0.071, 0.063),
                hues: [RGB(0.831, 0.329, 0.184), RGB(0.910, 0.537, 0.294),
                       RGB(0.941, 0.627, 0.294), RGB(0.549, 0.184, 0.090)]),
        Palette(paper: RGB(0.902, 0.922, 0.949), ink: RGB(0.043, 0.063, 0.125),
                hues: [RGB(0.176, 0.290, 0.541), RGB(0.310, 0.525, 0.776),
                       RGB(0.561, 0.722, 0.878), RGB(0.075, 0.125, 0.247)]),
        Palette(paper: RGB(0.906, 0.914, 0.867), ink: RGB(0.071, 0.102, 0.078),
                hues: [RGB(0.290, 0.420, 0.263), RGB(0.525, 0.627, 0.416),
                       RGB(0.765, 0.773, 0.549), RGB(0.141, 0.196, 0.145)]),
        Palette(paper: RGB(0.925, 0.886, 0.918), ink: RGB(0.098, 0.059, 0.110),
                hues: [RGB(0.420, 0.235, 0.431), RGB(0.604, 0.310, 0.494),
                       RGB(0.816, 0.541, 0.690), RGB(0.227, 0.110, 0.200)]),
        Palette(paper: RGB(0.949, 0.925, 0.847), ink: RGB(0.102, 0.086, 0.043),
                hues: [RGB(0.788, 0.635, 0.153), RGB(0.890, 0.776, 0.361),
                       RGB(0.490, 0.392, 0.078), RGB(0.271, 0.227, 0.071)]),
        Palette(paper: RGB(0.894, 0.894, 0.902), ink: RGB(0.063, 0.063, 0.067),
                hues: [RGB(0.235, 0.235, 0.251), RGB(0.431, 0.431, 0.459),
                       RGB(0.608, 0.608, 0.639), RGB(0.114, 0.114, 0.125)]),
    ]

    private static let titlesA = ["Slow", "Night", "Paper", "Amber", "Static", "Low", "Velvet",
                                  "Hollow", "Quiet", "Iron", "Soft", "Late", "Glass", "Long"]
    private static let titlesB = ["Tape", "Signal", "Harbour", "Rooms", "Weather", "Hours",
                                  "Motion", "Letters", "Daylight", "Season", "Orbit", "Window"]
    private static let artists = ["Marlowe", "Fieldwork", "Halves", "Deviron", "Ostrand",
                                  "Meridian", "Kolbe", "Arbour", "Lowell Pace"]

    struct Cover {
        let image: NSImage
        let title: String
        let artist: String
    }

    /// Deterministic for a given seed: the same seed is the same record.
    static func make(seed: String, size: Int = 768) -> Cover {
        var rng = SplitMix(seed: hash(seed))
        let palette = palettes[rng.int(palettes.count)]
        let style = Style.allCases[rng.int(Style.allCases.count)]
        let title = "\(titlesA[rng.int(titlesA.count)]) \(titlesB[rng.int(titlesB.count)])"
        let artist = artists[rng.int(artists.count)]

        // Half the sleeves print on stock, half flood the whole square with a
        // colour. Pastel-on-white alone made every record look like a demo.
        let ground: RGB = rng.unit() < 0.45
            ? palette.paper
            : (rng.unit() < 0.5 ? palette.ink : palette.hues[3])

        let cg = Textures.draw(width: size, height: size) { ctx in
            ctx.setFillColor(color(ground))
            ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
            ctx.saveGState()
            ctx.scaleBy(x: CGFloat(size), y: CGFloat(size))
            style.draw(ctx, palette, ground, &rng)
            ctx.restoreGState()
            // Sleeves are printed, not pristine: a touch of wear at the edges.
            ctx.setStrokeColor(color(palette.ink, alpha: 0.18))
            ctx.setLineWidth(CGFloat(size) * 0.006)
            ctx.stroke(CGRect(x: 0, y: 0, width: size, height: size).insetBy(dx: 1, dy: 1))
        }
        return Cover(image: Textures.nsImage(cg), title: title, artist: artist)
    }

    // MARK: - Styles

    private enum Style: CaseIterable {
        case orbit, horizon, grid, split, wave, blocks

        func draw(_ ctx: CGContext, _ p: Palette, _ ground: RGB, _ rng: inout SplitMix) {
            // Always mark against the ground, never on top of it.
            let contrast = luminance(ground) > 0.5 ? p.ink : p.paper
            switch self {
            case .orbit:
                let rings = 5 + rng.int(6)
                let cx = 0.34 + rng.unit() * 0.32
                let cy = 0.36 + rng.unit() * 0.24
                let a = p.hues[rng.int(p.hues.count)]
                let b = p.hues[rng.int(p.hues.count)]
                for i in stride(from: rings, through: 1, by: -1) {
                    let t = CGFloat(i) / CGFloat(rings)
                    ctx.setFillColor(color(i % 2 == 0 ? a : b, alpha: 1.0 - t * 0.4))
                    ctx.fillEllipse(in: CGRect(x: cx - t * 0.46, y: cy - t * 0.46,
                                               width: t * 0.92, height: t * 0.92))
                }

            case .horizon:
                let line = 0.5 + rng.unit() * 0.18
                let sky = p.hues[rng.int(p.hues.count)]
                let sun = p.hues[rng.int(p.hues.count)]
                ctx.setFillColor(color(sky))
                ctx.fill(CGRect(x: 0, y: line, width: 1, height: 1 - line))
                ctx.setFillColor(color(sun))
                let sy = line + 0.08 + rng.unit() * 0.14
                ctx.fillEllipse(in: CGRect(x: 0.3, y: sy - 0.2, width: 0.4, height: 0.4))
                let bands = 4 + rng.int(5)
                ctx.setFillColor(color(p.ink))
                for i in 0..<bands {
                    let t = CGFloat(i) / CGFloat(bands)
                    let h = line / CGFloat(bands) * (0.75 - t * 0.5)
                    ctx.setAlpha(0.85 - t * 0.7)
                    ctx.fill(CGRect(x: 0, y: line - t * line - h, width: 1, height: h))
                }
                ctx.setAlpha(1)

            case .grid:
                let n = 5 + rng.int(5)
                let pad: CGFloat = 0.12
                let step = (1 - pad * 2) / CGFloat(n - 1)
                let dot = rng.unit() < 0.35 ? contrast : p.hues[rng.int(p.hues.count)]
                let accent = p.hues[rng.int(p.hues.count)]
                let odd = rng.int(n * n)
                var k = 0
                for r in 0..<n {
                    for c in 0..<n {
                        let d = hypot(CGFloat(r) - CGFloat(n - 1) / 2, CGFloat(c) - CGFloat(n - 1) / 2)
                        let rad = step * (0.42 - 0.3 * d / CGFloat(n))
                        ctx.setFillColor(color(k == odd ? accent : dot))
                        ctx.fillEllipse(in: CGRect(x: pad + CGFloat(c) * step - rad,
                                                   y: pad + CGFloat(r) * step - rad,
                                                   width: rad * 2, height: rad * 2))
                        k += 1
                    }
                }

            case .split:
                let a = p.hues[rng.int(p.hues.count)]
                let b = p.hues[rng.int(p.hues.count)]
                ctx.saveGState()
                ctx.translateBy(x: 0.5, y: 0.5)
                ctx.rotate(by: (rng.unit() - 0.5))
                ctx.setFillColor(color(a))
                ctx.fill(CGRect(x: -1, y: 0, width: 2, height: 1))
                ctx.setFillColor(color(b))
                ctx.fill(CGRect(x: -1, y: -1, width: 2, height: 1))
                ctx.restoreGState()
                let d = 0.14 + rng.unit() * 0.12
                ctx.setFillColor(color(contrast))
                ctx.fillEllipse(in: CGRect(x: 0.3 + rng.unit() * 0.3 - d,
                                           y: 0.3 + rng.unit() * 0.3 - d,
                                           width: d * 2, height: d * 2))

            case .wave:
                let lines = 16 + rng.int(18)
                let amp = 0.03 + rng.unit() * 0.06
                let freq = 1.4 + rng.unit() * 2.2
                ctx.setStrokeColor(color(rng.unit() < 0.4 ? contrast : p.hues[rng.int(p.hues.count)]))
                ctx.setLineWidth(0.016)
                for i in 0..<lines {
                    let base = (CGFloat(i) + 0.5) / CGFloat(lines)
                    let env = sin(base * .pi)
                    ctx.setAlpha(0.35 + 0.65 * env)
                    ctx.beginPath()
                    var x: CGFloat = 0
                    while x <= 1.0001 {
                        let y = base + sin(x * .pi * 2 * freq + CGFloat(i) * 0.35) * amp * env
                        x == 0 ? ctx.move(to: CGPoint(x: x, y: y)) : ctx.addLine(to: CGPoint(x: x, y: y))
                        x += 0.02
                    }
                    ctx.strokePath()
                }
                ctx.setAlpha(1)

            case .blocks:
                for _ in 0..<(3 + rng.int(4)) {
                    let x = rng.unit() * 0.7
                    let y = rng.unit() * 0.7
                    let w = 0.18 + rng.unit() * 0.34
                    ctx.setFillColor(color(p.hues[rng.int(p.hues.count)]))
                    if rng.unit() < 0.45 {
                        ctx.fillEllipse(in: CGRect(x: x, y: y, width: w, height: w))
                    } else {
                        ctx.fill(CGRect(x: x, y: y, width: w, height: 0.18 + rng.unit() * 0.32))
                    }
                }
            }
        }
    }

    // MARK: - Plumbing

    private static func luminance(_ c: RGB) -> CGFloat {
        0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
    }

    private static func color(_ c: RGB, alpha: CGFloat = 1) -> CGColor {
        CGColor(srgbRed: c.r, green: c.g, blue: c.b, alpha: alpha)
    }

    private static func hash(_ s: String) -> UInt64 {
        var h: UInt64 = 0xcbf29ce484222325
        for byte in s.utf8 {
            h ^= UInt64(byte)
            h = h &* 0x100000001b3
        }
        return h
    }

    /// Tiny splitmix64 so covers are reproducible across launches.
    struct SplitMix {
        private var state: UInt64
        init(seed: UInt64) { state = seed }

        mutating func next() -> UInt64 {
            state = state &+ 0x9E3779B97F4A7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
            z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
            return z ^ (z >> 31)
        }

        mutating func unit() -> CGFloat { CGFloat(next() >> 11) / CGFloat(1 << 53) }
        mutating func int(_ n: Int) -> Int { n <= 0 ? 0 : Int(next() % UInt64(n)) }
    }
}
