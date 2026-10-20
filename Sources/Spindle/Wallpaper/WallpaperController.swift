import AppKit
import Combine
import SceneKit

/// Owns the scene, one window per display, and the wiring between what is
/// playing and what the deck is doing.
final class WallpaperController {

    private let preferences: Preferences
    /// Shared with the settings window so it can show what is playing.
    let nowPlaying: NowPlayingStore
    private let monitor = NowPlayingMonitor()
    private let lockScreen = LockScreenBackground()
    /// What is on the platter now, so it can be moved to the pile when the
    /// next track starts.
    private var currentArtwork: NSImage?
    private var currentLyrics: Lyrics?
    private var turntable: TurntableScene
    private var windows: [WallpaperWindow] = []
    private var cancellables: Set<AnyCancellable> = []
    private var progressTimer: Timer?
    private var clockTimer: Timer?
    private var lyricsTimer: Timer?

    /// Raised when an app refuses automation, so the menu can offer a fix.
    var onPermissionDenied: ((NowPlaying.Source) -> Void)?

    init(preferences: Preferences = .shared, nowPlaying: NowPlayingStore) {
        self.preferences = preferences
        self.nowPlaying = nowPlaying
        self.turntable = TurntableScene(preset: preferences.activePreset,
                                        seed: Preferences.Fixed.sleeveSeed,
                                        pressing: preferences.pressing)
    }

    // MARK: Lifecycle

    func start() {
        rebuildWindows()
        observePreferences()
        observeScreens()

        monitor.onChange = { [weak self] playing in
            self?.nowPlaying.update(playing)
            self?.apply(playing)
        }
        monitor.onArtwork = { [weak self] image in
            guard let self else { return }
            // Take the record off the platter before putting the next one on.
            if let outgoing = self.currentArtwork, image != nil {
                self.turntable.setLastPlayed(outgoing)
            }
            self.currentArtwork = image
            self.nowPlaying.update(artwork: image)
            self.turntable.setArtwork(image)
        }
        monitor.onLyrics = { [weak self] lyrics in
            self?.currentLyrics = lyrics
            self?.applyLyrics()
        }
        monitor.onPermissionDenied = { [weak self] source in
            self?.nowPlaying.denied(source)
            self?.onPermissionDenied?(source)
        }
        monitor.looksUpLyrics = preferences.lyricsLookup
        monitor.start(interval: Preferences.Fixed.pollInterval)

        // The tonearm creeps inward between polls rather than jumping every
        // two seconds when the next sample lands.
        progressTimer = Timer.scheduledTimer(withTimeInterval: 4, repeats: true) { [weak self] _ in
            self?.advanceTonearm()
        }

        // Lyric lines turn over every two or three seconds, so they get their
        // own beat. Sharing the tonearm's four-second tick skipped lines.
        lyricsTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self, self.preferences.showLyrics else { return }
            self.applyLyrics()
        }

