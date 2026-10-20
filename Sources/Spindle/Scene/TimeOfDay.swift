import CoreGraphics
import Foundation

/// Lets the desktop follow the clock.
///
/// Two things happen. The room changes through the day, because a white
/// gallery at midnight is as wrong as a lamplit corner at ten in the morning.
/// And within a daylit room the sun itself moves: it climbs, it cools toward
/// noon, and it drops and reddens again toward evening.
///
/// The sun model is a shape, not an ephemeris. It takes no account of
/// latitude or season, which would be a lot of arithmetic for a wallpaper.
enum TimeOfDay {

    /// Which room suits this hour. Wraps at midnight.
    private static let schedule: [(from: Double, scene: String)] = [
        (0,  "lamplight"),
        (6,  "daylight"),
        (9,  "conservatory"),
        (11, "gallery"),
        (14, "sage"),
        (17, "clay"),
        (19, "dusk"),
        (21, "lamplight"),
    ]

    /// Hours as a fraction, so 13:30 is 13.5.
    static func hour(at date: Date = Date(), calendar: Calendar = .current) -> Double {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return Double(parts.hour ?? 12) + Double(parts.minute ?? 0) / 60
    }

    static func sceneID(at date: Date = Date(), calendar: Calendar = .current) -> String {
        let now = hour(at: date, calendar: calendar)
        var chosen = schedule[0].scene
        for entry in schedule where now >= entry.from {
            chosen = entry.scene
        }
        return chosen
    }

    /// 0 at the horizon, 1 at the top of the arc. Zero all night.
    static func sunHeight(at hour: Double) -> Double {
        // Up at 6, down at 20, highest at 13.
        let sunrise = 6.0, sunset = 20.0
        guard hour > sunrise, hour < sunset else { return 0 }
        return sin(.pi * (hour - sunrise) / (sunset - sunrise))
    }

    /// Daylight reddens as the sun drops, and is near-neutral overhead.
    static func sunlight(at hour: Double) -> RGB {
        let low = RGB(1.0, 0.760, 0.520)
        let high = RGB(1.0, 0.975, 0.935)
        return low.mixed(with: high, CGFloat(pow(sunHeight(at: hour), 0.55)))
    }

    /// The scene for right now, with its sun placed for the hour.
    static func scene(at date: Date = Date(), calendar: Calendar = .current) -> ScenePreset {
        adjusted(.preset(id: sceneID(at: date, calendar: calendar)),
                 at: date, calendar: calendar)
    }

    /// Move and recolour a preset's key light for the time of day.
    ///
    /// Only daylight keys are touched. A lamp does not care what hour it is,
    /// so Lamplight and Dusk are returned exactly as written.
    static func adjusted(_ preset: ScenePreset,
                         at date: Date = Date(),
                         calendar: Calendar = .current) -> ScenePreset {
        guard case .spot = preset.key.kind else { return preset }

        let now = hour(at: date, calendar: calendar)
        let height = sunHeight(at: now)
        guard height > 0 else { return preset }

        var adjusted = preset

        // Low sun comes in almost level and from the side; high sun comes
        // down steeply. The preset's own position is the midday case.
        let rise = CGFloat(0.35 + height * 0.95)
        let reach = CGFloat(1.35 - height * 0.45)
        adjusted.key.position = Vec3(preset.key.position.x * reach,
                                     preset.key.position.y * rise,
                                     preset.key.position.z * reach)

        // Keep the room's own cast, but pull it toward the hour's colour.
        adjusted.key.color = preset.key.color.mixed(with: sunlight(at: now), 0.65)

        // A low sun is a weaker sun.
        adjusted.key.intensity = preset.key.intensity * CGFloat(0.72 + height * 0.42)
        adjusted.exposure = preset.exposure + CGFloat((1 - height) * -0.18)

        return adjusted
    }

    /// A short label for the settings window.
    static func label(at date: Date = Date(), calendar: Calendar = .current) -> String {
        ScenePreset.preset(id: sceneID(at: date, calendar: calendar)).name
    }
}
