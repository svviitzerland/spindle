import AppKit

// `spindle render`, `spindle icon` and friends finish here without ever
// touching NSApplication. Anything else is the app itself.
if let status = CommandLineTool.run(CommandLine.arguments) {
    exit(status)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
// A wallpaper has no Dock tile and no windows to bring forward.
app.setActivationPolicy(.accessory)
app.run()
