import CoreGraphics
import Foundation

/// The colour of a room, as one decision instead of seven.
///
/// Surfaces used to be seven loose fields on every preset, which made it
/// impossible to see a palette as a palette: you were reading thirty numbers
/// and hoping they got along. Grouping them means a scheme can be named,
/// reused and judged as a whole.
///
/// Each one follows the same shape interior designers use: a dominant neutral
/// covering most of the frame, a secondary that carries the furniture, and a
/// small accent that appears only in details. Greens and blues stay muted and
/// whites stay warm, because a blue-white wall reads as a screen rather than
/// as plaster.
struct Palette: Hashable, Sendable {
    var name: String

    /// The dominant surface: wall plaster, lit and shadowed.
    var wallTop: RGB
    var wallBottom: RGB

    /// The secondary: timber.
    var deskBase: RGB
    var deskGrain: RGB
    /// How much varnish is on it, 0 bare to 1 mirror.
    var deskGloss: CGFloat = 0.45

    /// The deck itself.
    var plinth: RGB
    var platter: RGB
    var metal: RGB

    /// The 10 per cent: the power indicator, the cartridge, small warm points.
    var accent: RGB
    /// Leaves, where a scene has any.
    var foliage: RGB
}

extension Palette {

    /// Warm cream plaster, walnut, brass. The default room.
    static let linen = Palette(
        name: "Linen",
        wallTop: RGB(0.790, 0.748, 0.684),
        wallBottom: RGB(0.648, 0.606, 0.544),
        deskBase: RGB(0.150, 0.100, 0.070),
        deskGrain: RGB(0.245, 0.170, 0.118),
        plinth: RGB(0.415, 0.395, 0.355),
        platter: RGB(0.560, 0.535, 0.485),
        metal: RGB(0.820, 0.780, 0.700),
        accent: RGB(0.920, 0.500, 0.190),
        foliage: RGB(0.225, 0.395, 0.205)
    )

    /// Warm white. Never blue-white: that reads as a screen, not plaster.
    static let paper = Palette(
        name: "Paper",
        wallTop: RGB(0.905, 0.893, 0.872),
        wallBottom: RGB(0.848, 0.835, 0.813),
        deskBase: RGB(0.175, 0.108, 0.065),
        deskGrain: RGB(0.285, 0.185, 0.112),
        deskGloss: 0.86,
        plinth: RGB(0.470, 0.455, 0.425),
        platter: RGB(0.560, 0.535, 0.485),
        metal: RGB(0.830, 0.795, 0.720),
        accent: RGB(0.920, 0.500, 0.190),
        foliage: RGB(0.225, 0.395, 0.205)
    )

    /// Grey-green walls with pale oak and brass. Sage is a neutral that
    /// happens to be green, which is why it carries a whole room without the
    /// room becoming about the colour.
    static let sage = Palette(
        name: "Sage",
        wallTop: RGB(0.618, 0.664, 0.566),
        wallBottom: RGB(0.512, 0.558, 0.468),
        deskBase: RGB(0.300, 0.218, 0.140),
        deskGrain: RGB(0.430, 0.330, 0.218),
        deskGloss: 0.55,
        plinth: RGB(0.528, 0.508, 0.462),
        platter: RGB(0.580, 0.555, 0.500),
        metal: RGB(0.800, 0.690, 0.470),
        accent: RGB(0.930, 0.530, 0.200),
        foliage: RGB(0.185, 0.330, 0.175)
    )

    /// Sun-faded clay. Chalky rather than saturated, with a muted green
    /// companion in the planting to keep all that warmth from going flat.
    static let clay = Palette(
        name: "Clay",
        wallTop: RGB(0.620, 0.418, 0.330),
        wallBottom: RGB(0.498, 0.318, 0.248),
        deskBase: RGB(0.285, 0.210, 0.148),
        deskGrain: RGB(0.405, 0.315, 0.225),
        deskGloss: 0.50,
        plinth: RGB(0.545, 0.525, 0.482),
        platter: RGB(0.575, 0.548, 0.495),
        metal: RGB(0.810, 0.700, 0.480),
        accent: RGB(0.950, 0.560, 0.220),
        foliage: RGB(0.200, 0.360, 0.235)
    )

