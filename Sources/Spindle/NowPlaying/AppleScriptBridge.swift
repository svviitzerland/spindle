import AppKit
import Foundation

/// Runs AppleScript against the music apps.
///
/// Spindle deliberately uses Apple Events rather than a web API: it needs no
/// account, no OAuth redirect and no API key, and the data never leaves the
/// machine. The cost is one permission prompt per app, the first time.
final class AppleScriptBridge {

    enum BridgeError: Error, CustomStringConvertible {
        case notRunning
        case compileFailed(String)
        case executionFailed(String)

        var description: String {
            switch self {
            case .notRunning: return "app is not running"
            case .compileFailed(let m): return "compile failed: \(m)"
            case .executionFailed(let m): return "execution failed: \(m)"
            }
        }
    }

    /// NSAppleScript is not thread-safe, so every call goes through one queue.
    private let queue = DispatchQueue(label: "com.spindle.applescript")
    private var compiled: [String: NSAppleScript] = [:]

    /// True when the app is already open. Checked through NSWorkspace rather
    /// than AppleScript, because `tell application "Spotify"` would *launch*
    /// Spotify — a wallpaper has no business doing that.
    func isRunning(_ bundleIdentifier: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty
    }

    /// Execute `source`, reusing the compiled script across polls.
    func run(_ source: String, cacheKey: String) throws -> NSAppleEventDescriptor {
        try queue.sync {
            let script: NSAppleScript
            if let existing = compiled[cacheKey] {
                script = existing
            } else {
                guard let fresh = NSAppleScript(source: source) else {
                    throw BridgeError.compileFailed(cacheKey)
                }
                var compileError: NSDictionary?
                guard fresh.compileAndReturnError(&compileError) else {
                    throw BridgeError.compileFailed(describe(compileError))
                }
                compiled[cacheKey] = fresh
                script = fresh
            }

            var runError: NSDictionary?
            let result = script.executeAndReturnError(&runError)
            if let runError {
                throw BridgeError.executionFailed(describe(runError))
            }
            return result
        }
    }

    private func describe(_ error: NSDictionary?) -> String {
        guard let error else { return "unknown" }
        let message = error[NSAppleScript.errorMessage] as? String ?? "unknown"
        let number = error[NSAppleScript.errorNumber] as? Int
        return number.map { "\(message) (\($0))" } ?? message
    }

    /// Whether the failure means "the user said no to automation".
    static func isPermissionDenial(_ error: Error) -> Bool {
        guard case BridgeError.executionFailed(let message) = error else { return false }
        // -1743 is errAEEventNotPermitted; -600 is "application isn't running".
        return message.contains("-1743") || message.contains("Not authorized")
    }
}
