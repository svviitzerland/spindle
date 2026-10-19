import AppKit
import Combine

/// Menu-bar lifecycle. Spindle has no main window: the wallpaper is the app,
/// and this is the only thing you can click.
final class AppDelegate: NSObject, NSApplicationDelegate {

    private let preferences = Preferences.shared
    private let nowPlaying = NowPlayingStore()
    private lazy var controller = WallpaperController(preferences: preferences,
                                                      nowPlaying: nowPlaying)
    private var statusItem: NSStatusItem?
    private var preferencesWindow: PreferencesWindowController?
    private var cancellables: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Explain the Records format in the folder itself, where whoever
        // opens it will actually read it.
        PressingLibrary.installGuideIfNeeded()
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

    /// Spindle has no windows, so opening it again from Finder or Spotlight
    /// would otherwise do nothing at all. Show the settings instead.
    func applicationShouldHandleReopen(_ sender: NSApplication,
                                       hasVisibleWindows: Bool) -> Bool {
        openPreferences()
        return true
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

        menu.addItem(.separator())

        let recordsItem = NSMenuItem(title: "Open Records Folder…",
                                     action: #selector(openRecordsFolder),
                                     keyEquivalent: "")
        recordsItem.target = self
        menu.addItem(recordsItem)

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

    @objc private func openRecordsFolder() {
        guard let url = try? PressingLibrary.directory() else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func openPreferences() {
        if preferencesWindow == nil {
            preferencesWindow = PreferencesWindowController(
                preferences: preferences,
                nowPlaying: nowPlaying,
                onRecheckPermissions: { [weak self] in self?.controller.refreshPermissions() })
        }
        preferencesWindow?.present()
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
}
