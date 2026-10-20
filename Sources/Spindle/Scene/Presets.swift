import CoreGraphics

/// The scenes Spindle ships.
///
/// Each one is a palette, a camera and a key light. Everything else falls back
/// to a default derived from those, so what you read here is only what makes
/// each room different from the others.
extension ScenePreset {

    static let all: [ScenePreset] = [
        daylight, gallery, sage, clay, conservatory, dusk, lamplight, overhead,
    ]

    static func preset(id: String) -> ScenePreset {
        all.first { $0.id == id } ?? daylight
    }

    // MARK: Daylight

    /// Raking morning light, shot from near desk height on a long lens so the
    /// arm and the label sit sharp against a soft room.
    static let daylight = ScenePreset(
        id: "daylight",
        name: "Daylight",
        tagline: "Morning, and the window is doing most of the work.",
        palette: .linen,
        cameraPosition: Vec3(0.735, 0.272, 1.215),
        cameraTarget: Vec3(-0.035, 0.090, 0.005),
        fieldOfView: 33,
        fStop: 0.80,
        roll: -0.012,
        key: .daylight(from: Vec3(-0.95, 1.05, 0.62), intensity: 46, softness: 9),
        exposure: -0.42,
        vignette: 0.40,
        // The deck sits right of centre with the sleeve beside it; the wall
        // above and left of both is the only space wide enough.
        lyrics: TextPlacement(x: 0.055, y: 0.125, alignment: .leading),
        dressing: .init(sleeve: true, stack: true, mug: true, plant: true, books: true),
        dustCount: 90
    )

    // MARK: Gallery

    /// A white room seen square on, with the blinds half open. The wall does
    /// the work: bare plaster is dull, plaster with slats across it is the
    /// whole picture.
    static let gallery = ScenePreset(
        id: "gallery",
        name: "Gallery",
        tagline: "A white room, a wooden desk, the blinds half open.",
        palette: .paper,
        cameraPosition: Vec3(0.050, 0.460, 1.620),
        cameraTarget: Vec3(0.000, 0.220, -0.020),
        fieldOfView: 42,
        fStop: 0.62,
        roll: -0.008,
        key: .daylight(from: Vec3(-1.05, 1.08, 0.72),
                       toward: Vec3(-0.10, 0.10, -0.34),
                       color: RGB(1.0, 0.968, 0.912),
                       intensity: 44, through: .blinds, softness: 13),
        ambientColor: RGB(0.78, 0.83, 0.95),
        ambientIntensity: 3,
        environmentIntensity: 0.17,
        exposure: -0.62,
        vignette: 0.44,
        bloom: 0.07,
        // Blinds cross the middle of the wall and the print hangs upper
        // right, so the text keeps to the quiet corner on the left.
        lyrics: TextPlacement(x: 0.05, y: 0.105, alignment: .leading),
        dressing: .init(sleeve: true, sleeveStand: true, framedArt: true),
        dustCount: 70
    )

    // MARK: Sage

    /// Grey-green walls, pale oak, brass. Sage carries a whole room without
    /// the room becoming about the colour, which is exactly what you want
    /// behind a black record.
    static let sage = ScenePreset(
        id: "sage",
        name: "Sage",
        tagline: "Green walls, pale oak, and a quiet afternoon.",
        palette: .sage,
        cameraPosition: Vec3(-0.605, 0.318, 1.265),
        cameraTarget: Vec3(0.020, 0.108, 0.000),
        fieldOfView: 36,
        fStop: 0.78,
        roll: 0.010,
        deckYaw: 0.046,
        key: .daylight(from: Vec3(0.98, 1.02, 0.68),
                       toward: Vec3(0.06, 0.06, -0.24),
                       color: RGB(1.0, 0.958, 0.890),
                       intensity: 45, softness: 11),
        exposure: -0.46,
        vignette: 0.38,
        // The camera is round to the left here, which pushes the deck right
        // and leaves the upper wall open.
        lyrics: TextPlacement(x: 0.058, y: 0.115, alignment: .leading),
        dressing: .init(sleeve: true, sleeveStand: true, mug: true, plant: true, books: true),
        dustCount: 85
    )

