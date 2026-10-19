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