    /// Bright white, light oak, brushed steel, and a lot of leaves. The green
    /// here is mass rather than tint: the walls stay neutral and the planting
    /// supplies all of the colour.
    static let conservatory = Palette(
        name: "Conservatory",
        wallTop: RGB(0.886, 0.884, 0.860),
        wallBottom: RGB(0.800, 0.802, 0.780),
        deskBase: RGB(0.330, 0.245, 0.165),
        deskGrain: RGB(0.460, 0.360, 0.248),
        deskGloss: 0.62,
        plinth: RGB(0.500, 0.492, 0.468),
        platter: RGB(0.600, 0.595, 0.575),
        metal: RGB(0.800, 0.780, 0.730),
        accent: RGB(0.900, 0.480, 0.180),
        foliage: RGB(0.250, 0.430, 0.210)
    )

    /// One lamp against a dark room.
    static let ember = Palette(
        name: "Ember",
        wallTop: RGB(0.160, 0.100, 0.070),
        wallBottom: RGB(0.070, 0.045, 0.030),
        deskBase: RGB(0.095, 0.058, 0.036),
        deskGrain: RGB(0.165, 0.100, 0.060),
        plinth: RGB(0.395, 0.370, 0.325),
        platter: RGB(0.550, 0.520, 0.465),
        metal: RGB(0.850, 0.720, 0.550),
        accent: RGB(0.980, 0.560, 0.220),
        foliage: RGB(0.120, 0.215, 0.140)
    )

    /// Blue hour outside, a warm lamp inside. Warm and cool opposites
    /// intensify each other, so neither has to be saturated to read.
    static let dusk = Palette(
        name: "Dusk",
        wallTop: RGB(0.228, 0.258, 0.318),
        wallBottom: RGB(0.150, 0.176, 0.228),
        deskBase: RGB(0.105, 0.072, 0.050),
        deskGrain: RGB(0.178, 0.124, 0.086),
        deskGloss: 0.70,
        plinth: RGB(0.400, 0.392, 0.374),
        platter: RGB(0.545, 0.530, 0.500),
        metal: RGB(0.790, 0.720, 0.590),
        accent: RGB(0.980, 0.570, 0.230),
        foliage: RGB(0.130, 0.235, 0.150)
    )

    /// Raw plaster and dark timber, for the view straight down.
    static let slate = Palette(
        name: "Slate",
        wallTop: RGB(0.330, 0.190, 0.090),
        wallBottom: RGB(0.220, 0.120, 0.050),
        deskBase: RGB(0.140, 0.090, 0.058),
        deskGrain: RGB(0.225, 0.150, 0.098),
        deskGloss: 0.58,
        plinth: RGB(0.400, 0.385, 0.350),
        platter: RGB(0.550, 0.520, 0.465),
        metal: RGB(0.840, 0.800, 0.720),
        accent: RGB(0.920, 0.500, 0.190),
        foliage: RGB(0.200, 0.350, 0.190)
    )

    static let all: [Palette] = [linen, paper, sage, clay, conservatory, ember, dusk, slate]
}

// MARK: - Small value types

/// A plain 3-component vector, so presets stay free of SceneKit imports.
struct Vec3: Hashable, Sendable {
    var x: CGFloat, y: CGFloat, z: CGFloat
    init(_ x: CGFloat, _ y: CGFloat, _ z: CGFloat) { self.x = x; self.y = y; self.z = z }
}

/// Colour in 0...1.
struct RGB: Hashable, Sendable {
    var r: CGFloat, g: CGFloat, b: CGFloat
    init(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) { self.r = r; self.g = g; self.b = b }

    func mixed(with other: RGB, _ t: CGFloat) -> RGB {
        RGB(r + (other.r - r) * t, g + (other.g - g) * t, b + (other.b - b) * t)
    }

    func scaled(_ f: CGFloat) -> RGB {
        RGB(min(r * f, 1), min(g * f, 1), min(b * f, 1))
    }
}