    // MARK: Clay

    /// Sun-faded terracotta, late in the day. All that warmth needs a cool
    /// companion or it goes flat, so the planting is the only green in frame
    /// and it is doing a job.
    static let clay = ScenePreset(
        id: "clay",
        name: "Clay",
        tagline: "Terracotta plaster, low sun, one plant for balance.",
        palette: .clay,
        cameraPosition: Vec3(0.235, 0.300, 1.325),
        cameraTarget: Vec3(-0.020, 0.105, 0.000),
        fieldOfView: 38,
        fStop: 0.75,
        roll: -0.014,
        key: .daylight(from: Vec3(-1.10, 0.72, 0.58),
                       toward: Vec3(-0.06, 0.08, -0.30),
                       color: RGB(1.0, 0.880, 0.735),
                       intensity: 43, through: .blinds, softness: 15),
        // A cool ambient keeps clay from turning muddy; a warm one on warm
        // walls leaves the whole frame at a single temperature.
        ambientColor: RGB(0.62, 0.72, 0.95),
        ambientIntensity: 4.6,
        exposure: -0.56,
        vignette: 0.46,
        bloom: 0.12,
        // Sleeve and planting take the left of frame, so the text crosses to
        // the bare clay on the right.
        lyrics: TextPlacement(x: 0.945, y: 0.125, alignment: .trailing),
        dressing: .init(sleeve: true, sleeveStand: true, mug: true,
                        plant: true, bigPlant: true),
        dustCount: 110
    )

    // MARK: Conservatory

    /// Bright white and a lot of leaves. The green here is mass rather than
    /// tint: the walls stay neutral and the planting supplies all the colour.
    static let conservatory = ScenePreset(
        id: "conservatory",
        name: "Conservatory",
        tagline: "White walls, light oak, and more plants than sense.",
        palette: .conservatory,
        cameraPosition: Vec3(0.085, 0.400, 1.495),
        cameraTarget: Vec3(0.000, 0.182, -0.020),
        fieldOfView: 41,
        fStop: 0.70,
        roll: 0.006,
        key: .daylight(from: Vec3(-0.92, 1.12, 0.80),
                       toward: Vec3(-0.04, 0.10, -0.30),
                       color: RGB(1.0, 0.978, 0.942),
                       intensity: 52, softness: 14),
        ambientColor: RGB(0.82, 0.88, 0.96),
        ambientIntensity: 5,
        environmentIntensity: 0.24,
        exposure: -0.55,
        vignette: 0.34,
        bloom: 0.08,
        // Planting on both sides. The gap is the middle of the wall.
        lyrics: TextPlacement(x: 0.5, y: 0.1, alignment: .center),
        dressing: .init(sleeve: true, sleeveStand: true, mug: true,
                        plant: true, bigPlant: true),
        dustCount: 60
    )

    // MARK: Dusk

    /// Blue hour through the window, one warm lamp inside. Warm and cool
    /// opposites intensify each other, so neither has to be saturated.
    static let dusk = ScenePreset(
        id: "dusk",
        name: "Dusk",
        tagline: "Blue outside, warm inside, the last side of the night.",
        palette: .dusk,
        cameraPosition: Vec3(0.455, 0.292, 1.145),
        cameraTarget: Vec3(-0.020, 0.100, 0.000),
        fieldOfView: 38,
        fStop: 0.82,
        roll: 0.012,
        // Blue hour is a blue room with a warm lamp in it, so the window has
        // to be the key and the lamp the accent. Having them the other way
        // round made the lamp wash the walls and the two colours collided
        // into olive.
        key: .softbox(width: 2.6, height: 1.8,
                      at: Vec3(-1.00, 0.92, 0.30),
                      toward: Vec3(-0.10, 0.34, -0.56),
                      color: RGB(0.40, 0.54, 0.92),
                      intensity: 760, castsShadow: true, softness: 20),
        // Tiny, because an omni and an area light are not on the same scale.
        // At 11 this buried a 760 area key completely and turned the room
        // brown; the blue was working all along.
        fill: .lamp(at: Vec3(0.600, 0.205, 0.150),
                    color: RGB(1.0, 0.640, 0.330),
                    intensity: 2.6, softness: 14),
        bounce: .softbox(width: 1.4, height: 0.9,
                         at: Vec3(0, 0.015, 0.42),
                         toward: Vec3(0, 0.26, -0.12),
                         color: RGB(0.30, 0.26, 0.34),
                         intensity: 55),
        ambientColor: RGB(0.34, 0.46, 0.76),
        ambientIntensity: 5.5,
        environmentTint: RGB(0.40, 0.54, 0.90),
        environmentIntensity: 0.24,
        exposure: 0.10,
        vignette: 0.58,
        bloom: 0.20,
        // The lamp owns the right of the desk but not the wall above it, and
        // dark blue plaster is the best ground pale text ever gets.
        lyrics: TextPlacement(x: 0.945, y: 0.14, alignment: .trailing),
        dressing: .init(sleeve: true, sleeveStand: true, lamp: true, plant: true),
        dustCount: 120
    )

