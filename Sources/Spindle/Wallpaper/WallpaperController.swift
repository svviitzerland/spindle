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
    private var settleTimer: Timer?
    private var powerTimer: Timer?
    private var policy = RenderPolicy()

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

        observeEnergy()
        updateRenderMode()

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
    // MARK: Energy

    /// Everything that decides whether the scene needs drawing at all.
    private func observeEnergy() {
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(forName: NSWorkspace.screensDidSleepNotification,
                              object: nil, queue: .main) { [weak self] _ in
            self?.policy.isScreenAsleep = true
            self?.updateRenderMode()
        }
        workspace.addObserver(forName: NSWorkspace.screensDidWakeNotification,
                              object: nil, queue: .main) { [weak self] _ in
            self?.policy.isScreenAsleep = false
            self?.monitor.forceRefresh()
            self?.updateRenderMode()
        }

        // Locking the screen is not screen sleep, and both need catching.
        let distributed = DistributedNotificationCenter.default()
        distributed.addObserver(forName: .init("com.apple.screenIsLocked"),
                                object: nil, queue: .main) { [weak self] _ in
            self?.policy.isScreenLocked = true
            self?.updateRenderMode()
        }
        distributed.addObserver(forName: .init("com.apple.screenIsUnlocked"),
                                object: nil, queue: .main) { [weak self] _ in
            self?.policy.isScreenLocked = false
            self?.monitor.forceRefresh()
            self?.updateRenderMode()
        }

        NotificationCenter.default.addObserver(
            forName: Notification.Name.NSProcessInfoPowerStateDidChange,
            object: nil, queue: .main) { [weak self] _ in
            self?.readPower()
            self?.updateRenderMode()
        }

        // Unplugging raises no notification worth relying on, so it is
        // checked on a slow timer. A minute late to drop six frames a second
        // costs nothing.
        powerTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            guard let self else { return }
            let before = self.policy
            self.readPower()
            if self.policy != before { self.updateRenderMode() }
        }
        readPower()
    }

    private func readPower() {
        policy.isOnBattery = PowerSource.isOnBattery
        policy.isLowPower = PowerSource.isLowPower
    }

    /// Recompute what the wallpaper should be doing and tell the windows.
    private func updateRenderMode() {
        let mode = policy.mode
        windows.forEach { $0.apply(mode) }

        // Asking Spotify what is playing costs an Apple Event every time.
        // When nothing can see the answer, ask far less often.
        let interval = mode == .off ? 10.0 : Preferences.Fixed.pollInterval
        if monitor.interval != interval { monitor.start(interval: interval) }

        lyricsTimer?.fireDate = mode.isLive ? Date() : .distantFuture
        progressTimer?.fireDate = mode.isLive ? Date() : .distantFuture
    }

    /// Hold the live renderer open for a moment after the music stops.
    ///
    /// The platter free-wheels for several seconds and the arm swings back to
    /// its rest. Freezing the instant playback ends would cut both of those
    /// off halfway.
    private func setAnimating(_ animating: Bool) {
        settleTimer?.invalidate()
        settleTimer = nil

        if animating {
            policy.isAnimating = true
            updateRenderMode()
            return
        }

        guard policy.isAnimating else { return }
        settleTimer = Timer.scheduledTimer(withTimeInterval: 6, repeats: false) { [weak self] _ in
            self?.policy.isAnimating = false
            self?.updateRenderMode()
        }
    }

    /// Put the right room on screen, which depends on the hour when the
    /// clock is driving.
    private func refreshScene() {
        turntable.apply(preferences.activePreset)
        refreshLockScreen()
        // The held frame is a picture of the old room.
        windows.forEach { $0.redrawHeldFrame() }
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
        settleTimer?.invalidate()
        settleTimer = nil
        powerTimer?.invalidate()
        powerTimer = nil
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
            window.onVisibilityChange = { [weak self] visible in
                self?.policy.isVisible = visible
                self?.updateRenderMode()
            }
            window.orderFrontRegardless()
            return window
        }
        Log.info("wallpaper showing on \(windows.count) display(s)")
        windows.forEach { $0.apply(policy.mode) }
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
            let moving = playing.isPlaying || preferences.spinWhenPaused
            setAnimating(moving)
            turntable.setSpinning(moving)
            if playing.isPlaying {
                turntable.setProgress(playing.interpolatedProgress())
            } else {
                // Paused: lift the stylus and swing it clear, rather than
                // leaving it sitting in a groove that is not moving.
                turntable.parkTonearm()
            }
        } else {
            // Nothing playing: show the generated sleeve and park the arm.
            setAnimating(preferences.spinWhenPaused)
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
