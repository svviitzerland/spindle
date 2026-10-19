import AppKit
import Foundation

/// What is on the turntable right now.
struct NowPlaying: Equatable {
    enum Source: String, CaseIterable, Identifiable {
        case appleMusic
        case spotify

        var id: String { rawValue }

        var bundleIdentifier: String {
            switch self {
            case .appleMusic: return "com.apple.Music"
            case .spotify: return "com.spotify.client"
            }
        }

        var displayName: String {
            switch self {
            case .appleMusic: return "Music"
            case .spotify: return "Spotify"
            }
        }
    }

    var title: String
    var artist: String
    var album: String
    /// Seconds.
    var duration: Double
    /// Seconds, as of `sampledAt`.
    var position: Double
    var isPlaying: Bool
    var source: Source
    var sampledAt: Date = Date()

    /// Identifies the record, not the moment — used to decide when the sleeve
    /// needs redrawing and when to go fetch new artwork.
    var trackKey: String { "\(source.rawValue)|\(artist)|\(album)|\(title)" }

    /// Position carried forward from the last poll, so the tonearm keeps
    /// creeping inward between samples instead of stepping.
    func interpolatedProgress(at date: Date = Date()) -> Double {
        guard duration > 0 else { return 0 }
        let elapsed = isPlaying ? date.timeIntervalSince(sampledAt) : 0
        return min(max((position + elapsed) / duration, 0), 1)
    }

    static func == (lhs: NowPlaying, rhs: NowPlaying) -> Bool {
        lhs.trackKey == rhs.trackKey && lhs.isPlaying == rhs.isPlaying
    }
}
