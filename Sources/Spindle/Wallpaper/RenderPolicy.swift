import AppKit
import IOKit.ps

/// What the wallpaper should be doing right now.
///
/// Spindle spends most of its life drawing a room that nobody is looking at:
/// buried under windows, or sitting still because no music is playing. A
/// turntable with nothing on it is a photograph, and a photograph costs
/// nothing to display. The whole point of this type is to notice that.
enum RenderMode: Equatable {
    /// Animating, at this frame rate.
    case live(fps: Int)
    /// One frame, held. Costs what a desktop picture costs.
    case still
    /// Not drawn at all: covered, asleep or locked.
    case off

    var isLive: Bool { if case .live = self { return true }; return false }
}

/// The inputs that decide it, gathered in one place so the decision can be
/// read, and tested, without a window attached.
struct RenderPolicy: Equatable {
    /// macOS says at least part of the window is on screen.
    var isVisible = true
    /// The platter is turning, or the arm is moving.
    var isAnimating = false
    var isScreenAsleep = false
    var isScreenLocked = false
    var isLowPower = false
    var isOnBattery = false
    /// Keep the dust and the leaves moving even with nothing playing.
    var alwaysAnimate = false
    /// What the display can actually show, so the frame rate can divide it.
    var displayRefresh = 60

    var mode: RenderMode {
        // Nothing can see it, so draw nothing at all.
        if isScreenAsleep || isScreenLocked || !isVisible { return .off }

        // Nothing is moving, so one frame says everything the next one would.
        guard isAnimating || alwaysAnimate else { return .still }

        // Only Low Power Mode gets a reduced rate, because that is the one
        // place the machine has been told to save power. The saving that
        // matters is not drawing at all when nothing moves, which is already
        // handled above; shaving frames off the one moment somebody is
        // actually watching buys little and is immediately visible.
        if isLowPower { return .live(fps: Self.evenDivisor(of: displayRefresh, upTo: 30)) }
        return .live(fps: Self.evenDivisor(of: displayRefresh, upTo: 60))
    }

    /// The fastest rate at or below `limit` that divides the refresh exactly.
    ///
    /// Frames landing on an uneven cadence judder: 24 on a 60 Hz display is
    /// two and a half refreshes per frame, and a turning record with fine
    /// grooves shows it plainly. Dividing exactly is always safe, on 60 Hz
    /// panels and on 120 Hz ones.
    static func evenDivisor(of refresh: Int, upTo limit: Int) -> Int {
        guard refresh > 0 else { return limit }
        for step in 1...max(refresh, 1) where refresh % step == 0 {
            let rate = refresh / step
            if rate <= limit { return rate }
        }
        return min(refresh, limit)
    }
}

// MARK: - Power

enum PowerSource {
    /// True when the Mac is running off its own battery.
    ///
    /// `IOPSGetTimeRemainingEstimate` reports an unlimited estimate while
    /// something is plugged in, which is a cheaper question than walking the
    /// whole power-source list.
    static var isOnBattery: Bool {
        IOPSGetTimeRemainingEstimate() != kIOPSTimeRemainingUnlimited
    }

    static var isLowPower: Bool {
        ProcessInfo.processInfo.isLowPowerModeEnabled
    }
}
