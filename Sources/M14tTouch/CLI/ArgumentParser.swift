import Foundation

/// Parses command-line arguments into a `TouchConfig` (or a control action).
///
/// Kept separate from `main.swift` so the parsing logic is a pure function of
/// its input array and could be unit tested without launching the driver.
enum ArgumentParser {

    /// The outcome of parsing — either run with a config, or perform a one-shot
    /// action and exit.
    enum Outcome {
        case run(TouchConfig)
        case listDisplays
        case resetCalibration
        case help
        case error(String)
    }

    /// - Parameter defaults: the configuration arguments start from, so a flag
    ///   overrides a stored setting rather than the compiled default. Callers
    ///   that have no stored settings — every test here — get the defaults.
    static func parse(_ arguments: [String], defaults: TouchConfig = TouchConfig()) -> Outcome {
        var config = defaults
        var iterator = arguments.makeIterator()

        func nextDouble() -> Double? {
            guard let raw = iterator.next() else { return nil }
            return Double(raw)
        }

        while let arg = iterator.next() {
            switch arg {
            case "--help", "-h":       return .help
            case "--list":             return .listDisplays
            case "--reset-calibration": return .resetCalibration

            case "--display":
                guard let raw = iterator.next(), let idx = Int(raw) else {
                    return .error("--display requires an integer")
                }
                config.displayIndex = idx

            case "--mode":
                guard let raw = iterator.next() else {
                    return .error("--mode requires a value")
                }
                guard let mode = TouchMode(rawValue: raw) else {
                    let known = TouchMode.allCases.map(\.rawValue).joined(separator: ", ")
                    return .error("Unknown mode '\(raw)' — expected one of: \(known)")
                }
                config.mode = mode

            // Gesture tuning. Durations are given in milliseconds because that
            // is how the spec talks about them (§8: longPressDelay = 400 ms)
            // and how anyone tuning them thinks; they are stored in seconds.
            case "--scroll-threshold":
                guard let v = nextDouble(), v >= 0 else {
                    return .error("--scroll-threshold requires a non-negative number of pixels")
                }
                config.gestures.scrollThreshold = v

            case "--scroll-sensitivity":
                guard let v = nextDouble(), v > 0 else {
                    return .error("--scroll-sensitivity requires a positive number")
                }
                config.gestures.scrollSensitivity = v

            case "--hide-cursor":
                guard let raw = iterator.next() else {
                    return .error("--hide-cursor requires a value")
                }
                guard let policy = CursorHiding(rawValue: raw) else {
                    let known = CursorHiding.allCases.map(\.rawValue).joined(separator: ", ")
                    return .error("Unknown cursor hiding mode '\(raw)' — expected one of: \(known)")
                }
                config.gestures.cursorHiding = policy

            case "--restore-cursor":    config.gestures.restoreCursor = true
            case "--no-restore-cursor": config.gestures.restoreCursor = false

            case "--natural-scroll":    config.gestures.naturalScroll = true
            case "--no-natural-scroll": config.gestures.naturalScroll = false

            case "--long-press":
                guard let v = nextDouble(), v >= 0 else {
                    return .error("--long-press requires a non-negative number of milliseconds")
                }
                config.gestures.longPressDelay = v / 1000

            case "--drag-threshold":
                guard let v = nextDouble(), v >= 0 else {
                    return .error("--drag-threshold requires a non-negative number of pixels")
                }
                config.gestures.dragThreshold = v

            case "--invert-x":      config.invertX = true
            case "--invert-y":      config.invertY = true
            case "--debug":         config.debugMode = true
            case "--auto-calibrate": config.autoCalibrate = true
            case "--no-accessibility-prompt": config.promptForAccessibility = false

            case "--x-min": guard let v = nextDouble() else { return .error("--x-min requires a number") }; config.manualXMin = v
            case "--x-max": guard let v = nextDouble() else { return .error("--x-max requires a number") }; config.manualXMax = v
            case "--y-min": guard let v = nextDouble() else { return .error("--y-min requires a number") }; config.manualYMin = v
            case "--y-max": guard let v = nextDouble() else { return .error("--y-max requires a number") }; config.manualYMax = v

            default:
                return .error("Unknown option: \(arg)")
            }
        }

        return .run(config)
    }

    static let usageText = """

    m14ttouch — touchscreen driver for the Lenovo ThinkVision M14t on macOS

    USAGE:
      m14ttouch [OPTIONS]

    OPTIONS:
      --mode MODE          Touch behaviour (default: mouse)
                             mouse       finger drags the pointer
                             touchscreen tap to click, swipe to scroll,
                                         long press to drag
      --display N          Display index the M14t is mapped to (default: 1)
      --auto-calibrate     Learn the touch range as you touch all four corners,
                           then save it for future runs
      --invert-x           Mirror the horizontal axis
      --invert-y           Mirror the vertical axis
      --x-min N            Manual raw X minimum (overrides saved calibration)
      --x-max N            Manual raw X maximum
      --y-min N            Manual raw Y minimum
      --y-max N            Manual raw Y maximum
      --debug              Print every HID event and resulting action

    GESTURE TUNING (touchscreen mode):
      --scroll-threshold N Movement that commits to scrolling, in pixels, and
                           so also the furthest a tap may wander (default: 10)
      --scroll-sensitivity N
                           Multiplier for scroll deltas (default: 1.0)
      --natural-scroll     Content follows the finger (default)
      --no-natural-scroll  Invert the scroll direction
      --long-press MS      Hold before a contact becomes a drag (default: 400)
      --hide-cursor MODE   When to hide the pointer (default: never)
                             never      keep it visible
                             scrolling  hide once a swipe becomes a scroll
                             touching   hide whenever a finger is down
                           Needs a private API, and only holds while the pointer
                           is still — a tap and a drag move it by design, so
                           both make it visible again whichever mode is chosen
      --restore-cursor     Put the pointer back where it was when a gesture ends
                           (default)
      --no-restore-cursor  Leave the pointer where the gesture took it

    GESTURE TUNING (mouse mode):
      --drag-threshold N   Jitter filter before a press becomes a drag
                           (default: 1.5 pixels)
      --no-accessibility-prompt
               Do not show the Accessibility prompt; useful for LaunchAgents
      --list               List connected displays and exit
      --reset-calibration  Delete saved calibration and exit
      --help, -h           Show this help and exit

    FIRST RUN:
      m14ttouch --list                       # find your M14t's display index
      m14ttouch --display 1 --auto-calibrate  # calibrate by touching 4 corners

    EVERYDAY:
      m14ttouch --display 1                   # uses saved calibration

    """
}
