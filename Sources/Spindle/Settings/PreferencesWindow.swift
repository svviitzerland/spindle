import AppKit
import SwiftUI

/// Hosts the settings pane.
///
/// Deliberately dark and fixed-width. Spindle's whole job is a lit room on
/// your desktop, and a bright system-chrome panel sitting in front of it
/// looked like a different application.
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
        window.backgroundColor = NSColor(srgbRed: 0.063, green: 0.059, blue: 0.055, alpha: 1)
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: Theme.windowWidth, height: 670))
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
    static let windowWidth: CGFloat = 520

    static let background = Color(red: 0.063, green: 0.059, blue: 0.055)
    static let card = Color(red: 0.102, green: 0.096, blue: 0.090)
    static let cardStroke = Color.white.opacity(0.07)
    static let divider = Color.white.opacity(0.06)

    static let primary = Color(red: 0.961, green: 0.949, blue: 0.929)
    static let secondary = Color(red: 0.961, green: 0.949, blue: 0.929).opacity(0.52)
    static let faint = Color(red: 0.961, green: 0.949, blue: 0.929).opacity(0.30)
    /// The amber from the record label on the app icon.
    static let accent = Color(red: 0.886, green: 0.639, blue: 0.290)

    static let cardRadius: CGFloat = 12
}

// MARK: - Root

struct PreferencesView: View {
    @ObservedObject var preferences: Preferences
    @ObservedObject var nowPlaying: NowPlayingStore
    let onRecheckPermissions: () -> Void

    @StateObject private var previews = ScenePreviewCache()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Wordmark()
                    .padding(.top, 6)

                NowPlayingCard(store: nowPlaying,
                               onRecheckPermissions: onRecheckPermissions)

                ScenePicker(preferences: preferences, previews: previews)

                SettingsCard(preferences: preferences)

                Footer()
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 22)
        }
        .frame(width: Theme.windowWidth)
        .background(Theme.background)
        .onAppear { previews.loadIfNeeded() }
    }
}

private struct Wordmark: View {
    var body: some View {
        Text("Spindle")
            .font(.system(size: 30, weight: .regular, design: .serif))
            .italic()
            .foregroundStyle(Theme.primary)
    }
}

// MARK: - Now playing

private struct NowPlayingCard: View {
    @ObservedObject var store: NowPlayingStore
    let onRecheckPermissions: () -> Void

    var body: some View {
        Card {
            if let denied = store.deniedSource {
                permissionNotice(for: denied)
            } else if let playing = store.playing {
                playingRow(playing)
            } else {
                idleRow
            }
        }
    }

    private func playingRow(_ playing: NowPlaying) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Artwork(image: store.artwork)

            VStack(alignment: .leading, spacing: 3) {
                Text(playing.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.primary)
                    .lineLimit(1)

                Text(playing.artist)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.secondary)
                    .lineLimit(1)

                HStack(spacing: 5) {
                    Circle()
                        .fill(playing.isPlaying ? Theme.accent : Theme.faint)
                        .frame(width: 5, height: 5)
                    Text(playing.isPlaying
                         ? playing.source.displayName
                         : "\(playing.source.displayName) · paused")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.faint)
                }
                .padding(.top, 2)

                // Ticks on its own so the bar creeps forward between polls
                // instead of jumping every couple of seconds.
                TimelineView(.periodic(from: .now, by: 0.5)) { context in
                    Progress(elapsed: store.elapsed(at: context.date),
                             duration: playing.duration)
                }
                .padding(.top, 8)
            }
        }
    }

    private var idleRow: some View {
        HStack(spacing: 14) {
            // Standalone still has a sleeve, the generated one, so show it
            // rather than falling back to the placeholder disc.
            Artwork(image: store.artwork)
            VStack(alignment: .leading, spacing: 3) {
                Text("Nothing playing")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.primary)
                Text("Start a track in Music or Spotify.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.secondary)
            }
            Spacer(minLength: 0)
        }
    }

    private func permissionNotice(for denied: NowPlaying.Source) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "lock.fill")
                    .foregroundStyle(Theme.accent)
                Text("Spindle cannot read \(denied.displayName)")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.primary)
            }
            Text("Allow it under Privacy & Security › Automation, then re-check.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Button("Open Settings") {
                    let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!
                    NSWorkspace.shared.open(url)
                }
                Button("Re-check", action: onRecheckPermissions)
            }
            .controlSize(.small)
        }
    }
}

private struct Artwork: View {
    let image: NSImage?

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Theme.card
                Image(systemName: "opticaldisc")
                    .font(.system(size: 20))
                    .foregroundStyle(Theme.faint)
            }
        }
        .frame(width: 62, height: 62)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        )
    }
}

private struct Progress: View {
    let elapsed: Double
    let duration: Double

    private var fraction: Double {
        guard duration > 0 else { return 0 }
        return min(max(elapsed / duration, 0), 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.10))
                    Capsule()
                        .fill(Theme.accent.opacity(0.85))
                        .frame(width: geometry.size.width * fraction)
                }
            }
            .frame(height: 3)

            HStack {
                Text(NowPlaying.timestamp(elapsed))
                Spacer()
                Text(NowPlaying.timestamp(duration))
            }
            .font(.system(size: 10, design: .monospaced))
            .foregroundStyle(Theme.faint)
        }
    }
}

// MARK: - Scene picker

private struct ScenePicker: View {
    @ObservedObject var preferences: Preferences
    @ObservedObject var previews: ScenePreviewCache