    // MARK: Lamplight

    /// Very low, very close, one warm lamp behind the deck so the chrome and
    /// the record rim catch a rim light and everything else falls away.
    static let lamplight = ScenePreset(
        id: "lamplight",
        name: "Lamplight",
        tagline: "One lamp, side two, nobody else awake.",
        palette: .ember,
        cameraPosition: Vec3(-0.565, 0.335, 0.985),
        cameraTarget: Vec3(0.010, 0.085, -0.015),
        fieldOfView: 37,
        fStop: 1.00,
        roll: 0.016,
        key: .lamp(at: Vec3(0.540, 0.300, 0.040), intensity: 21),
        fill: .softbox(width: 1.2, height: 0.9,
                       at: Vec3(-0.95, 0.55, 0.85),
                       color: RGB(0.52, 0.56, 0.74),
                       intensity: 150),
        ambientColor: RGB(0.42, 0.33, 0.28),
        ambientIntensity: 3.0,
        environmentTint: RGB(0.85, 0.55, 0.30),
        environmentIntensity: 0.10,
        exposure: 0.15,
        vignette: 0.80,
        bloom: 0.26,
        // Everything falls off into shadow on the left, which is exactly
        // where pale text wants to be.
        lyrics: TextPlacement(x: 0.055, y: 0.13, alignment: .leading),
        dressing: .init(sleeve: true, stack: true, lamp: true, headphones: true),
        dustCount: 150
    )

    // MARK: Overhead

    /// Nearly overhead, but tilted and rolled: a plan view is a diagram, and
    /// a few degrees off axis is a photograph.
    static let overhead = ScenePreset(
        id: "overhead",
        name: "Overhead",
        tagline: "Straight down on the deck, nothing else in the frame.",
        palette: .slate,
        cameraPosition: Vec3(0.185, 1.300, 0.585),
        cameraTarget: Vec3(-0.030, 0.090, -0.005),
        fieldOfView: 31,
        fStop: 1.20,
        roll: 0.040,
        key: .softbox(width: 1.3, height: 1.0,
                      at: Vec3(-0.72, 0.95, 0.52),
                      toward: Vec3(-0.05, 0.08, 0),
                      color: RGB(1.0, 0.945, 0.855),
                      intensity: 780, castsShadow: true, softness: 7),
        fill: .softbox(width: 1.4, height: 1.0,
                       at: Vec3(0.78, 0.60, -0.42),
                       color: RGB(0.93, 0.87, 0.80),
                       intensity: 195),
        bounce: .softbox(width: 1.0, height: 0.8,
                         at: Vec3(0, 0.012, 0.35),
                         toward: Vec3(0, 0.22, 0),
                         color: RGB(0.60, 0.42, 0.26),
                         intensity: 88),
        ambientColor: RGB(0.88, 0.82, 0.72),
        ambientIntensity: 52,
        environmentIntensity: 0.16,
        exposure: -0.20,
        vignette: 0.55,
        // No wall at all from up here; the bare desk to the left of the deck
        // is the only clear ground.
        lyrics: TextPlacement(x: 0.045, y: 0.2, alignment: .leading),
        dressing: .init(wall: false, sleeve: false, mug: true),
        dustCount: 40
    )
}
