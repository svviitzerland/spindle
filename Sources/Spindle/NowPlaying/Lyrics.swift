import Foundation

/// Lyrics for the track on the platter.
///
/// Two shapes arrive here. Music keeps a plain text field against tracks in
/// your own library, with no timings in it at all. A lyrics database returns
/// LRC, where every line carries the moment it is sung. Timed lines are
/// followed exactly; untimed ones have to be estimated, and the difference
/// matters enough that it is recorded rather than hidden.
struct Lyrics: Equatable {

    struct Line: Equatable {
        /// Seconds from the start of the track, when the source knows.
        var time: TimeInterval?
        var text: String
    }

    let lines: [Line]
    /// The track these belong to, so a slow fetch never lands on a song that
    /// has already changed.
    let trackKey: String
    /// True when every line carries a timestamp.
    var isSynced: Bool { lines.first?.time != nil }

    init?(lines: [Line], trackKey: String) {
        guard !lines.isEmpty else { return nil }
        self.lines = lines
        self.trackKey = trackKey
    }

    /// Plain text, as Music stores it.
    init?(text: String, trackKey: String) {
        let parsed = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .map { Line(time: nil, text: $0) }
        self.init(lines: parsed, trackKey: trackKey)
    }

    /// LRC, as a lyrics database returns it.
    ///
    /// Lines look like `[01:23.45] text`, and one line can carry several
    /// timestamps when a refrain repeats, so each is emitted separately and
    /// the result sorted.
    init?(lrc: String, trackKey: String) {
        var parsed: [Line] = []
        let stamp = try! NSRegularExpression(pattern: #"\[(\d{1,3}):(\d{2})(?:[.:](\d{1,3}))?\]"#)

        for raw in lrc.components(separatedBy: .newlines) {
            let range = NSRange(raw.startIndex..., in: raw)
            let matches = stamp.matches(in: raw, range: range)
            guard !matches.isEmpty, let last = matches.last else { continue }

            let textStart = raw.index(raw.startIndex, offsetBy: last.range.upperBound)
            let text = String(raw[textStart...]).trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else { continue }

            for match in matches {
                func part(_ index: Int) -> Double {
                    guard let r = Range(match.range(at: index), in: raw) else { return 0 }
                    return Double(raw[r]) ?? 0
                }
                // Hundredths or thousandths, depending on the file.
                let fractionDigits = Range(match.range(at: 3), in: raw).map { raw[$0].count } ?? 0
                let fraction = part(3) / pow(10, Double(max(fractionDigits, 1)))
                parsed.append(Line(time: part(1) * 60 + part(2) + fraction, text: text))
            }
        }

        parsed.sort { ($0.time ?? 0) < ($1.time ?? 0) }
        self.init(lines: parsed, trackKey: trackKey)
    }

    /// Which line is being sung.
    ///
    /// With timestamps this is exact. Without them it is the elapsed fraction
    /// mapped onto the line count, which follows a steady song well and a long
    /// intro badly.
    func lineIndex(elapsed: TimeInterval, duration: TimeInterval) -> Int {
        guard lines.count > 1 else { return 0 }

        if isSynced {
            var index = 0
            for (position, line) in lines.enumerated() {
                guard let time = line.time, time <= elapsed else { break }
                index = position
            }
            return index
        }

        guard duration > 0 else { return 0 }
        let progress = min(max(elapsed / duration, 0), 0.9999)
        return Int(progress * Double(lines.count))
    }

    /// The line being sung, with its neighbours for context.
    func window(elapsed: TimeInterval, duration: TimeInterval)
        -> (before: String?, current: String, after: String?) {
        let index = lineIndex(elapsed: elapsed, duration: duration)
        return (before: index > 0 ? lines[index - 1].text : nil,
                current: lines[index].text,
                after: index + 1 < lines.count ? lines[index + 1].text : nil)
    }
}
