import AppKit
import SwiftUI

/// Hosts the settings pane.
///
/// Built around a large preview rather than a list of controls. The one thing
/// you come here to do is choose how the desktop looks, so the window shows
/// that at size and keeps everything else to a strip underneath. It is also
/// deliberately dark: Spindle's whole job is a lit room on your desktop, and a
/// bright system-chrome panel in front of it read as a different application.
final class PreferencesWindowController: NSWindowController {

    convenience init(preferences: Preferences,
                     nowPlaying: NowPlayingStore,
                     onRecheckPermissions: @escaping () -> Void) {
        let view = PreferencesView(preferences: preferences,
                                   nowPlaying: nowPlaying,
                                   onRecheckPermissions: onRecheckPermissions)
        let hosting = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hosting)
        window.title = "Spindle"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.isMovableByWindowBackground = true
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = NSColor(srgbRed: 0.055, green: 0.052, blue: 0.050, alpha: 1)
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: Theme.windowWidth, height: 742))
        window.center()
        self.init(window: window)
    }

    func present() {
        // The app is an accessory, so it has to ask for focus explicitly.
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

// MARK: - Theme

private enum Theme {
    static let windowWidth: CGFloat = 660
    /// The preview is 16:9 because the scenes are composed for a screen.
    static var heroHeight: CGFloat { windowWidth * 9 / 16 }

    static let background = Color(red: 0.055, green: 0.052, blue: 0.050)
    static let raised = Color(red: 0.098, green: 0.094, blue: 0.090)
    static let hairline = Color.white.opacity(0.07)

    static let primary = Color(red: 0.964, green: 0.953, blue: 0.933)
    static let secondary = Color(red: 0.964, green: 0.953, blue: 0.933).opacity(0.54)
    static let faint = Color(red: 0.964, green: 0.953, blue: 0.933).opacity(0.32)
    /// The amber from the record label on the app icon.
    static let accent = Color(red: 0.886, green: 0.639, blue: 0.290)
}

private extension RGB {
    var color: Color { Color(red: r, green: g, blue: b) }
}

// MARK: - Root

struct PreferencesView: View {
    @ObservedObject var preferences: Preferences
    @ObservedObject var nowPlaying: NowPlayingStore
    let onRecheckPermissions: () -> Void

    @StateObject private var previews = ScenePreviewCache()

    var body: some View {
        VStack(spacing: 0) {
            Hero(preset: preferences.activePreset,
                 preview: previews.previews[preferences.activePreset.id],
                 isAutomatic: preferences.followsClock,
                 store: nowPlaying)

            SceneStrip(preferences: preferences, previews: previews)

            if let denied = nowPlaying.deniedSource {
                PermissionBanner(source: denied, onRecheck: onRecheckPermissions)
            }

            Controls(preferences: preferences)

            Spacer(minLength: 0)
            Footer()
        }
        .frame(width: Theme.windowWidth)
        .background(Theme.background)
        .onAppear { previews.loadIfNeeded(first: preferences.sceneID) }
    }
}

// MARK: - Hero

/// The selected scene, at size, with everything else written over it.
private struct Hero: View {
    let preset: ScenePreset
    let preview: NSImage?
    var isAutomatic = false
    @ObservedObject var store: NowPlayingStore

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Group {
                if let preview {
                    Image(nsImage: preview)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    // Until the render lands, the scene's own wall and desk.
                    // A spinner here would just advertise the wait.
                    LinearGradient(colors: [preset.wallTop.color, preset.deskBase.color],
                                   startPoint: .top, endPoint: .bottom)
                }
            }
            .frame(width: Theme.windowWidth, height: Theme.heroHeight)
            .clipped()

            // Scrim, so the caption stays legible over a bright scene.
            LinearGradient(colors: [.clear, .black.opacity(0.78)],
                           startPoint: .center, endPoint: .bottom)
                .frame(height: Theme.heroHeight * 0.55)
                .allowsHitTesting(false)

            caption
                .padding(.horizontal, 18)
                .padding(.bottom, 14)
        }
        .frame(width: Theme.windowWidth, height: Theme.heroHeight)
        .overlay(alignment: .topLeading) {
            Text("Spindle")
                .font(.system(size: 19, weight: .regular, design: .serif))
                .italic()
                .foregroundStyle(.white.opacity(0.92))
                .shadow(color: .black.opacity(0.5), radius: 6, y: 1)
                .padding(.leading, 18)
                .padding(.top, 14)
        }
    }

    private var caption: some View {
        HStack(alignment: .bottom, spacing: 12) {
            if let playing = store.playing {
                Artwork(image: store.artwork, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(playing.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    HStack(spacing: 5) {
                        Circle()
                            .fill(playing.isPlaying ? Theme.accent : .white.opacity(0.4))
                            .frame(width: 4, height: 4)
                        Text(playing.isPlaying
                             ? playing.artist
                             : "\(playing.artist) · paused")
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.68))
                            .lineLimit(1)
                    }
                }
            } else {
                Artwork(image: store.artwork, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Nothing playing")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                    Text("Start a track in Music or Spotify")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.62))
                }
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 2) {
                HStack(spacing: 5) {
                    if isAutomatic {
                        Image(systemName: "clock")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                    }
                    Text(preset.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                }
                // Only when it adds something: half the scenes are named
                // after their palette, and "Clay / CLAY" is just noise.
                if preset.palette.name != preset.name {
                    Text(preset.palette.name.uppercased())
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.52))
                }
            }
        }
        .shadow(color: .black.opacity(0.45), radius: 8, y: 1)
    }
}

