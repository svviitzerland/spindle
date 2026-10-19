import AppKit
import Combine

/// What is playing, in a form SwiftUI can watch.
///
/// `NowPlayingMonitor` is a plain callback-driven object so the wallpaper can
/// use it without importing SwiftUI. This adapts it for the settings window,
/// which is the only place that needs to observe playback.
final class NowPlayingStore: ObservableObject {
    @Published private(set) var playing: NowPlaying?
    @Published private(set) var artwork: NSImage?
    /// Set when macOS has refused Apple Events for a source.
    @Published private(set) var deniedSource: NowPlaying.Source?

    func update(_ playing: NowPlaying?) {
        self.playing = playing
        if playing != nil { deniedSource = nil }
    }

    func update(artwork: NSImage?) {
        self.artwork = artwork
    }

    func denied(_ source: NowPlaying.Source) {
        deniedSource = source
    }

    func clearDenial() {
        deniedSource = nil
    }

    /// Elapsed seconds, carried forward from the last poll so the progress bar
    /// moves smoothly rather than stepping every couple of seconds.
    func elapsed(at date: Date = Date()) -> Double {
        guard let playing else { return 0 }
        let drift = playing.isPlaying ? date.timeIntervalSince(playing.sampledAt) : 0
        return min(max(playing.position + drift, 0), playing.duration)
    }
}

extension NowPlaying {
    /// "3:48". Negative or absurd values collapse to a dash.
    static func timestamp(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0, seconds < 60 * 60 * 24 else { return "–:––" }
        let total = Int(seconds.rounded(.down))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
