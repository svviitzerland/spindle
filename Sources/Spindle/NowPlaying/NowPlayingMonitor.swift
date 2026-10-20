import AppKit
import Foundation

/// Polls the music apps and reports what changed.
///
/// Polling, rather than listening for the apps' distributed notifications,
/// because those only fire on track change: without a poll the tonearm would
/// never learn that you hit pause or scrubbed.
///
/// Whichever app is actually playing wins, so there is nothing to configure.
final class NowPlayingMonitor {

    /// Called on the main queue whenever the picture changes.
    var onChange: ((NowPlaying?) -> Void)?
    /// Called on the main queue when lyrics arrive, or nil when the track has
    /// none and when the source cannot supply them at all.
    var onLyrics: ((Lyrics?) -> Void)?
    /// Called on the main queue when new cover art is available.
    var onArtwork: ((NSImage?) -> Void)?
    /// Called once if macOS refuses the Apple Events permission.
    var onPermissionDenied: ((NowPlaying.Source) -> Void)?

    /// Whether to look lyrics up by name when the app has none of its own.
    /// Owned by preferences; the monitor is told rather than asking.
    var looksUpLyrics = false

    private let bridge = AppleScriptBridge()
    private let lyricsService = LyricsService()
    private let providers: [MusicProvider]
    private let work = DispatchQueue(label: "com.spindle.nowplaying", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var lastTrackKey: String?
    private var deniedSources: Set<NowPlaying.Source> = []

    private(set) var current: NowPlaying?
    /// How often the apps are being asked, so a caller can avoid restarting
    /// the timer with the interval it already has.
    private(set) var interval: TimeInterval = 0

    init() {
        providers = [AppleMusicProvider(bridge: bridge), SpotifyProvider(bridge: bridge)]
    }

    func start(interval: TimeInterval = 2.0) {
        stop()
        self.interval = interval
        let timer = DispatchSource.makeTimerSource(queue: work)
        timer.schedule(deadline: .now(), repeating: interval, leeway: .milliseconds(250))
        timer.setEventHandler { [weak self] in self?.poll() }
        timer.resume()
        self.timer = timer
    }

    func stop() {
        timer?.cancel()
        timer = nil
        interval = 0
    }

    func forceRefresh() {
        lastTrackKey = nil
        work.async { [weak self] in self?.poll() }
    }

    // MARK: Polling

    private func poll() {
        let playing = readCurrent()
        let changed = playing?.trackKey != lastTrackKey

        if changed {
            lastTrackKey = playing?.trackKey
            let artwork = playing.flatMap { readArtwork(for: $0.source) }
            let lyrics = playing.flatMap { readLyrics(for: $0) }
            DispatchQueue.main.async { [weak self] in
                self?.current = playing
                self?.onChange?(playing)
                self?.onArtwork?(artwork)
                self?.onLyrics?(lyrics)
            }
        } else {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                // Same record, but the position and play state still move.
                let wasPlaying = self.current?.isPlaying
                self.current = playing
                if wasPlaying != playing?.isPlaying { self.onChange?(playing) }
            }
        }
    }

    /// Ask each candidate in turn; the first one actually playing wins, and a
    /// paused app is remembered as a fallback so the sleeve does not vanish
    /// the moment you hit pause.
    private func readCurrent() -> NowPlaying? {
        var paused: NowPlaying?
        for provider in providers {
            guard !deniedSources.contains(provider.source) else { continue }
            do {
                guard let state = try provider.fetch() else { continue }
                if state.isPlaying { return state }
                if paused == nil { paused = state }
            } catch {
                note(error, from: provider.source)
            }
        }
        return paused
    }

    private func readArtwork(for source: NowPlaying.Source) -> NSImage? {
        guard let provider = providers.first(where: { $0.source == source }) else { return nil }
        do {
            return try provider.artwork()
        } catch {
            note(error, from: source)
            return nil
        }
    }

    /// Whatever the source keeps against this track. Only Music has any.
    private func readLyrics(for playing: NowPlaying) -> Lyrics? {
        guard let provider = providers.first(where: { $0.source == playing.source }) else {
            return nil
        }
        // What the app itself holds, which costs nothing and leaves the
        // machine untouched.
        do {
            if let text = try provider.lyrics(),
               let local = Lyrics(text: text, trackKey: playing.trackKey) {
                return local
            }
        } catch {
            note(error, from: playing.source)
        }

        // Then, only if asked, look them up by name. This is where Spotify
        // gets lyrics at all, and where anything gets timed ones.
        guard looksUpLyrics else { return nil }
        return lyricsService.lyrics(for: playing)
    }

    /// Log once per source, and stop pestering an app that said no.
    private func note(_ error: Error, from source: NowPlaying.Source) {
        if AppleScriptBridge.isPermissionDenial(error) {
            guard !deniedSources.contains(source) else { return }
            deniedSources.insert(source)
            Log.warn("automation denied for \(source.displayName): \(error)")
            DispatchQueue.main.async { [weak self] in self?.onPermissionDenied?(source) }
        } else {
            Log.warn("\(source.displayName): \(error)")
        }
    }

    /// Called after the user grants permission in System Settings.
    func clearDenials() {
        deniedSources.removeAll()
        forceRefresh()
    }
}
