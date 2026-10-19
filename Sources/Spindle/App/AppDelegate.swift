import AppKit
import Combine

/// Menu-bar lifecycle. Spindle has no main window: the wallpaper is the app,
/// and this is the only thing you can click.
final class AppDelegate: NSObject, NSApplicationDelegate {

    private let preferences = Preferences.shared
    private lazy var controller = WallpaperController(preferences: preferences)
    private var statusItem: NSStatusItem?
    private var preferencesWindow: PreferencesWindowController?
    private var cancellables: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildStatusItem()
        controller.onPermissionDenied = { [weak self] source in
            self?.presentAutomationHelp(for: source)
        }
        controller.start()

        // The menu shows the current scene with a tick, so it has to be
        // rebuilt whenever anything it displays changes.
        preferences.objectWillChange
            .debounce(for: .milliseconds(50), scheduler: RunLoop.main)
            .sink { [weak self] in self?.rebuildMenu() }
            .store(in: &cancellables)

        Log.info("spindle running")
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller.stop()
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }

    // MARK: Status item

    private func buildStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "opticaldisc",
                                   accessibilityDescription: "Spindle")
            button.image?.isTemplate = true
        }
        statusItem = item
        rebuildMenu()
    }

    private func rebuildMenu() {
        let menu = NSMenu()

        let header = NSMenuItem(title: "Spindle", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        for preset in ScenePreset.all {
            let item = NSMenuItem(title: preset.name,
                                  action: #selector(selectScene(_:)),
                                  keyEquivalent: "")
            item.target = self
            item.representedObject = preset.id
            item.state = preferences.sceneID == preset.id ? .on : .off
            menu.addItem(item)
        }

        menu.addItem(.separator())

        let sourceItem = NSMenuItem(title: "Follow", action: nil, keyEquivalent: "")
        let sourceMenu = NSMenu()
        for option in NowPlayingMonitor.Preference.allCases {
            let item = NSMenuItem(title: option.displayName,
                                  action: #selector(selectSource(_:)),
                                  keyEquivalent: "")
            item.target = self
            item.representedObject = option.rawValue
            item.state = preferences.source == option ? .on : .off
            sourceMenu.addItem(item)
        }
        sourceItem.submenu = sourceMenu
        menu.addItem(sourceItem)

        let exportItem = NSMenuItem(title: "Save Current Scene as Image…",
                                    action: #selector(exportStill),
                                    keyEquivalent: "s")
        exportItem.target = self
        menu.addItem(exportItem)

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: "Settings…",
                                      action: #selector(openPreferences),
                                      keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let quitItem = NSMenuItem(title: "Quit Spindle",
                                  action: #selector(NSApplication.terminate(_:)),
                                  keyEquivalent: "q")
        menu.addItem(quitItem)

        statusItem?.menu = menu
    }

    // MARK: Actions

    @objc private func selectScene(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        preferences.sceneID = id
    }

    @objc private func selectSource(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let option = NowPlayingMonitor.Preference(rawValue: raw) else { return }
        preferences.source = option
    }

    @objc private func openPreferences() {
        if preferencesWindow == nil {
            preferencesWindow = PreferencesWindowController(preferences: preferences) {
                [weak self] in self?.controller.refreshPermissions()
            }
        }
        preferencesWindow?.present()
    }

    /// Render the current scene at the main display's resolution and let the
    /// user keep it — a live wallpaper is not much use as a lock screen.
    @objc private func exportStill() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "\(preferences.sceneID).png"
        panel.title = "Save Scene as Image"
        NSApp.activate(ignoringOtherApps: true)

        guard panel.runModal() == .OK, let url = panel.url else { return }
        let screen = NSScreen.main ?? NSScreen.screens.first
        let scale = screen?.backingScaleFactor ?? 2
        let size = screen.map {
            CGSize(width: $0.frame.width * scale, height: $0.frame.height * scale)
        } ?? CGSize(width: 2560, height: 1440)

        do {
            let image = try StillRenderer.render(preset: preferences.preset,
                                                 size: size,
                                                 seed: preferences.seed)
            try StillRenderer.writePNG(image, to: url)
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            present(error: "Could not save the image.", detail: "\(error)")
        }
    }

    // MARK: Permission help

    /// macOS only prompts once. If the answer was no, nothing in the app can
    /// re-ask, so point the user straight at the right settings pane.
    private func presentAutomationHelp(for source: NowPlaying.Source) {
        let alert = NSAlert()
        alert.messageText = "Spindle cannot read \(source.displayName)"
        alert.informativeText = """
        macOS has not granted Spindle permission to talk to \(source.displayName), \
        so the record will keep showing its own artwork.

        Open Privacy & Security › Automation, enable \(source.displayName) under \
        Spindle, then choose "Re-check permissions" in Settings.
        """
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "Not Now")
        NSApp.activate(ignoringOtherApps: true)

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!
        NSWorkspace.shared.open(url)
    }

    private func present(error message: String, detail: String) {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = detail
        alert.alertStyle = .warning
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
