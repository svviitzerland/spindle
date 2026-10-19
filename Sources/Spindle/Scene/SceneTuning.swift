import CoreGraphics
import Foundation

/// Live overrides for the lighting values baked into `ScenePreset`.
///
/// Getting a procedural scene to expose correctly takes a lot of small
/// adjustments, and rebuilding between each one is slow. These read from the
/// environment so you can sweep values from the shell:
///
///     SPINDLE_LIGHT=0.6 SPINDLE_EXPOSURE=-0.5 \
///       spindle render --scene lamplight --out /tmp/try.png
///
/// Once a value looks right, move it into the preset and drop the variable.
/// Unset, every one of these is a no-op.
enum SceneTuning {
    /// Multiplies every light's intensity.
    static let lightScale = number("SPINDLE_LIGHT") ?? 1.0
    /// Multiplies the image-based lighting contribution.
    static let environmentScale = number("SPINDLE_ENV") ?? 1.0
    /// Added to the preset's exposure offset, in stops.
    static let exposureOffset = number("SPINDLE_EXPOSURE")
    /// Disables tone mapping, which is the quickest way to see raw radiance
    /// and find out what is actually clipping.
    static let toneMapping = ProcessInfo.processInfo.environment["SPINDLE_HDR"] != "0"
    static let averageGray = number("SPINDLE_GRAY")
    static let whitePoint = number("SPINDLE_WHITE")

    private static func number(_ key: String) -> CGFloat? {
        guard let raw = ProcessInfo.processInfo.environment[key],
              let value = Double(raw) else { return nil }
        return CGFloat(value)
    }
}
