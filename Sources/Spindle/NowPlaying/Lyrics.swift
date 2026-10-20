import Foundation

/// Lyrics for the track on the platter.
///
/// They come from the `lyrics` field Music keeps on a track in your own
/// library. Spindle ships none, stores none and fetches none: it reads what
/// is already on your machine, the same way it reads the title.
///
/// Spotify has no lyrics in its scripting interface at all, so this is a
/// Music-only feature and says so rather than pretending otherwise.
struct Lyrics: Equatable {
    /// Blank lines removed; what is left is what gets shown.
    let lines: [String]
    /// The track these belong to, so a stale fetch is never displayed over a
    /// song that has already changed.
    let trackKey: String

    init?(text: String, trackKey: String) {
        let parsed = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard !parsed.isEmpty else { return nil }
        self.lines = parsed
        self.trackKey = trackKey
    }

    /// Which line is probably being sung.
    ///
    /// Music stores lyrics as plain text with no timings, so there is nothing
    /// to synchronise against. This spreads the lines evenly across the
    /// track, which tracks a steady song well and a long intro badly. It is
    /// an estimate and the setting is named so that it reads as one.
    func lineIndex(atProgress progress: Double) -> Int {
        guard lines.count > 1 else { return 0 }
        let clamped = min(max(progress, 0), 0.9999)
        return Int(clamped * Double(lines.count))
    }

    /// The line being sung, with its neighbours for context.
    func window(atProgress progress: Double) -> (before: String?, current: String, after: String?) {
        let index = lineIndex(atProgress: progress)
        return (before: index > 0 ? lines[index - 1] : nil,
                current: lines[index],
                after: index + 1 < lines.count ? lines[index + 1] : nil)
    }
}
