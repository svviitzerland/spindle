import AppKit
import Foundation

/// What the record itself is made of.
///
/// The label still shows whatever you are playing. A pressing changes the
/// disc around it: classic black, translucent ruby, bone, a custom colour
/// somebody mixed themselves.
struct Pressing: Identifiable, Hashable, Sendable {
    var id: String
    var name: String
    /// The vinyl compound.
    var color: RGB
    /// Translucent stock catches light through its edge instead of swallowing
    /// it, which is most of what separates clear vinyl from black.
    var translucent: Bool
    /// A label image that overrides the album art. Rare, and only sensible
    /// for a pressing meant to be looked at rather than listened to.
    var labelImage: URL?

    var isCustom: Bool { labelImage != nil || !Pressing.builtIn.contains(where: { $0.id == id }) }
}

extension Pressing {
    static let black = Pressing(id: "black", name: "Classic Black",
                                color: RGB(0.030, 0.029, 0.032), translucent: false)

    static let builtIn: [Pressing] = [
        black,
        Pressing(id: "clear", name: "Clear",
                 color: RGB(0.70, 0.72, 0.74), translucent: true),
        Pressing(id: "ruby", name: "Ruby",
                 color: RGB(0.46, 0.055, 0.080), translucent: true),
        Pressing(id: "sea-glass", name: "Sea Glass",
                 color: RGB(0.10, 0.36, 0.33), translucent: true),
        Pressing(id: "bone", name: "Bone",
                 color: RGB(0.82, 0.78, 0.68), translucent: false),
        Pressing(id: "ember", name: "Ember",
                 color: RGB(0.68, 0.30, 0.055), translucent: true),
    ]
}

// MARK: - Library

/// Loads pressings from disk so people can add their own.
///
/// Deliberately a folder rather than a download. A hosted gallery would mean
/// somebody paying for a server forever, every fork pointing at a server that
/// is not theirs, and an app that phones home. A folder costs nothing, works
/// offline, and if a shared gallery is ever wanted, a git repository cloned
/// into it does the job with no infrastructure at all.
enum PressingLibrary {

    /// `~/Library/Application Support/Spindle/Records`
    static func directory() throws -> URL {
        let base = try FileManager.default.url(for: .applicationSupportDirectory,
                                               in: .userDomainMask,
                                               appropriateFor: nil,
                                               create: true)
        let directory = base.appendingPathComponent("Spindle/Records", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// Built-in pressings first, then whatever is in the folder.
    static func all() -> [Pressing] {
        builtIn() + custom()
    }

    static func builtIn() -> [Pressing] { Pressing.builtIn }

    static func pressing(id: String) -> Pressing {
        all().first { $0.id == id } ?? .black
    }

    /// Every `*.json` in the folder, skipping any that will not parse.
    ///
    /// A malformed file is logged and ignored rather than thrown: one bad
    /// hand-edited record should not take the wallpaper down with it.
    static func custom() -> [Pressing] {
        guard let directory = try? directory(),
              let files = try? FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: nil) else { return [] }

        return files
            .filter { $0.pathExtension.lowercased() == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .compactMap { url in
                do {
                    return try load(url)
                } catch {
                    Log.warn("ignoring \(url.lastPathComponent): \(error)")
                    return nil
                }
            }
    }

    private static func load(_ url: URL) throws -> Pressing {
        let data = try Data(contentsOf: url)
        let file = try JSONDecoder().decode(PressingFile.self, from: data)
        let id = "custom:" + url.deletingPathExtension().lastPathComponent

        var labelImage: URL?
        if let name = file.label {
            let candidate = url.deletingLastPathComponent().appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: candidate.path) {
                labelImage = candidate
            } else {
                Log.warn("\(url.lastPathComponent): label '\(name)' not found")
            }
        }

        return Pressing(id: id,
                        name: file.name ?? url.deletingPathExtension().lastPathComponent,
                        color: try RGB(hex: file.color),
                        translucent: file.translucent ?? false,
                        labelImage: labelImage)
    }

    /// Explain the format in the folder itself, where someone opening it will
    /// actually read it. Written once; never overwritten.
    static func installGuideIfNeeded() {
        guard let directory = try? directory() else { return }
        let guide = directory.appendingPathComponent("README.md")
        guard !FileManager.default.fileExists(atPath: guide.path) else { return }

        let text = """
        # Records

        Drop a `.json` file in this folder and Spindle offers it as a pressing.
        The label still shows whatever you are playing; a pressing changes the
        disc around it.

        `midnight.json`

        ```json
        {
          "name": "Midnight Blue",
          "color": "#1b2a6b",
          "translucent": true
        }
        ```

        | Field | |
        | --- | --- |
        | `color` | required, `#rrggbb` |
        | `name` | optional, defaults to the file name |
        | `translucent` | optional, `false` by default. Translucent stock catches light through its edge |
        | `label` | optional, an image file beside the json. Replaces the album art on the label |

        Changes appear next time Spindle starts.

        To share a set of pressings, put this folder in a git repository.
        Anyone can clone it here, and nobody has to run a server.
        """
        try? text.write(to: guide, atomically: true, encoding: .utf8)
    }
}

/// The on-disk shape, kept apart from `Pressing` so the file format can stay
/// forgiving without the rest of the app having to deal with optionals.
private struct PressingFile: Decodable {
    var name: String?
    var color: String
    var translucent: Bool?
    var label: String?
}

// MARK: - Colour parsing

extension RGB {
    enum HexError: Error, CustomStringConvertible {
        case malformed(String)

        var description: String {
            switch self {
            case .malformed(let value): return "'\(value)' is not a #rrggbb colour"
            }
        }
    }

    init(hex: String) throws {
        var text = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("#") { text.removeFirst() }
        // Accept #abc as well, since people write it.
        if text.count == 3 {
            text = text.map { "\($0)\($0)" }.joined()
        }
        guard text.count == 6, let value = UInt32(text, radix: 16) else {
            throw HexError.malformed(hex)
        }
        self.init(CGFloat((value >> 16) & 0xFF) / 255.0,
                  CGFloat((value >> 8) & 0xFF) / 255.0,
                  CGFloat(value & 0xFF) / 255.0)
    }
}