private struct Artwork: View {
    let image: NSImage?
    var size: CGFloat

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                Color.black.opacity(0.45)
                Image(systemName: "opticaldisc")
                    .font(.system(size: size * 0.38))
                    .foregroundStyle(.white.opacity(0.4))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous)
            .stroke(.white.opacity(0.22), lineWidth: 1))
    }
}

// MARK: - Scene strip

/// Every scene across one row, like contact prints under an enlarger. All of
/// them are visible at once; nothing is hidden behind a scroll or a menu.
private struct SceneStrip: View {
    @ObservedObject var preferences: Preferences
    @ObservedObject var previews: ScenePreviewCache

    private var activeID: String { preferences.activePreset.id }

    var body: some View {
        HStack(spacing: 6) {
            ForEach(ScenePreset.all) { preset in
                Tile(preset: preset,
                     preview: previews.previews[preset.id],
                     isSelected: activeID == preset.id,
                     isAutomatic: preferences.followsClock) {
                    // Choosing a room by hand is a statement that you want
                    // that room, so it takes the clock out of the loop.
                    preferences.followsClock = false
                    preferences.sceneID = preset.id
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .background(Theme.raised)
        .overlay(alignment: .top) { Rectangle().fill(Theme.hairline).frame(height: 1) }
    }

    private struct Tile: View {
        let preset: ScenePreset
        let preview: NSImage?
        let isSelected: Bool
        var isAutomatic = false
        let action: () -> Void

        var body: some View {
            Button(action: action) {
                VStack(spacing: 4) {
                    ZStack {
                        if let preview {
                            Image(nsImage: preview).resizable().aspectRatio(contentMode: .fill)
                        } else {
                            LinearGradient(colors: [preset.wallTop.color, preset.deskBase.color],
                                           startPoint: .top, endPoint: .bottom)
                        }
                    }
                    .frame(height: 42)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .stroke(isSelected ? Theme.accent : .white.opacity(0.10),
                                lineWidth: isSelected ? 2 : 1))

                    HStack(spacing: 3) {
                        if isSelected && isAutomatic {
                            Image(systemName: "clock")
                                .font(.system(size: 7, weight: .semibold))
                                .foregroundStyle(Theme.accent)
                        }
                        Text(preset.name)
                            .font(.system(size: 9, weight: isSelected ? .semibold : .regular))
                            .foregroundStyle(isSelected ? Theme.primary : Theme.faint)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
            }
            .buttonStyle(.plain)
            .help(preset.tagline)
        }
    }
}

// MARK: - Controls

private struct Controls: View {
    @ObservedObject var preferences: Preferences
    @State private var pressings: [Pressing] = PressingLibrary.builtIn()

    /// Reads and writes the login-item service directly, so the checkbox can
    /// never drift from what macOS actually registered.
    private var launchAtLogin: Binding<Bool> {
        Binding(get: { preferences.launchAtLogin },
                set: { preferences.launchAtLogin = $0 })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            pressingRow

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 18),
                                GridItem(.flexible(), spacing: 18)],
                      spacing: 10) {
                Switch(title: "Follow the clock",
                       help: "Changes the room through the day and moves the sun with it.",
                       isOn: $preferences.followsClock)
                Switch(title: "Show track on desktop", isOn: $preferences.showTrackInfo)
                Switch(title: "Show lyrics",
                       help: "From your Music library, if a track has any stored.",
                       isOn: $preferences.showLyrics)
                Switch(title: "Look lyrics up online",
                       help: "Sends the track name, artist, album and length to "
                           + "lrclib.net. The only thing Spindle ever sends anywhere, "
                           + "and how Spotify gets lyrics at all.",
                       isOn: $preferences.lyricsLookup)
                Switch(title: "Keep turning when paused", isOn: $preferences.spinWhenPaused)
                Switch(title: "Use on the lock screen",
                       help: "Sets your desktop picture to a still of this scene.",
                       isOn: $preferences.lockScreenBackground)
                Switch(title: "Open at login", isOn: launchAtLogin)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 4)
        .toggleStyle(.switch)
        .tint(Theme.accent)
        .onAppear { pressings = PressingLibrary.all() }
    }

    /// Pressings as actual discs. A dropdown of colour names is a worse way to
    /// pick a colour than the colours themselves.
    private var pressingRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("PRESSING")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Theme.faint)
                Text(PressingLibrary.pressing(id: preferences.pressingID).name)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.secondary)
                Spacer()
                Button {
                    guard let url = try? PressingLibrary.directory() else { return }
                    NSWorkspace.shared.open(url)
                } label: {
                    Label("Add your own", systemImage: "folder")
                        .font(.system(size: 10))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.faint)
                .help("Drop a json in the Records folder")
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 30), spacing: 8)],
                      alignment: .leading, spacing: 8) {
                ForEach(pressings) { pressing in
                    Disc(pressing: pressing,
                         isSelected: preferences.pressingID == pressing.id) {
                        preferences.pressingID = pressing.id
                    }
                }
            }
        }
    }

    private struct Disc: View {
        let pressing: Pressing
        let isSelected: Bool
        let action: () -> Void

        var body: some View {
            Button(action: action) {
                ZStack {
                    Circle().fill(pressing.color.color)
                    // The label, so a swatch reads as a record rather than a dot.
                    Circle().fill(Color.black.opacity(0.55)).frame(width: 9, height: 9)
                    Circle().fill(Theme.background).frame(width: 2.5, height: 2.5)
                }
                .frame(width: 26, height: 26)
                .overlay(Circle().stroke(isSelected ? Theme.accent : .white.opacity(0.14),
                                         lineWidth: isSelected ? 2 : 1))
            }
            .buttonStyle(.plain)
            .help(pressing.name)
        }
    }

    private struct Switch: View {
        let title: String
        var help: String?
        @Binding var isOn: Bool

        var body: some View {
            HStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Spacer(minLength: 4)
                Toggle("", isOn: $isOn).labelsHidden()
            }
            .help(help ?? "")
        }
    }
}

