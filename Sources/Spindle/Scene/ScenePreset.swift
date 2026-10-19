import CoreGraphics
import Foundation

/// A scene is pure data: where the camera stands, how the room is lit, what
/// the surfaces are made of and what else is on the desk. `TurntableScene`
/// reads this and nothing else, so a fourth mood is a new entry here rather
/// than new drawing code.
struct ScenePreset: Identifiable, Hashable, Sendable {

    /// Area lights are the whole reason this scene stops looking like a game.
    /// A point light carves hard-edged shadows no room ever has; a rectangle
    /// the size of a window gives the soft, directional falloff of real light.
    struct Light: Hashable, Sendable {
        enum Kind: Hashable, Sendable {
            case area(width: CGFloat, height: CGFloat)
            case spot(angle: CGFloat)
            case omni
        }

        var kind: Kind
        var position: Vec3
        /// What the light aims at. Ignored for omni.
        var target: Vec3 = Vec3(0, 0.09, 0)
        var color: RGB
        /// Beware: SceneKit spreads an area light's intensity over its whole
        /// rectangle, so an area light needs an intensity roughly an order of
        /// magnitude larger than a spot or omni to match it. The numbers below
        /// are not comparable across kinds; compare them within a kind.
        var intensity: CGFloat
        var castsShadow: Bool = true
        var shadowRadius: CGFloat = 12
        /// Project a window pattern through this light (spot lights only).
        var window: Bool = false
    }

    /// What else is in the room. A deck alone on a desk reads as a product
    /// shot; the clutter is what makes it somebody's room.
    struct Dressing: Hashable, Sendable {
        var wall = true
        var shelf = false
        var framedArt = false
        var sleeve = true
        var stack = true
        var lamp = false
        var mug = false
        var plant = false
        var headphones = false
        var books = false
    }

    var id: String
    var name: String
    var tagline: String

    // MARK: Camera
    var cameraPosition: Vec3
    /// Aimed with a look-at constraint, which is far easier to author — and to
    /// adjust — than a set of Euler angles.
    var cameraTarget: Vec3
    /// Horizontal field of view in degrees. Small numbers mean a long lens and
    /// the flatter, more photographic perspective that comes with it.
    var fieldOfView: CGFloat
    /// 0 disables depth of field. Smaller is shallower.
    var fStop: CGFloat
    /// Tilt, in radians. A degree or two stops the frame feeling mechanical.
    var roll: CGFloat = 0

    // MARK: Light
    var key: Light
    var fill: Light
    /// Light bounced back up off the desk, which no renderer gives you for
    /// free without global illumination.
    var bounce: Light
    var ambient: RGB
    var ambientIntensity: CGFloat
    var environmentTint: RGB
    var environmentIntensity: CGFloat
    var exposure: CGFloat
    var vignette: CGFloat
    var bloom: CGFloat

    // MARK: Surfaces
    var wallTop: RGB
    var wallBottom: RGB
    var deskBase: RGB
    var deskGrain: RGB
    var plinth: RGB
    var platter: RGB
    var metal: RGB

    var dressing: Dressing

    var dustCount: Int
    var dustColor: RGB

    /// Focus on whatever the camera is pointed at.
    var focusDistance: CGFloat {
        let dx = cameraTarget.x - cameraPosition.x
        let dy = cameraTarget.y - cameraPosition.y
        let dz = cameraTarget.z - cameraPosition.z
        return (dx * dx + dy * dy + dz * dz).squareRoot()
    }
}

extension ScenePreset {
    static let all: [ScenePreset] = [daylight, lamplight, overhead]

    static func preset(id: String) -> ScenePreset {
        all.first { $0.id == id } ?? daylight
    }

    /// Raking morning light, shot from near desk height on a long
    /// lens so the arm and the label sit sharp against a soft room.
    static let daylight = ScenePreset(
        id: "daylight",
        name: "Daylight",
        tagline: "Morning, and the window is doing most of the work.",
        cameraPosition: Vec3(0.735, 0.272, 1.215),
        cameraTarget: Vec3(-0.035, 0.090, 0.005),
        fieldOfView: 33,
        fStop: 2.6,
        roll: -0.012,
        key: .init(kind: .spot(angle: 96),
                   position: Vec3(-0.95, 1.05, 0.62),
                   target: Vec3(-0.05, 0.05, -0.05),
                   color: RGB(1.0, 0.955, 0.875),
                   intensity: 46, shadowRadius: 9, window: true),
        fill: .init(kind: .area(width: 1.6, height: 1.1),
                    position: Vec3(0.85, 0.62, 0.95),
                    target: Vec3(0, 0.08, 0),
                    color: RGB(0.80, 0.865, 1.0),
                    intensity: 230, castsShadow: false),
        bounce: .init(kind: .area(width: 1.4, height: 0.9),
                      position: Vec3(0.0, 0.015, 0.42),
                      target: Vec3(0, 0.22, -0.05),
                      color: RGB(0.62, 0.45, 0.30),
                      intensity: 95, castsShadow: false),
        ambient: RGB(0.95, 0.91, 0.84),
        ambientIntensity: 3.5,
        environmentTint: RGB(1.0, 0.96, 0.89),
        environmentIntensity: 0.20,
        exposure: -0.1,
        vignette: 0.42,
        bloom: 0.12,
        wallTop: RGB(0.760, 0.716, 0.652),
        wallBottom: RGB(0.620, 0.572, 0.496),
        deskBase: RGB(0.150, 0.100, 0.070),
        deskGrain: RGB(0.245, 0.170, 0.118),
        plinth: RGB(0.415, 0.395, 0.355),
        platter: RGB(0.560, 0.535, 0.485),
        metal: RGB(0.820, 0.780, 0.700),
        dressing: .init(wall: true, shelf: false, framedArt: false, sleeve: true,
                        stack: true, lamp: false, mug: true, plant: true,
                        headphones: false, books: true),
        dustCount: 90, dustColor: RGB(1.0, 0.96, 0.87)
    )

