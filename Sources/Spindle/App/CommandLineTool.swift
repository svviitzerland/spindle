import AppKit
import Foundation

/// The non-GUI entry points. `spindle` with no arguments starts the app;
/// these subcommands exist so you can get a wallpaper out of it, or an icon,
/// without launching anything.
enum CommandLineTool {

    static let usage = """
    spindle — a turntable on your desktop

    USAGE
      spindle                      Run the wallpaper (menu bar app)
      spindle render [options]     Write one frame as a PNG
      spindle icon --out <path>    Generate the app icon
      spindle scenes               List scene ids
      spindle contact [--out p]    Render every scene onto one sheet
      spindle --help

    RENDER OPTIONS
      --scene <id>      daylight | lamplight | overhead
      --size <WxH>      default 2560x1440
      --seed <text>     changes the generated sleeve art
      --pressing <id>   black | clear | ruby | sea-glass | bone | ember
      --progress <0-1>  where the stylus sits in the side
      --out <path>      default ./spindle-<scene>.png
    """

    /// Returns true when a subcommand handled the invocation and the process
    /// should exit without starting NSApplication.
    static func run(_ arguments: [String]) -> Int32? {
        var args = arguments
        args.removeFirst() // executable path
        guard let command = args.first else { return nil }

        switch command {
        case "--help", "-h", "help":
            print(usage)
            return 0
        case "scenes":
            for preset in ScenePreset.all {
                print("\(preset.id)\t\(preset.name) — \(preset.tagline)")
            }
            return 0
        case "contact":
            return contactCommand(Array(args.dropFirst()))
        case "render":
            return renderCommand(Array(args.dropFirst()))
        case "icon":
            return iconCommand(Array(args.dropFirst()))
        default:
            // Launch services passes -psn_… and friends; those mean "run the app".
            if command.hasPrefix("-") { return nil }
            Log.cli("unknown command '\(command)'. Try: spindle --help")
            return 2
        }
    }

    // MARK: Subcommands

    private static func renderCommand(_ args: [String]) -> Int32 {
        let options = parse(args)
        let preset = ScenePreset.preset(id: options["scene"] ?? ScenePreset.daylight.id)
        if let requested = options["scene"], !ScenePreset.all.contains(where: { $0.id == requested }) {
            Log.cli("unknown scene '\(requested)'. Try: spindle scenes")
            return 2
        }

        let sizeText = options["size"] ?? "2560x1440"
        guard let size = StillRenderer.parseSize(sizeText) else {
            Log.cli("bad --size '\(sizeText)'. Expected something like 3840x2160")
            return 2
        }

        let progress = Double(options["progress"] ?? "") ?? 0.28
        let seed = options["seed"] ?? "spindle"
        let pressing = PressingLibrary.pressing(id: options["pressing"] ?? Pressing.black.id)
        let outPath = options["out"] ?? "spindle-\(preset.id).png"
        let url = URL(fileURLWithPath: (outPath as NSString).expandingTildeInPath)

        do {
            let image = try StillRenderer.render(preset: preset, size: size,
                                                 seed: seed, pressing: pressing,
                                                 progress: progress)
            try StillRenderer.writePNG(image, to: url)
            print("\(Int(size.width))x\(Int(size.height))  \(preset.name)  →  \(url.path)")
            return 0
        } catch {
            Log.cli("render failed: \(error)")
            return 1
        }
    }

    /// Every scene side by side, which is the only way to judge whether a set
    /// of palettes belongs together.
    private static func contactCommand(_ args: [String]) -> Int32 {
        let options = parse(args)
        let outPath = options["out"] ?? "spindle-contact.png"
        let url = URL(fileURLWithPath: (outPath as NSString).expandingTildeInPath)
        let width = Int(options["width"] ?? "") ?? 560
        do {
            let sheet = try StillRenderer.contactSheet(tileWidth: width)
            try StillRenderer.writePNG(sheet, to: url)
            print("\(ScenePreset.all.count) scenes  →  \(url.path)")
            return 0
        } catch {
            Log.cli("contact sheet failed: \(error)")
            return 1
        }
    }

    private static func iconCommand(_ args: [String]) -> Int32 {
        let options = parse(args)
        let base = options["out"] ?? "icon"
        do {
            let url = try AppIcon.writeICNS(toBasePath: (base as NSString).expandingTildeInPath)
            print(url.path)
            return 0
        } catch {
            Log.cli("icon failed: \(error)")
            return 1
        }
    }

    // MARK: Argument parsing

    /// Minimal `--key value` parser. Nothing here needs a dependency.
    private static func parse(_ args: [String]) -> [String: String] {
        var options: [String: String] = [:]
        var index = 0
        while index < args.count {
            let token = args[index]
            guard token.hasPrefix("--") else { index += 1; continue }
            let key = String(token.dropFirst(2))
            if index + 1 < args.count, !args[index + 1].hasPrefix("--") {
                options[key] = args[index + 1]
                index += 2
            } else {
                options[key] = "true"
                index += 1
            }
        }
        return options
    }
}