    var body: some View {
        Card(padding: 14) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Scene")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.primary)

                HStack(spacing: 10) {
                    ForEach(ScenePreset.all) { preset in
                        SceneCard(preset: preset,
                                  preview: previews.previews[preset.id],
                                  isSelected: preferences.sceneID == preset.id) {
                            preferences.sceneID = preset.id
                        }
                    }
                }

                Text(preferences.preset.tagline)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.faint)
            }
        }
    }
}

private struct SceneCard: View {
    let preset: ScenePreset
    let preview: NSImage?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                ZStack {
                    if let preview {
                        Image(nsImage: preview)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        // Previews are rendered on launch; until they land,
                        // show the scene's own wall colour rather than a spinner.
                        LinearGradient(colors: [swiftColor(preset.wallTop),
                                                swiftColor(preset.deskBase)],
                                       startPoint: .top, endPoint: .bottom)
                    }
                }
                .frame(height: 84)
                .clipped()

                HStack(spacing: 4) {
                    Text(preset.name)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(isSelected ? Theme.primary : Theme.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 11))
                        .foregroundStyle(isSelected ? Theme.accent : Theme.faint)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 7)
                .background(Theme.card)
            }
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(isSelected ? Theme.accent.opacity(0.85) : Theme.cardStroke,
                            lineWidth: isSelected ? 1.5 : 1)
            )
        }
        .buttonStyle(.plain)
        .help(preset.tagline)
    }

    private func swiftColor(_ c: RGB) -> Color {
        Color(red: c.r, green: c.g, blue: c.b)
    }
}

// MARK: - Settings rows

private struct SettingsCard: View {
    @ObservedObject var preferences: Preferences

    /// Read when the window opens rather than continuously: a json dropped in
    /// the folder should show up, but not at the cost of hitting the disk on
    /// every redraw.
    @State private var pressings: [Pressing] = PressingLibrary.builtIn()

    /// Reads and writes the login-item service directly, so the checkbox can
    /// never drift from what macOS actually registered.
    private var launchAtLogin: Binding<Bool> {
        Binding(get: { preferences.launchAtLogin },
                set: { preferences.launchAtLogin = $0 })
    }

    var body: some View {
        Card(padding: 0) {
            VStack(spacing: 0) {
                Row(icon: "record.circle", title: "Pressing") {
                    HStack(spacing: 7) {
                        Picker("", selection: $preferences.pressingID) {
                            ForEach(pressings) { pressing in
                                Text(pressing.name).tag(pressing.id)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 142)

                        Button {
                            guard let url = try? PressingLibrary.directory() else { return }
                            NSWorkspace.shared.open(url)
                        } label: {
                            Image(systemName: "folder")
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(Theme.faint)
                        .help("Add your own records here")
                    }
                }

                Row(icon: "textformat", title: "Show track on desktop") {
                    Toggle("", isOn: $preferences.showTrackInfo).labelsHidden()
                }

                Row(icon: "pause.circle", title: "Keep turning when paused") {
                    Toggle("", isOn: $preferences.spinWhenPaused).labelsHidden()
                }

                Row(icon: "lock.display",
                    title: "Use on the lock screen",
                    subtitle: "Sets your desktop picture to a still of this scene.") {
                    Toggle("", isOn: $preferences.lockScreenBackground).labelsHidden()
                }

                Row(icon: "power", title: "Open at login", isLast: true) {
                    Toggle("", isOn: launchAtLogin).labelsHidden()
                }
            }
        }
        .toggleStyle(.switch)
        .tint(Theme.accent)
        .onAppear {
            pressings = PressingLibrary.all()
            // A record that has since been deleted would otherwise leave the
            // picker showing nothing at all.
            if !pressings.contains(where: { $0.id == preferences.pressingID }) {
                preferences.pressingID = Pressing.black.id
            }
        }
    }
}

private struct Row<Content: View>: View {
    let icon: String
    let title: String
    var subtitle: String? = nil
    var isLast: Bool = false
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 11) {
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.faint)
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.primary)
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.faint)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer(minLength: 12)
                content
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .frame(minHeight: 46)

            if !isLast {
                Rectangle()
                    .fill(Theme.divider)
                    .frame(height: 1)
                    .padding(.leading, 43)
            }
        }
    }
}

// MARK: - Shell

private struct Card<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card.opacity(0.65))
            .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                    .stroke(Theme.cardStroke, lineWidth: 1)
            )
    }
}

private struct Footer: View {
    /// Where the project lives. Clicking the credit opens it.
    private static let author = "svviitzerland"
    private static let profile = URL(string: "https://github.com/svviitzerland/spindle")!

    @State private var isHovering = false

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    var body: some View {
        HStack {
            Text("Spindle \(version)")

            Spacer()

            Link(destination: Self.profile) {
                Text("by \(Self.author)")
                    .underline(isHovering)
                    .foregroundStyle(isHovering ? Theme.accent : Theme.faint)
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                isHovering = hovering
                // A link should admit it is one before you click it. Using
                // set() rather than push()/pop(), which leaves the cursor
                // stack unbalanced if the window closes mid-hover.
                (hovering ? NSCursor.pointingHand : NSCursor.arrow).set()
            }
            .help(Self.profile.absoluteString)
        }
        .font(.system(size: 10))
        .foregroundStyle(Theme.faint)
        .padding(.top, 2)
    }
}
