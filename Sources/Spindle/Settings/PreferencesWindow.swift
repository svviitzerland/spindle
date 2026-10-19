import AppKit
import SwiftUI

/// Hosts the settings pane. Kept as one small window rather than a tabbed
/// Settings scene, because there is not enough here to need tabs.
final class PreferencesWindowController: NSWindowController {

    convenience init(preferences: Preferences, onRecheckPermissions: @escaping () -> Void) {
        let view = PreferencesView(preferences: preferences,
                                   onRecheckPermissions: onRecheckPermissions)
        let hosting = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hosting)
        window.title = "Spindle"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.setContentSize(NSSize(width: 460, height: 500))
        window.isReleasedWhenClosed = false
        window.center()
        self.init(window: window)
    }

    func present() {
        // The app is an accessory, so it has to ask for focus explicitly.
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

struct PreferencesView: View {
    @ObservedObject var preferences: Preferences
    let onRecheckPermissions: () -> Void

    /// Reads and writes the login-item service directly, so the checkbox can
    /// never drift from what macOS actually registered.
    private var launchAtLogin: Binding<Bool> {
        Binding(get: { preferences.launchAtLogin },
                set: { preferences.launchAtLogin = $0 })
    }

    var body: some View {
        Form {
            Section("Scene") {
                Picker("Mood", selection: $preferences.sceneID) {
                    ForEach(ScenePreset.all) { preset in
                        Text(preset.name).tag(preset.id)
                    }
                }
                .pickerStyle(.radioGroup)

                Text(preferences.preset.tagline)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section("Music") {
                Picker("Follow", selection: $preferences.source) {
                    ForEach(NowPlayingMonitor.Preference.allCases) { option in
                        Text(option.displayName).tag(option)
                    }
                }
                Toggle("Show track name on the desktop", isOn: $preferences.showTrackInfo)
                Toggle("Keep the platter turning when paused", isOn: $preferences.spinWhenPaused)

                HStack {
                    Text("Check every")
                    Slider(value: $preferences.pollInterval, in: 1...10, step: 0.5)
                    Text("\(preferences.pollInterval, specifier: "%.1f")s")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }

                Button("Re-check permissions", action: onRecheckPermissions)
                    .help("Use this after allowing Spindle in Privacy & Security › Automation.")
            }

            Section("When nothing is playing") {
                TextField("Sleeve seed", text: $preferences.seed)
                    .help("Any text. The same text always draws the same sleeve.")
                Text("Spindle draws its own cover art instead of shipping anyone else's.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section("System") {
                Picker("Frame rate", selection: $preferences.frameRateLimit) {
                    Text("24 fps").tag(24)
                    Text("30 fps").tag(30)
                    Text("60 fps").tag(60)
                }
                Toggle("Open at login", isOn: launchAtLogin)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
    }
}
