import AppKit
import Combine
import SceneKit

/// Owns the scene, one window per display, and the wiring between what is
/// playing and what the deck is doing.
final class WallpaperController {

    private let preferences: Preferences
    private let monitor = NowPlayingMonitor()
    private var turntable: TurntableScene
    private var windows: [WallpaperWindow] = []
    private var cancellables: Set<AnyCancellable> = []
    private var progressTimer: Timer?

    /// Raised when an app refuses automation, so the menu can offer a fix.
    var onPermissionDenied: ((NowPlaying.Source) -> Void)?

    init(preferences: Preferences = .shared) {
        self.preferences = preferences
        self.turntable = TurntableScene(preset: preferences.preset, seed: preferences.seed)
    }

    // MARK: Lifecycle

    func start() {
        rebuildWindows()
        observePreferences()
        observeScreens()

        monitor.preference = preferences.source
        monitor.onChange = { [weak self] playing in self?.apply(playing) }
        monitor.onArtwork = { [weak self] image in self?.turntable.setArtwork(image) }
        monitor.onPermissionDenied = { [weak self] source in self?.onPermissionDenied?(source) }
        monitor.start(interval: preferences.pollInterval)

        // The tonearm creeps inward between polls rather than jumping every
        // two seconds when the next sample lands.
        progressTimer = Timer.scheduledTimer(withTimeInterval: 4, repeats: true) { [weak self] _ in
            self?.advanceTonearm()
        }
        apply(nil)
    }

    func stop() {
        monitor.stop()
        progressTimer?.invalidate()
        progressTimer = nil
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
    }

    func refreshPermissions() {
        monitor.clearDenials()
    }

    // MARK: Windows

    private func rebuildWindows() {
        windows.forEach { $0.orderOut(nil) }
        windows = NSScreen.screens.map { screen in
            let window = WallpaperWindow(screen: screen,
                                         scene: turntable.scene,
                                         pointOfView: turntable.pointOfView,
                                         frameRateLimit: preferences.frameRateLimit)
            window.update(for: screen)
            window.orderFrontRegardless()
            return window
        }
        Log.info("wallpaper showing on \(windows.count) display(s)")
        applyTrackInfo(monitor.current)
    }

    private func observeScreens() {
        NotificationCenter.default.publisher(
            for: NSApplication.didChangeScreenParametersNotification)
            .debounce(for: .milliseconds(400), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.rebuildWindows() }
            .store(in: &cancellables)
    }

    private func observePreferences() {
        preferences.$sceneID
            .dropFirst()
            .sink { [weak self] id in self?.turntable.apply(ScenePreset.preset(id: id)) }
            .store(in: &cancellables)

        preferences.$source
            .dropFirst()
            .sink { [weak self] source in self?.monitor.preference = source }
            .store(in: &cancellables)

        preferences.$frameRateLimit
            .dropFirst()
            .sink { [weak self] fps in self?.windows.forEach { $0.setFrameRateLimit(fps) } }
            .store(in: &cancellables)

        preferences.$pollInterval
            .dropFirst()
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] interval in self?.monitor.start(interval: interval) }
            .store(in: &cancellables)

        preferences.$spinWhenPaused
            .dropFirst()
            .sink { [weak self] _ in self?.apply(self?.monitor.current) }
            .store(in: &cancellables)

        preferences.$showTrackInfo
            .dropFirst()
            .sink { [weak self] _ in self?.applyTrackInfo(self?.monitor.current) }
            .store(in: &cancellables)

        preferences.$seed
            .dropFirst()
            .debounce(for: .milliseconds(500), scheduler: RunLoop.main)
            .sink { [weak self] seed in
                guard let self, self.monitor.current == nil else { return }
                self.turntable.setArtwork(GenerativeCover.make(seed: seed).image)
            }
            .store(in: &cancellables)
    }

    // MARK: Reacting to playback

    private func apply(_ playing: NowPlaying?) {
        if let playing {
            turntable.setSpinning(playing.isPlaying || preferences.spinWhenPaused)
            turntable.setProgress(playing.interpolatedProgress())
        } else {
            // Nothing playing: show the generated sleeve and park the arm.
            turntable.setArtwork(GenerativeCover.make(seed: preferences.seed).image)
            turntable.setSpinning(preferences.spinWhenPaused)
            turntable.parkTonearm()
        }
        applyTrackInfo(playing)
    }

    private func applyTrackInfo(_ playing: NowPlaying?) {
        windows.forEach { $0.setTrackInfo(playing, visible: preferences.showTrackInfo) }
    }

    private func advanceTonearm() {
        guard let playing = monitor.current, playing.isPlaying else { return }
        turntable.setProgress(playing.interpolatedProgress())
    }
}
