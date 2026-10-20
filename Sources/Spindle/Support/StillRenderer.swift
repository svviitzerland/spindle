import AppKit
import Metal
import SceneKit

/// Renders one frame of a scene to a PNG, off screen.
///
/// This is how `spindle render` makes a static wallpaper, and it is also the
/// fastest way to iterate on lighting: you can look at a 2560-wide frame
/// without putting anything on the desktop.
enum StillRenderer {

    enum Failure: Error, CustomStringConvertible {
        case noMetalDevice
        case encodingFailed

        var description: String {
            switch self {
            case .noMetalDevice: return "no Metal device available"
            case .encodingFailed: return "could not encode PNG"
            }
        }
    }

    static func render(preset: ScenePreset,
                       size: CGSize,
                       seed: String = "spindle",
                       artwork: NSImage? = nil,
                       pressing: Pressing = .black,
                       progress: Double = 0.28,
                       atTime time: TimeInterval = 2.0) throws -> NSImage {
        guard let device = MTLCreateSystemDefaultDevice() else { throw Failure.noMetalDevice }

        let turntable = TurntableScene(preset: preset, seed: seed, pressing: pressing)
        if let artwork { turntable.setArtwork(artwork) }
        turntable.setProgress(progress, animated: false)

        let renderer = SCNRenderer(device: device, options: nil)
        renderer.scene = turntable.scene
        renderer.pointOfView = turntable.pointOfView
        renderer.autoenablesDefaultLighting = false
        // Give the particle system a moment of simulated time so the dust is
        // distributed rather than all newborn at the emitter.
        return renderer.snapshot(atTime: time, with: size, antialiasingMode: .multisampling4X)
    }

    /// Every scene on one sheet.
    ///
    /// Palettes can only really be judged against each other. Rendering them
    /// one at a time hides the fact that two rooms have drifted to the same
    /// temperature, or that one is a stop brighter than the rest.
    static func contactSheet(columns: Int = 2,
                             tileWidth: Int = 560,
                             pressing: Pressing = .black) throws -> NSImage {
        let presets = ScenePreset.all
        let tileHeight = tileWidth * 9 / 16
        let label = 30
        let gap = 14
        let rows = (presets.count + columns - 1) / columns

        let width = columns * tileWidth + (columns + 1) * gap
        let height = rows * (tileHeight + label) + (rows + 1) * gap

        var tiles: [(ScenePreset, NSImage)] = []
        for preset in presets {
            let image = try render(preset: preset,
                                   size: CGSize(width: tileWidth * 2, height: tileHeight * 2),
                                   pressing: pressing)
            tiles.append((preset, image))
        }

        let sheet = Textures.draw(width: width, height: height) { ctx in
            ctx.setFillColor(CGColor(gray: 0.08, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))

            for (index, tile) in tiles.enumerated() {
                let column = index % columns
                let row = index / columns
                let x = gap + column * (tileWidth + gap)
                // CoreGraphics counts from the bottom; lay the sheet out top down.
                let y = height - (row + 1) * (tileHeight + label + gap)

                if let cg = tile.1.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                    ctx.draw(cg, in: CGRect(x: x, y: y + label,
                                            width: tileWidth, height: tileHeight))
                }

                let text = "\(tile.0.name)  ·  \(tile.0.palette.name)  ·  \(tile.0.id)"
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .medium),
                    .foregroundColor: NSColor(white: 0.72, alpha: 1),
                ]
                let line = NSAttributedString(string: text, attributes: attributes)
                let graphics = NSGraphicsContext(cgContext: ctx, flipped: false)
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = graphics
                line.draw(at: NSPoint(x: x + 2, y: y + 7))
                NSGraphicsContext.restoreGraphicsState()
            }
        }
        return Textures.nsImage(sheet)
    }

    static func writePNG(_ image: NSImage, to url: URL) throws {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let data = rep.representation(using: .png, properties: [:]) else {
            throw Failure.encodingFailed
        }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try data.write(to: url)
    }

    /// Parse a "WIDTHxHEIGHT" argument.
    static func parseSize(_ text: String) -> CGSize? {
        let parts = text.lowercased().split(separator: "x")
        guard parts.count == 2,
              let w = Int(parts[0]), let h = Int(parts[1]),
              w > 0, h > 0, w <= 16384, h <= 16384 else { return nil }
        return CGSize(width: w, height: h)
    }
}
