import Foundation
import os

/// One logger for the whole app. `log stream --predicate 'subsystem == "com.spindle.wallpaper"'`
/// in Terminal gives you a live trace without attaching a debugger.
enum Log {
    private static let core = Logger(subsystem: "com.spindle.wallpaper", category: "core")

    static func info(_ message: String) { core.info("\(message, privacy: .public)") }
    static func warn(_ message: String) { core.warning("\(message, privacy: .public)") }
    static func error(_ message: String) { core.error("\(message, privacy: .public)") }

    /// Printed to stdout as well, for the CLI subcommands where nobody is
    /// watching Console.app.
    static func cli(_ message: String) {
        FileHandle.standardError.write(Data(("spindle: " + message + "\n").utf8))
    }
}
