import Foundation

/// Looks lyrics up by name.
///
/// Spotify exposes no lyrics at all, and Music only has whatever happens to
/// be stored against a track in your own library, which for most of them is
/// nothing. The menu-bar lyrics apps people compare this to are not reading
/// Spotify either: they take the title and artist from it and look the words
/// up in a lyrics database. That is what this does.
///
/// LRCLIB is used because it is free, needs no key or account, and returns
/// LRC with a timestamp on every line, so the display follows the song
/// properly instead of guessing from elapsed time. It is open source and can
/// be self-hosted, so the address is configurable rather than burned in.
///
/// This is the one part of Spindle that sends anything anywhere. It is off by
/// default, and what leaves the machine is the title, artist, album and
/// length of the track, which is enough to identify it.
final class LyricsService {

    /// Override to point at your own instance.
    static let endpointKey = "lyricsEndpoint"

    private let session: URLSession
    private let defaults: UserDefaults
    /// One result per track, so a song is never looked up twice.
    private var cache: [String: Lyrics?] = [:]
    private let queue = DispatchQueue(label: "com.spindle.lyrics")

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 8
        configuration.waitsForConnectivity = false
        session = URLSession(configuration: configuration)
    }

    private var endpoint: String {
        defaults.string(forKey: Self.endpointKey) ?? "https://lrclib.net/api/get"
    }

    /// Blocking, and called from the polling queue rather than the main one.
    func lyrics(for playing: NowPlaying) -> Lyrics? {
        if let hit = queue.sync(execute: { cache[playing.trackKey] }) { return hit }

        let found = fetch(playing)
        queue.sync { cache[playing.trackKey] = found }
        return found
    }

    private func fetch(_ playing: NowPlaying) -> Lyrics? {
        guard var components = URLComponents(string: endpoint) else { return nil }
        components.queryItems = [
            URLQueryItem(name: "track_name", value: playing.title),
            URLQueryItem(name: "artist_name", value: playing.artist),
            URLQueryItem(name: "album_name", value: playing.album),
            URLQueryItem(name: "duration", value: String(Int(playing.duration.rounded()))),
        ]
        guard let url = components.url else { return nil }

        var request = URLRequest(url: url)
        // LRCLIB asks clients to identify themselves.
        request.setValue("Spindle (https://github.com/svviitzerland/spindle)",
                         forHTTPHeaderField: "User-Agent")

        var payload: Data?
        let done = DispatchSemaphore(value: 0)
        session.dataTask(with: request) { data, response, error in
            if let error {
                Log.warn("lyrics lookup failed: \(error.localizedDescription)")
            } else if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                // 404 just means nobody has transcribed this one.
                if http.statusCode != 404 { Log.warn("lyrics lookup: HTTP \(http.statusCode)") }
            } else {
                payload = data
            }
            done.signal()
        }.resume()
        _ = done.wait(timeout: .now() + 10)

        guard let payload,
              let record = try? JSONDecoder().decode(Record.self, from: payload) else { return nil }
        guard record.instrumental != true else { return nil }

        // Timed lines whenever they exist; plain text is the fallback.
        if let synced = record.syncedLyrics, !synced.isEmpty,
           let lyrics = Lyrics(lrc: synced, trackKey: playing.trackKey) {
            return lyrics
        }
        if let plain = record.plainLyrics, !plain.isEmpty {
            return Lyrics(text: plain, trackKey: playing.trackKey)
        }
        return nil
    }

    private struct Record: Decodable {
        var syncedLyrics: String?
        var plainLyrics: String?
        var instrumental: Bool?
    }
}
