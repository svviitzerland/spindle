import CoreGraphics
import Foundation

/// A scene is pure data: a palette, where the camera stands, how the room is
/// lit, and what else is on the desk.
///
/// Almost every field has a default, and the ones that depend on the palette
/// are derived from it rather than restated. A preset therefore says only
/// what makes it different from every other preset, which is the only way a
/// list of them stays readable once there are eight.
struct ScenePreset: Identifiable, Hashable, Sendable {

    // MARK: Identity

    var id: String
    var name: String
    var tagline: String
    var palette: Palette

    // MARK: Camera

    var cameraPosition: Vec3
    var cameraTarget: Vec3 = Vec3(0, 0.115, 0)
    /// Horizontal field of view in degrees. Smaller means a longer lens and
    /// the flatter, more photographic perspective that comes with it.
    var fieldOfView: CGFloat = 40
    /// Blur strength, not an aperture. SceneKit's defocus is far weaker than
    /// the optics this number describes: anything above about f/1.5 is
    /// indistinguishable from everything being in focus.
    var fStop: CGFloat = 0.85
    /// Tilt, in radians. A degree or two stops the frame feeling mechanical.
    var roll: CGFloat = 0
    /// Turn the deck off square. Nothing in a real room lines up with the
    /// camera, and perfect alignment reads as a diagram.
    var deckYaw: CGFloat = -0.038

    // MARK: Light

    var key: Light
    /// Unset means a cool, broad source on the camera side, which is what
    /// almost every scene wants.
    var fill: Light?
    /// Unset means light coming back up off the desk, tinted by it.
    var bounce: Light?

    var ambientColor: RGB?
    var ambientIntensity: CGFloat = 3.5
    var environmentTint: RGB?
    var environmentIntensity: CGFloat = 0.20

    var exposure: CGFloat = -0.55
    var vignette: CGFloat = 0.42
    var bloom: CGFloat = 0.10

    // MARK: Room

    /// Where lyrics sit in this room. Defaults to the top left, which is
    /// clear in most of them.
    var lyrics: TextPlacement = TextPlacement(x: 0.055, y: 0.115, alignment: .leading)

    var dressing: Dressing = Dressing()
    var dustCount: Int = 80
    var dustTint: RGB?

    // MARK: Derived

    /// Focus on whatever the camera is pointed at.
    var focusDistance: CGFloat {
        let dx = cameraTarget.x - cameraPosition.x
        let dy = cameraTarget.y - cameraPosition.y
        let dz = cameraTarget.z - cameraPosition.z
        return (dx * dx + dy * dy + dz * dz).squareRoot()
    }

    var fillLight: Light { fill ?? .defaultFill() }
    var bounceLight: Light { bounce ?? .defaultBounce(tintedBy: palette.deskGrain) }
    var ambient: RGB { ambientColor ?? palette.wallTop.mixed(with: RGB(0.80, 0.86, 1.0), 0.35) }
    var environment: RGB { environmentTint ?? key.color }
    var dustColor: RGB { dustTint ?? key.color }

    // Surfaces come from the palette. These keep the renderer from having to
    // know that palettes exist.
    var wallTop: RGB { palette.wallTop }
    var wallBottom: RGB { palette.wallBottom }
    var deskBase: RGB { palette.deskBase }
    var deskGrain: RGB { palette.deskGrain }
    var deskGloss: CGFloat { palette.deskGloss }
    var plinth: RGB { palette.plinth }
    var platter: RGB { palette.platter }
    var metal: RGB { palette.metal }
    var accent: RGB { palette.accent }
    var foliage: RGB { palette.foliage }
}

// MARK: - Light

extension ScenePreset {

    /// Area lights are the reason this stops looking like a game. A point
    /// light carves hard-edged shadows no room has; a rectangle the size of a
    /// window gives the soft, directional falloff of real light.
    struct Light: Hashable, Sendable {
        enum Kind: Hashable, Sendable {
            case area(width: CGFloat, height: CGFloat)
            case spot(angle: CGFloat)
            case omni
        }

