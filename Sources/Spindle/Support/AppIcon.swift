import AppKit
import CoreGraphics
import Foundation

/// The app icon is drawn, not stored, so the repository holds no binaries.
/// `spindle icon --out dist/icon` writes `dist/icon.icns`.
///
/// One record, seen flat on, lit from the upper left. Everything is sized as a
/// fraction of the canvas so the same code produces the 16 pt tile and the
/// 512 pt @2x master, and the detail that would turn to mush at small sizes
/// (grooves, the inner label ring) simply drops out below a threshold.
enum AppIcon {

    // Proportions from Apple's macOS icon grid: the rounded square occupies
    // 824 of a 1024 canvas, leaving room for the shadow.
    private enum Grid {
        static let plateInset: CGFloat = 100.0 / 1024.0
        static let cornerRadius: CGFloat = 185.0 / 824.0
        static let discRadius: CGFloat = 282.0 / 1024.0
        static let labelRadius: CGFloat = 0.325      // of the disc
        static let holeRadius: CGFloat = 0.082       // of the disc
    }

    private enum Palette {
        static let plateTop = CGColor(srgbRed: 0.965, green: 0.918, blue: 0.843, alpha: 1)
        static let plateBottom = CGColor(srgbRed: 0.820, green: 0.698, blue: 0.541, alpha: 1)
        static let daylight = CGColor(srgbRed: 1.0, green: 0.985, blue: 0.945, alpha: 0.85)
        static let vinyl = CGColor(srgbRed: 0.078, green: 0.071, blue: 0.086, alpha: 1)
        static let vinylEdge = CGColor(srgbRed: 0.035, green: 0.031, blue: 0.042, alpha: 1)
        static let sheen = CGColor(srgbRed: 1.0, green: 0.945, blue: 0.855, alpha: 1)
        static let label = CGColor(srgbRed: 0.886, green: 0.639, blue: 0.290, alpha: 1)
        static let labelShade = CGColor(srgbRed: 0.769, green: 0.510, blue: 0.212, alpha: 1)
        static let hole = CGColor(srgbRed: 0.090, green: 0.071, blue: 0.055, alpha: 1)
    }

