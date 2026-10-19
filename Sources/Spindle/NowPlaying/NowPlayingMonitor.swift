import AppKit
import Foundation

/// Polls the music apps and reports what changed.
///
/// Polling, rather than listening for the apps' distributed notifications,
/// because those only fire on track change: without a poll the tonearm would
/// never learn that you hit pause or scrubbed.
final class NowPlayingMonitor {

    /// How Spindle decides which app to believe.
    enum Preference: String, CaseIterable, Identifiable {
        case automatic
        case appleMusic
        case spotify
        case standalone

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .automatic: return "Whatever is playing"
            case .appleMusic: return "Music only"
            case .spotify: return "Spotify only"
            case .standalone: return "Standalone"
            }
        }
    }

    /// Called on the main queue whenever the picture changes.
    var onChange: ((NowPlaying?) -> Void)?
    /// Called on the main queue when new cover art is available.
    var onArtwork: ((NSImage?) -> Void)?
    /// Called once if macOS refuses the Apple Events permission.
    var onPermissionDenied: ((NowPlaying.Source) -> Void)?

    var preference: Preference = .automatic {
        didSet { if preference != oldValue { forceRefresh() } }
    }

    private let bridge = AppleScriptBridge()
    private let providers: [MusicProvider]
    private let work = DispatchQueue(label: "com.spindle.nowplaying", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var lastTrackKey: String?
    private var deniedSources: Set<NowPlaying.Source> = []

    private(set) var current: NowPlaying?

    init() {
        providers = [AppleMusicProvider(bridge: bridge), SpotifyProvider(bridge: bridge)]
    }

    func start(interval: TimeInterval = 2.0) {
        stop()
        let timer = DispatchSource.makeTimerSource(queue: work)
        timer.schedule(deadline: .now(), repeating: interval, leeway: .milliseconds(250))
        timer.setEventHandler { [weak self] in self?.poll() }
        timer.resume()
        self.timer = timer
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    func forceRefresh() {
        lastTrackKey = nil
        work.async { [weak self] in self?.poll() }
    }

    // MARK: Polling

    private func poll() {
        let playing = preference == .standalone ? nil : readCurrent()
        let changed = playing?.trackKey != lastTrackKey

        if changed {
            lastTrackKey = playing?.trackKey
            let artwork = playing.flatMap { readArtwork(for: $0.source) }
            DispatchQueue.main.async { [weak self] in
                self?.current = playing
                self?.onChange?(playing)
                self?.onArtwork?(artwork)
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
        for provider in candidates() {
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

    private func candidates() -> [MusicProvider] {
        switch preference {
        case .automatic: return providers
        case .appleMusic: return providers.filter { $0.source == .appleMusic }
        case .spotify: return providers.filter { $0.source == .spotify }
        case .standalone: return []
        }
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
