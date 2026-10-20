import AppKit
import Foundation

/// Read a number out of an AppleScript result.
///
/// AppleScript formats reals with the system's decimal separator, so on a
/// machine set to a comma locale `player position` comes back as "12,345" and
/// `Double()` refuses it. That silently became zero, which pinned the tonearm
/// to the lead-in groove and held lyrics on the first line forever.
func appleScriptNumber(_ text: String) -> Double? {
    Double(text.replacingOccurrences(of: ",", with: "."))
}

/// A source Spindle can ask "what is playing?".
protocol MusicProvider {
    var source: NowPlaying.Source { get }
    var isRunning: Bool { get }
    /// Returns nil when the app is closed or stopped — not an error.
    func fetch() throws -> NowPlaying?
    /// Cover art for the current track, if the app will give it up.
    func artwork() throws -> NSImage?
    /// Lyrics stored against the current track, if the app keeps any.
    func lyrics() throws -> String?
}

extension MusicProvider {
    /// Most sources have nothing to offer here.
    func lyrics() throws -> String? { nil }
}

// MARK: - Spotify

/// Spotify exposes the cover as an https URL, so artwork arrives over the
/// network rather than through Apple Events.
struct SpotifyProvider: MusicProvider {
    let bridge: AppleScriptBridge
    let source: NowPlaying.Source = .spotify

    var isRunning: Bool { bridge.isRunning(source.bundleIdentifier) }

    private static let stateScript = """
    tell application id "com.spotify.client"
        if player state is stopped then return "stopped"
        set t to current track
        return (name of t) & "\\n" & (artist of t) & "\\n" & (album of t) & "\\n" ¬
            & ((duration of t) as text) & "\\n" & ((player position) as text) & "\\n" ¬
            & ((player state) as text)
    end tell
    """

    private static let artworkScript = """
    tell application id "com.spotify.client"
        if player state is stopped then return ""
        return artwork url of current track
    end tell
    """

    func fetch() throws -> NowPlaying? {
        guard isRunning else { return nil }
        let result = try bridge.run(Self.stateScript, cacheKey: "spotify.state")
        guard let text = result.stringValue, text != "stopped" else { return nil }

        let fields = text.components(separatedBy: "\n")
        guard fields.count >= 6 else { return nil }
        // Spotify reports track length in milliseconds.
        let duration = (appleScriptNumber(fields[3]) ?? 0) / 1000.0
        return NowPlaying(title: fields[0],
                          artist: fields[1],
                          album: fields[2],
                          duration: duration,
                          position: appleScriptNumber(fields[4]) ?? 0,
                          isPlaying: fields[5].lowercased().contains("playing"),
                          source: source)
    }

    /// Spotify's scripting interface has no lyrics in it at all, so there is
    /// nothing to ask for. Saying so here is better than an empty result that
    /// looks like a track without lyrics.
    func lyrics() throws -> String? { nil }

    func artwork() throws -> NSImage? {
        guard isRunning else { return nil }
        let result = try bridge.run(Self.artworkScript, cacheKey: "spotify.artwork")
        guard let urlString = result.stringValue,
              let url = URL(string: urlString),
              url.scheme == "https" else { return nil }
        // The only network request Spindle ever makes, and only to the URL
        // Spotify itself handed over.
        guard let data = try? Data(contentsOf: url) else { return nil }
        return NSImage(data: data)
    }
}

// MARK: - Apple Music

/// Music hands over raw image bytes, so nothing touches the network.
struct AppleMusicProvider: MusicProvider {
    let bridge: AppleScriptBridge
    let source: NowPlaying.Source = .appleMusic

    var isRunning: Bool { bridge.isRunning(source.bundleIdentifier) }

    private static let stateScript = """
    tell application id "com.apple.Music"
        if player state is stopped then return "stopped"
        set t to current track
        return (name of t) & "\\n" & (artist of t) & "\\n" & (album of t) & "\\n" ¬
            & ((duration of t) as text) & "\\n" & ((player position) as text) & "\\n" ¬
            & ((player state) as text)
    end tell
    """

    private static let lyricsScript = """
    tell application id "com.apple.Music"
        if player state is stopped then return ""
        return lyrics of current track
    end tell
    """

    private static let artworkScript = """
    tell application id "com.apple.Music"
        if player state is stopped then return missing value
        set t to current track
        if (count of artworks of t) is 0 then return missing value
        return raw data of artwork 1 of t
    end tell
    """

    func fetch() throws -> NowPlaying? {
        guard isRunning else { return nil }
        let result = try bridge.run(Self.stateScript, cacheKey: "music.state")
        guard let text = result.stringValue, text != "stopped" else { return nil }

        let fields = text.components(separatedBy: "\n")
        guard fields.count >= 6 else { return nil }
        return NowPlaying(title: fields[0],
                          artist: fields[1],
                          album: fields[2],
                          duration: appleScriptNumber(fields[3]) ?? 0,
                          position: appleScriptNumber(fields[4]) ?? 0,
                          isPlaying: fields[5].lowercased().contains("playing"),
                          source: source)
    }

    /// Whatever is stored against the track in your own library. Music keeps
    /// this as plain text with no timings.
    func lyrics() throws -> String? {
        guard isRunning else { return nil }
        let result = try bridge.run(Self.lyricsScript, cacheKey: "music.lyrics")
        guard let text = result.stringValue, !text.isEmpty else { return nil }
        return text
    }

    func artwork() throws -> NSImage? {
        guard isRunning else { return nil }
        let result = try bridge.run(Self.artworkScript, cacheKey: "music.artwork")
        // Depending on the file, Music returns TIFF, JPEG or PNG bytes; NSImage
        // sniffs all three, so the descriptor type does not need decoding.
        guard let data = result.data as Data?, !data.isEmpty else { return nil }
        return NSImage(data: data)
    }
}