    static func image(size: Int) -> CGImage {
        Textures.draw(width: size, height: size) { ctx in
            let s = CGFloat(size)
            let plate = CGRect(x: 0, y: 0, width: s, height: s)
                .insetBy(dx: s * Grid.plateInset, dy: s * Grid.plateInset)
            let path = squircle(in: plate, radius: plate.width * Grid.cornerRadius)

            drawPlateShadow(ctx, path: path, scale: s)
            ctx.saveGState()
            ctx.addPath(path)
            ctx.clip()
            drawPlate(ctx, rect: plate, scale: s)
            ctx.restoreGState()

            drawDisc(ctx, centre: CGPoint(x: s / 2, y: s / 2),
                     radius: s * Grid.discRadius, scale: s)

            // A hairline along the top edge, the way a physical tile catches
            // the light. Too fine to resolve on the smallest tiles.
            if s >= 64 {
                ctx.saveGState()
                ctx.addPath(path)
                ctx.setStrokeColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.30))
                ctx.setLineWidth(s * 0.004)
                ctx.strokePath()
                ctx.restoreGState()
            }
        }
    }

    // MARK: Plate

    /// Apple's rounded rectangle is a superellipse, not a circular-cornered
    /// rect: the curvature runs continuously into the straight edges instead
    /// of starting abruptly. The difference is small and unmistakable.
    private static func squircle(in rect: CGRect, radius: CGFloat) -> CGPath {
        let path = CGMutablePath()
        let a = rect.width / 2, b = rect.height / 2
        let cx = rect.midX, cy = rect.midY
        // Apple's shape sits near n = 5. Deriving the exponent from a corner
        // radius gave a much rounder figure whose sides visibly bowed, so the
        // radius argument only nudges it either side of that.
        let n = max(2.5, 5.0 * (1 + (radius / (rect.width * Grid.cornerRadius) - 1) * -0.35))
        let steps = 512

        for step in 0...steps {
            let t = CGFloat(step) / CGFloat(steps) * 2 * .pi
            let c = cos(t), si = sin(t)
            let x = cx + a * copysign(pow(abs(c), 2 / n), c)
            let y = cy + b * copysign(pow(abs(si), 2 / n), si)
            step == 0 ? path.move(to: CGPoint(x: x, y: y))
                      : path.addLine(to: CGPoint(x: x, y: y))
        }
        path.closeSubpath()
        return path
    }

    private static func drawPlateShadow(_ ctx: CGContext, path: CGPath, scale s: CGFloat) {
        guard s >= 32 else { return }
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.012),
                      blur: s * 0.035,
                      color: CGColor(srgbRed: 0.18, green: 0.12, blue: 0.07, alpha: 0.42))
        ctx.addPath(path)
        ctx.setFillColor(Palette.plateBottom)
        ctx.fillPath()
        ctx.restoreGState()
    }

    /// Warm paper, with the daylight of the Daylight scene falling
    /// across it from the upper left.
    private static func drawPlate(_ ctx: CGContext, rect: CGRect, scale s: CGFloat) {
        let base = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                              colors: [Palette.plateTop, Palette.plateBottom] as CFArray,
                              locations: [0, 1])!
        ctx.drawLinearGradient(base,
                               start: CGPoint(x: rect.minX, y: rect.maxY),
                               end: CGPoint(x: rect.maxX, y: rect.minY),
                               options: [])

        let glow = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                              colors: [Palette.daylight,
                                       CGColor(srgbRed: 1, green: 0.985, blue: 0.945, alpha: 0)] as CFArray,
                              locations: [0, 1])!
        ctx.drawRadialGradient(glow,
                               startCenter: CGPoint(x: rect.minX + rect.width * 0.18,
                                                    y: rect.maxY - rect.height * 0.12),
                               startRadius: 0,
                               endCenter: CGPoint(x: rect.minX + rect.width * 0.30,
                                                  y: rect.maxY - rect.height * 0.22),
                               endRadius: rect.width * 0.82,
                               options: [])
    }

    // MARK: Record

    private static func drawDisc(_ ctx: CGContext, centre c: CGPoint,
                                 radius r: CGFloat, scale s: CGFloat) {
        let bounds = CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)

        // Contact shadow, so the record sits on the plate rather than in it.
        if s >= 32 {
            ctx.saveGState()
            ctx.setShadow(offset: CGSize(width: 0, height: -r * 0.055),
                          blur: r * 0.14,
                          color: CGColor(srgbRed: 0.22, green: 0.14, blue: 0.07, alpha: 0.46))
            ctx.setFillColor(Palette.vinyl)
            ctx.fillEllipse(in: bounds)
            ctx.restoreGState()
        }

        // The lacquer itself, very slightly lighter at the centre.
        ctx.saveGState()
        ctx.addEllipse(in: bounds)
        ctx.clip()
        let body = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                              colors: [Palette.vinyl, Palette.vinylEdge] as CFArray,
                              locations: [0, 1])!
        ctx.drawRadialGradient(body,
                               startCenter: CGPoint(x: c.x - r * 0.3, y: c.y + r * 0.3),
                               startRadius: 0,
                               endCenter: c, endRadius: r,
                               options: [.drawsAfterEndLocation])

        if s >= 48 { drawGrooves(ctx, centre: c, radius: r) }
        drawSheen(ctx, centre: c, radius: r)
        ctx.restoreGState()

        drawLabel(ctx, centre: c, radius: r, scale: s)

        // A bright hairline on the rim separates the record from the plate.
        if s >= 48 {
            ctx.setStrokeColor(CGColor(srgbRed: 1, green: 0.94, blue: 0.84, alpha: 0.22))
            ctx.setLineWidth(max(0.6, r * 0.012))
            ctx.strokeEllipse(in: bounds.insetBy(dx: r * 0.006, dy: r * 0.006))
        }
    }

    private static func drawGrooves(_ ctx: CGContext, centre c: CGPoint, radius r: CGFloat) {
        let inner = r * 0.38, outer = r * 0.94
        let spacing = r * 0.052
        ctx.setLineWidth(max(0.5, r * 0.009))
        var ring = inner
        while ring <= outer {
            // Fade the grooves out toward the rim so the eye settles on the
            // label rather than on the texture.
            let t = (ring - inner) / (outer - inner)
            let alpha = 0.055 + 0.045 * (1 - t)
            ctx.setStrokeColor(CGColor(srgbRed: 0.92, green: 0.86, blue: 0.76, alpha: alpha))
            ctx.strokeEllipse(in: CGRect(x: c.x - ring, y: c.y - ring,
                                         width: ring * 2, height: ring * 2))
            ring += spacing
        }
    }

    /// The soft band of light a record throws back at a window. This is the
    /// one gesture that stops the disc reading as a flat black circle.
    private static func drawSheen(_ ctx: CGContext, centre c: CGPoint, radius r: CGFloat) {
        ctx.saveGState()
        let clear = CGColor(srgbRed: 1, green: 0.945, blue: 0.855, alpha: 0)
        let sheen = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                               colors: [Palette.sheen.copy(alpha: 0.26)!,
                                        Palette.sheen.copy(alpha: 0.05)!,
                                        clear] as CFArray,
                               locations: [0, 0.45, 1])!
        ctx.drawRadialGradient(sheen,
                               startCenter: CGPoint(x: c.x - r * 0.52, y: c.y + r * 0.56),
                               startRadius: 0,
                               endCenter: CGPoint(x: c.x - r * 0.22, y: c.y + r * 0.24),
                               endRadius: r * 1.18,
                               options: [])
        ctx.restoreGState()
    }

    private static func drawLabel(_ ctx: CGContext, centre c: CGPoint,
                                  radius r: CGFloat, scale s: CGFloat) {
        let labelRadius = r * Grid.labelRadius
        let bounds = CGRect(x: c.x - labelRadius, y: c.y - labelRadius,
                            width: labelRadius * 2, height: labelRadius * 2)

        ctx.saveGState()
        ctx.addEllipse(in: bounds)
        ctx.clip()
        let paper = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                               colors: [Palette.label, Palette.labelShade] as CFArray,
                               locations: [0, 1])!
        ctx.drawLinearGradient(paper,
                               start: CGPoint(x: bounds.minX, y: bounds.maxY),
                               end: CGPoint(x: bounds.maxX, y: bounds.minY),
                               options: [])
        ctx.restoreGState()

        // The printed ring every label carries. Dropped on small tiles, where
        // it would only muddy the amber.
        if s >= 128 {
            ctx.setStrokeColor(CGColor(srgbRed: 1, green: 0.93, blue: 0.80, alpha: 0.38))
            ctx.setLineWidth(max(0.5, labelRadius * 0.045))
            ctx.strokeEllipse(in: bounds.insetBy(dx: labelRadius * 0.22,
                                                 dy: labelRadius * 0.22))
        }

        let holeRadius = r * Grid.holeRadius
        ctx.setFillColor(Palette.hole)
        ctx.fillEllipse(in: CGRect(x: c.x - holeRadius, y: c.y - holeRadius,
                                   width: holeRadius * 2, height: holeRadius * 2))
    }

    // MARK: Export

    /// Write `<basePath>.icns` via iconutil, leaving the .iconset behind only
    /// if the conversion fails so the failure is inspectable.
    @discardableResult
    static func writeICNS(toBasePath basePath: String) throws -> URL {
        let fm = FileManager.default
        let iconset = URL(fileURLWithPath: basePath + ".iconset")
        let icns = URL(fileURLWithPath: basePath + ".icns")
        try? fm.removeItem(at: iconset)
        try fm.createDirectory(at: iconset, withIntermediateDirectories: true)

        for base in [16, 32, 128, 256, 512] {
            for scale in [1, 2] {
                let pixels = base * scale
                let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
                let cg = image(size: pixels)
                try StillRenderer.writePNG(Textures.nsImage(cg),
                                           to: iconset.appendingPathComponent(name))
            }
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
        process.arguments = ["-c", "icns", iconset.path, "-o", icns.path]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw NSError(domain: "Spindle", code: Int(process.terminationStatus),
                          userInfo: [NSLocalizedDescriptionKey: "iconutil failed; left \(iconset.path)"])
        }
        try? fm.removeItem(at: iconset)
        return icns
    }
}
