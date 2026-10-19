import AppKit

/// Puts the current scene on the lock screen, as far as macOS allows.
///
/// No third-party app can draw on the lock screen. It belongs to the login
/// window, in a different session, and its image is protected by System
/// Integrity Protection. The one lever that exists is this: while you are
/// still logged in, macOS uses your Desktop Picture as the lock screen
/// background. So Spindle renders a still frame of the scene and sets it as
/// the desktop picture.
///
/// You never see that picture while you are working, because Spindle's own
/// window covers it. You see it when the screen locks.
///
/// This changes a system setting, so it is off by default, and the previous
/// wallpaper is remembered and put back when you turn it off.
final class LockScreenBackground {

    private enum Key {
        static let previous = "lockScreenPreviousWallpaper"
    }

    private let defaults: UserDefaults
    private let workspace = NSWorkspace.shared
    private let queue = DispatchQueue(label: "com.spindle.lockscreen", qos: .utility)

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: Applying

    /// Render `preset` at each display's native resolution and set it as that
    /// display's wallpaper. Rendering is slow enough to matter at 5K, so it
    /// happens off the main thread.
    func apply(preset: ScenePreset, pressing: Pressing = .black,
               completion: ((Error?) -> Void)? = nil) {
        let displays = NSScreen.screens.map {
            (screen: $0, id: Self.displayID(for: $0), pixels: Self.pixelSize(of: $0))
        }
        rememberCurrentWallpapers(for: displays.map(\.id))

        queue.async { [weak self] in
            guard let self else { return }
            var failure: Error?
            var rendered: [String: URL] = [:]

            for display in displays {
                do {
                    let url = try self.renderFile(preset: preset,
                                                  pressing: pressing,
                                                  pixels: display.pixels,
                                                  displayID: display.id)
                    rendered[display.id] = url
                } catch {
                    failure = error
                    Log.warn("lock screen render failed: \(error)")
                }
            }

            DispatchQueue.main.async {
                // Re-read the screens: the user may have unplugged one while
                // a 5K frame was rendering.
                for screen in NSScreen.screens {
                    let id = Self.displayID(for: screen)
                    guard let url = rendered[id] else { continue }
                    do {
                        try self.workspace.setDesktopImageURL(url, for: screen, options: [
                            .imageScaling: NSImageScaling.scaleProportionallyUpOrDown.rawValue,
                            .allowClipping: true,
                        ])
                    } catch {
                        failure = error
                        Log.warn("could not set wallpaper: \(error)")
                    }
                }
                self.pruneOldRenders(keeping: Set(rendered.values.map(\.lastPathComponent)))
                completion?(failure)
            }
        }
    }

    /// Put back whatever the wallpaper was before Spindle touched it.
    func restore() {
        guard let saved = defaults.dictionary(forKey: Key.previous) as? [String: String] else {
            return
        }
        for screen in NSScreen.screens {
            let id = Self.displayID(for: screen)
            guard let path = saved[id] else { continue }
            let url = URL(fileURLWithPath: path)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            try? workspace.setDesktopImageURL(url, for: screen, options: [:])
        }
        defaults.removeObject(forKey: Key.previous)
        pruneOldRenders(keeping: [])
    }

    // MARK: Previous wallpaper

    /// Recorded once, the first time this is switched on. Re-recording later
    /// would capture Spindle's own render and make restore a no-op.
    private func rememberCurrentWallpapers(for ids: [String]) {
        guard defaults.dictionary(forKey: Key.previous) == nil else { return }
        var saved: [String: String] = [:]
        for screen in NSScreen.screens {
            let id = Self.displayID(for: screen)
            guard ids.contains(id), let url = workspace.desktopImageURL(for: screen) else { continue }
            saved[id] = url.path
        }
        defaults.set(saved, forKey: Key.previous)
    }

    // MARK: Files

    private func renderFile(preset: ScenePreset, pressing: Pressing,
                            pixels: CGSize, displayID: String) throws -> URL {
        let image = try StillRenderer.render(preset: preset,
                                             size: pixels,
                                             seed: Preferences.Fixed.sleeveSeed,
                                             pressing: pressing)
        // A fresh filename every time: macOS caches the wallpaper by path, so
        // overwriting one in place does not always take effect.
        let name = "\(preset.id)-\(displayID)-\(Int(Date().timeIntervalSince1970)).png"
        let url = try Self.directory().appendingPathComponent(name)
        try StillRenderer.writePNG(image, to: url)
        return url
    }

    private func pruneOldRenders(keeping names: Set<String>) {
        guard let directory = try? Self.directory(),
              let files = try? FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: nil) else { return }
        for file in files where file.pathExtension == "png" && !names.contains(file.lastPathComponent) {
            try? FileManager.default.removeItem(at: file)
        }
    }

    private static func directory() throws -> URL {
        let base = try FileManager.default.url(for: .applicationSupportDirectory,
                                               in: .userDomainMask,
                                               appropriateFor: nil,
                                               create: true)
        let directory = base.appendingPathComponent("Spindle/LockScreen", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    // MARK: Screens

    /// Stable across relaunches, unlike an NSScreen reference.
    private static func displayID(for screen: NSScreen) -> String {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        let number = screen.deviceDescription[key] as? NSNumber
        return number.map { "\($0.uint32Value)" } ?? "main"
    }

    private static func pixelSize(of screen: NSScreen) -> CGSize {
        CGSize(width: screen.frame.width * screen.backingScaleFactor,
               height: screen.frame.height * screen.backingScaleFactor)
    }
}