        // The sun moves slowly. Five minutes is frequent enough that the room
        // is never visibly wrong and rare enough to cost nothing.
        clockTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            guard let self, self.preferences.followsClock else { return }
            self.refreshScene()
        }
        apply(nil)
        refreshLockScreen()
    }

    /// Re-render the lock screen still. Called when the scene changes or a
    /// display is added.
    ///
    /// When the setting is off this puts back the wallpaper Spindle replaced,
    /// which covers the case of it being switched off while the app was not
    /// running: otherwise our render would be left on the desktop for good.
    /// Put the right room on screen, which depends on the hour when the
    /// clock is driving.
    private func refreshScene() {
        turntable.apply(preferences.activePreset)
        refreshLockScreen()
    }

    private func refreshLockScreen() {
        guard preferences.lockScreenBackground else {
            lockScreen.restore()
            return
        }
        lockScreen.apply(preset: preferences.activePreset, pressing: preferences.pressing)
    }

    func stop() {
        monitor.stop()
        progressTimer?.invalidate()
        progressTimer = nil
        clockTimer?.invalidate()
        clockTimer = nil
        lyricsTimer?.invalidate()
        lyricsTimer = nil
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
    }

    func refreshPermissions() {
        nowPlaying.clearDenial()
        monitor.clearDenials()
    }

    // MARK: Windows

    private func rebuildWindows() {
        windows.forEach { $0.orderOut(nil) }
        windows = NSScreen.screens.map { screen in
            let window = WallpaperWindow(screen: screen,
                                         scene: turntable.scene,
                                         pointOfView: turntable.pointOfView,
                                         frameRateLimit: Preferences.Fixed.frameRate)
            window.update(for: screen)
            window.orderFrontRegardless()
            return window
        }
        Log.info("wallpaper showing on \(windows.count) display(s)")
        applyTrackInfo(monitor.current)
        applyLyrics()
        refreshLockScreen()
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
            .sink { [weak self] _ in self?.refreshScene() }
            .store(in: &cancellables)

        preferences.$followsClock
            .dropFirst()
            .sink { [weak self] _ in self?.refreshScene() }
            .store(in: &cancellables)

        preferences.$pressingID
            .dropFirst()
            .sink { [weak self] id in
                guard let self else { return }
                self.turntable.apply(PressingLibrary.pressing(id: id))
                self.turntable.setArtwork(self.currentArtwork)
                self.refreshLockScreen()
            }
            .store(in: &cancellables)

        preferences.$lockScreenBackground
            .dropFirst()
            .sink { [weak self] enabled in
                guard let self else { return }
                if enabled {
                    self.lockScreen.apply(preset: self.preferences.preset)
                } else {
                    self.lockScreen.restore()
                }
            }
            .store(in: &cancellables)

        preferences.$spinWhenPaused
            .dropFirst()
            .sink { [weak self] _ in self?.apply(self?.monitor.current) }
            .store(in: &cancellables)

        preferences.$showTrackInfo
            .dropFirst()
            .sink { [weak self] _ in self?.applyTrackInfo(self?.monitor.current) }
            .store(in: &cancellables)

        preferences.$showLyrics
            .dropFirst()
            .sink { [weak self] _ in self?.applyLyrics() }
            .store(in: &cancellables)

        preferences.$lyricsLookup
            .dropFirst()
            .sink { [weak self] enabled in
                guard let self else { return }
                self.monitor.looksUpLyrics = enabled
                self.monitor.forceRefresh()
            }
            .store(in: &cancellables)
    }

    // MARK: Reacting to playback

    private func apply(_ playing: NowPlaying?) {
        if let playing {
            turntable.setSpinning(playing.isPlaying || preferences.spinWhenPaused)
            if playing.isPlaying {
                turntable.setProgress(playing.interpolatedProgress())
            } else {
                // Paused: lift the stylus and swing it clear, rather than
                // leaving it sitting in a groove that is not moving.
                turntable.parkTonearm()
            }
        } else {
            // Nothing playing: show the generated sleeve and park the arm.
            let generated = GenerativeCover.make(seed: Preferences.Fixed.sleeveSeed).image
            nowPlaying.update(artwork: generated)
            turntable.setArtwork(generated)
            turntable.setSpinning(preferences.spinWhenPaused)
            turntable.parkTonearm()
        }
        applyTrackInfo(playing)
    }

    private func applyTrackInfo(_ playing: NowPlaying?) {
        windows.forEach { $0.setTrackInfo(playing, visible: preferences.showTrackInfo) }
    }

    /// The line is estimated from elapsed time, so this is refreshed on the
    /// same beat as the tonearm rather than only when the track changes.
    private func applyLyrics() {
        let playing = monitor.current
        // Timed lyrics are followed against the clock, so they need seconds
        // rather than a fraction of the track.
        let elapsed = playing.map { $0.interpolatedProgress() * $0.duration } ?? 0
        let visible = preferences.showLyrics && playing?.isPlaying == true
        windows.forEach {
            $0.setLyricsPlacement(preferences.activePreset.lyrics, screen: $0.screen)
            $0.setLyrics(currentLyrics, elapsed: elapsed,
                         duration: playing?.duration ?? 0, visible: visible)
        }
    }

    private func advanceTonearm() {
        guard let playing = monitor.current, playing.isPlaying else { return }
        turntable.setProgress(playing.interpolatedProgress())
    }
}