    /// Very low, very close, one warm lamp behind the deck so the chrome and
    /// the record rim catch a rim light and everything else falls away.
    static let lamplight = ScenePreset(
        id: "lamplight",
        name: "Lamplight",
        tagline: "One lamp, side two, nobody else awake.",
        cameraPosition: Vec3(-0.565, 0.335, 0.985),
        cameraTarget: Vec3(0.010, 0.085, -0.015),
        fieldOfView: 37,
        fStop: 1.8,
        roll: 0.016,
        key: .init(kind: .omni,
                   position: Vec3(0.540, 0.300, 0.040),
                   color: RGB(1.0, 0.68, 0.37),
                   intensity: 21, shadowRadius: 16),
        fill: .init(kind: .area(width: 1.2, height: 0.9),
                    position: Vec3(-0.95, 0.55, 0.85),
                    target: Vec3(0, 0.08, 0),
                    color: RGB(0.52, 0.56, 0.74),
                    intensity: 150, castsShadow: false),
        bounce: .init(kind: .area(width: 1.1, height: 0.7),
                      position: Vec3(0.18, 0.012, 0.22),
                      target: Vec3(0, 0.20, -0.05),
                      color: RGB(0.62, 0.38, 0.20),
                      intensity: 85, castsShadow: false),
        ambient: RGB(0.42, 0.33, 0.28),
        ambientIntensity: 3.0,
        environmentTint: RGB(0.85, 0.55, 0.30),
        environmentIntensity: 0.10,
        exposure: 0.15,
        vignette: 0.80,
        bloom: 0.26,
        wallTop: RGB(0.16, 0.10, 0.07),
        wallBottom: RGB(0.07, 0.045, 0.03),
        deskBase: RGB(0.095, 0.058, 0.036),
        deskGrain: RGB(0.165, 0.100, 0.060),
        plinth: RGB(0.395, 0.370, 0.325),
        platter: RGB(0.550, 0.520, 0.465),
        metal: RGB(0.850, 0.720, 0.550),
        dressing: .init(wall: true, shelf: false, framedArt: false, sleeve: true,
                        stack: true, lamp: true, mug: false, plant: false,
                        headphones: true, books: false),
        dustCount: 150, dustColor: RGB(1.0, 0.80, 0.58)
    )

    /// Nearly overhead, but tilted and rolled: a plan view is a diagram, and a
    /// few degrees off axis is a photograph.
    static let overhead = ScenePreset(
        id: "overhead",
        name: "Overhead",
        tagline: "Straight down on the deck, nothing else in the frame.",
        cameraPosition: Vec3(0.185, 1.300, 0.585),
        cameraTarget: Vec3(-0.030, 0.090, -0.005),
        fieldOfView: 31,
        fStop: 5.0,
        roll: 0.040,
        key: .init(kind: .area(width: 1.3, height: 1.0),
                   position: Vec3(-0.72, 0.95, 0.52),
                   target: Vec3(-0.05, 0.08, 0),
                   color: RGB(1.0, 0.945, 0.855),
                   intensity: 780, shadowRadius: 7),
        fill: .init(kind: .area(width: 1.4, height: 1.0),
                    position: Vec3(0.78, 0.60, -0.42),
                    target: Vec3(0, 0.08, 0),
                    color: RGB(0.93, 0.87, 0.80),
                    intensity: 195, castsShadow: false),
        bounce: .init(kind: .area(width: 1.0, height: 0.8),
                      position: Vec3(0.0, 0.012, 0.35),
                      target: Vec3(0, 0.22, 0),
                      color: RGB(0.60, 0.42, 0.26),
                      intensity: 88, castsShadow: false),
        ambient: RGB(0.88, 0.82, 0.72),
        ambientIntensity: 52,
        environmentTint: RGB(0.98, 0.92, 0.83),
        environmentIntensity: 0.16,
        exposure: -0.2,
        vignette: 0.55,
        bloom: 0.10,
        wallTop: RGB(0.33, 0.19, 0.09),
        wallBottom: RGB(0.22, 0.12, 0.05),
        deskBase: RGB(0.140, 0.090, 0.058),
        deskGrain: RGB(0.225, 0.150, 0.098),
        plinth: RGB(0.400, 0.385, 0.350),
        platter: RGB(0.550, 0.520, 0.465),
        metal: RGB(0.840, 0.800, 0.720),
        dressing: .init(wall: false, shelf: false, framedArt: false, sleeve: false,
                        stack: false, lamp: false, mug: true, plant: false,
                        headphones: false, books: false),
        dustCount: 40, dustColor: RGB(1.0, 0.93, 0.80)
    )
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
