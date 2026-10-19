import Combine
import Foundation
import ServiceManagement

/// Everything the user can change, persisted in UserDefaults.
///
/// Deliberately small. A wallpaper that needs a settings manual is a wallpaper
/// nobody leaves running.
final class Preferences: ObservableObject {
    static let shared = Preferences()

    private enum Key {
        static let scene = "scene"
        static let source = "source"
        static let spinWhenPaused = "spinWhenPaused"
        static let showTrackInfo = "showTrackInfo"
        static let frameRateLimit = "frameRateLimit"
        static let pollInterval = "pollInterval"
        static let seed = "seed"
    }

    private let defaults: UserDefaults

    @Published var sceneID: String { didSet { defaults.set(sceneID, forKey: Key.scene) } }
    @Published var source: NowPlayingMonitor.Preference {
        didSet { defaults.set(source.rawValue, forKey: Key.source) }
    }
    /// Keep the platter turning even when playback is paused.
    @Published var spinWhenPaused: Bool {
        didSet { defaults.set(spinWhenPaused, forKey: Key.spinWhenPaused) }
    }
    @Published var showTrackInfo: Bool {
        didSet { defaults.set(showTrackInfo, forKey: Key.showTrackInfo) }
    }
    /// 30 fps is plenty for a record turning at 33 rpm and halves the GPU cost.
    @Published var frameRateLimit: Int {
        didSet { defaults.set(frameRateLimit, forKey: Key.frameRateLimit) }
    }
    @Published var pollInterval: Double {
        didSet { defaults.set(pollInterval, forKey: Key.pollInterval) }
    }
    /// Changes the generated sleeve shown when nothing is playing.
    @Published var seed: String { didSet { defaults.set(seed, forKey: Key.seed) } }

    var preset: ScenePreset { ScenePreset.preset(id: sceneID) }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        sceneID = defaults.string(forKey: Key.scene) ?? ScenePreset.daylight.id
        source = NowPlayingMonitor.Preference(rawValue: defaults.string(forKey: Key.source) ?? "")
            ?? .automatic
        spinWhenPaused = defaults.object(forKey: Key.spinWhenPaused) as? Bool ?? false
        showTrackInfo = defaults.object(forKey: Key.showTrackInfo) as? Bool ?? true
        frameRateLimit = defaults.object(forKey: Key.frameRateLimit) as? Int ?? 30
        pollInterval = defaults.object(forKey: Key.pollInterval) as? Double ?? 2.0
        seed = defaults.string(forKey: Key.seed) ?? "spindle"
    }

    // MARK: Launch at login

    /// Backed by the login-item service rather than a stored flag, so the
    /// checkbox always reflects what macOS actually believes.
    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
                objectWillChange.send()
            } catch {
                Log.warn("launch at login (\(newValue)) failed: \(error.localizedDescription)")
            }
        }
    }
}
