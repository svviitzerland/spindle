import Combine
import Foundation
import ServiceManagement

/// Everything the user can change, persisted in UserDefaults.
///
/// Deliberately small. A wallpaper that needs a settings manual is a wallpaper
/// nobody leaves running, so anything with one obviously right answer lives in
/// `Fixed` instead of in the settings window.
final class Preferences: ObservableObject {
    static let shared = Preferences()

    /// Decisions made once, for everyone.
    enum Fixed {
        /// Plenty for a record turning at 33 rpm, and half the GPU cost of 60.
        static let frameRate = 30
        /// Music and Spotify only post a notification on track change, so
        /// pause, resume and scrub have to be polled for.
        static let pollInterval: TimeInterval = 2.0
        /// The sleeve drawn when nothing is playing.
        static let sleeveSeed = "spindle"
    }

    private enum Key {
        static let scene = "scene"
        static let spinWhenPaused = "spinWhenPaused"
        static let showTrackInfo = "showTrackInfo"
        static let lockScreen = "lockScreenBackground"
    }

    private let defaults: UserDefaults

    @Published var sceneID: String { didSet { defaults.set(sceneID, forKey: Key.scene) } }

    /// Keep the platter turning even when playback is paused.
    @Published var spinWhenPaused: Bool {
        didSet { defaults.set(spinWhenPaused, forKey: Key.spinWhenPaused) }
    }

    @Published var showTrackInfo: Bool {
        didSet { defaults.set(showTrackInfo, forKey: Key.showTrackInfo) }
    }

    /// Put a still of the scene on the lock screen, by way of the desktop
    /// picture. Off by default: it changes a system setting.
    @Published var lockScreenBackground: Bool {
        didSet { defaults.set(lockScreenBackground, forKey: Key.lockScreen) }
    }

    var preset: ScenePreset { ScenePreset.preset(id: sceneID) }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        sceneID = defaults.string(forKey: Key.scene) ?? ScenePreset.daylight.id
        spinWhenPaused = defaults.object(forKey: Key.spinWhenPaused) as? Bool ?? false
        showTrackInfo = defaults.object(forKey: Key.showTrackInfo) as? Bool ?? true
        lockScreenBackground = defaults.object(forKey: Key.lockScreen) as? Bool ?? false
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