// MARK: - Permission banner

private struct PermissionBanner: View {
    let source: NowPlaying.Source
    let onRecheck: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "lock.fill").foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 1) {
                Text("Spindle cannot read \(source.displayName)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.primary)
                Text("Allow it under Privacy & Security › Automation, then re-check.")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.secondary)
            }
            Spacer(minLength: 8)
            Button("Open") {
                let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!
                NSWorkspace.shared.open(url)
            }
            Button("Re-check", action: onRecheck)
        }
        .controlSize(.small)
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(Theme.accent.opacity(0.10))
    }
}

// MARK: - Footer

private struct Footer: View {
    private static let author = "svviitzerland"
    private static let project = URL(string: "https://github.com/svviitzerland/spindle")!

    @State private var isHovering = false

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    var body: some View {
        HStack {
            Text("Spindle \(version)")
            Spacer()
            Link(destination: Self.project) {
                Text("by \(Self.author)")
                    .underline(isHovering)
                    .foregroundStyle(isHovering ? Theme.accent : Theme.faint)
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                isHovering = hovering
                // set() rather than push()/pop(), which leaves the cursor
                // stack unbalanced if the window closes mid-hover.
                (hovering ? NSCursor.pointingHand : NSCursor.arrow).set()
            }
        }
        .font(.system(size: 10))
        .foregroundStyle(Theme.faint)
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .overlay(alignment: .top) { Rectangle().fill(Theme.hairline).frame(height: 1) }
    }
}
