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

    var mode: RenderMode {
        // Nothing can see it, so draw nothing at all.
        if isScreenAsleep || isScreenLocked || !isVisible { return .off }

        // Nothing is moving, so one frame says everything the next one would.
        guard isAnimating || alwaysAnimate else { return .still }

        // A record turns at 33 rpm. It does not need sixty frames a second,
        // and on battery it does not need thirty.
        if isLowPower { return .live(fps: 15) }
        if isOnBattery { return .live(fps: 24) }
        return .live(fps: 30)
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