        /// What the light arrives through, if anything. Spot lights only.
        enum Gobo: Hashable, Sendable {
            case none
            /// Panes of daylight.
            case window
            /// Venetian slats at an angle.
            case blinds
        }

        var kind: Kind
        var position: Vec3
        /// What the light aims at. Ignored for omni.
        var target: Vec3 = Vec3(0, 0.09, 0)
        var color: RGB
        /// Beware: SceneKit spreads an area light's intensity over its whole
        /// rectangle, so an area light needs a figure roughly an order of
        /// magnitude larger than a spot or omni to match it. These are only
        /// comparable within a kind.
        var intensity: CGFloat
        var castsShadow: Bool = true
        var shadowRadius: CGFloat = 12
        var gobo: Gobo = .none
    }
}

extension ScenePreset.Light {

    /// Daylight through a window, as the key.
    static func daylight(from position: Vec3,
                         toward target: Vec3 = Vec3(-0.08, 0.06, -0.26),
                         color: RGB = RGB(1.0, 0.962, 0.900),
                         intensity: CGFloat,
                         through gobo: Gobo = .window,
                         softness: CGFloat = 12) -> Self {
        Self(kind: .spot(angle: 106), position: position, target: target,
             color: color, intensity: intensity, shadowRadius: softness, gobo: gobo)
    }

    /// A lamp in the room, as the key.
    static func lamp(at position: Vec3,
                     color: RGB = RGB(1.0, 0.68, 0.37),
                     intensity: CGFloat,
                     softness: CGFloat = 16) -> Self {
        Self(kind: .omni, position: position, color: color,
             intensity: intensity, shadowRadius: softness)
    }

    /// A broad soft source, usually overhead.
    static func softbox(width: CGFloat, height: CGFloat,
                        at position: Vec3,
                        toward target: Vec3 = Vec3(0, 0.09, 0),
                        color: RGB,
                        intensity: CGFloat,
                        castsShadow: Bool = false,
                        softness: CGFloat = 10) -> Self {
        Self(kind: .area(width: width, height: height), position: position,
             target: target, color: color, intensity: intensity,
             castsShadow: castsShadow, shadowRadius: softness)
    }

    /// Cool, broad, on the camera side. Lifts the shadows without filling
    /// them in, and gives them a colour so they are not merely dark.
    static func defaultFill() -> Self {
        .softbox(width: 1.8, height: 1.2,
                 at: Vec3(0.92, 0.70, 1.05),
                 color: RGB(0.62, 0.72, 1.0),
                 intensity: 185)
    }

    /// Light coming back up off the desk, which no renderer gives you free
    /// without global illumination.
    static func defaultBounce(tintedBy wood: RGB) -> Self {
        .softbox(width: 1.5, height: 1.0,
                 at: Vec3(0, 0.015, 0.45),
                 toward: Vec3(0, 0.26, -0.10),
                 color: wood.scaled(1.9),
                 intensity: 80)
    }
}

// MARK: - Text placement

/// Where a block of text sits on screen.
///
/// Every scene puts its furniture somewhere different, so one fixed corner
/// would land on the deck in one room and in dead space in another. Each
/// preset names its own clear wall.
struct TextPlacement: Hashable, Sendable {
    /// Fractions of the screen, with 0,0 at the top left.
    var x: CGFloat
    var y: CGFloat
    var alignment: Alignment

    enum Alignment: Hashable, Sendable {
        case leading, center, trailing
    }
}

// MARK: - Dressing

extension ScenePreset {

    /// What else is in the room. A deck alone on a desk reads as a product
    /// shot; the clutter is what makes it somebody's room.
    struct Dressing: Hashable, Sendable {
        var wall = true
        var sleeve = true
        /// Show the sleeve in a wooden cradle rather than propped on the desk.
        var sleeveStand = false
        var stack = false
        var shelf = false
        /// A framed print hung on the wall.
        var framedArt = false
        /// A framed print standing on the desk.
        var leaningFrame = false
        var lamp = false
        var mug = false
        var plant = false
        /// A second, larger plant. For rooms where the green is the point.
        var bigPlant = false
        var headphones = false
        var books = false
    }
}
