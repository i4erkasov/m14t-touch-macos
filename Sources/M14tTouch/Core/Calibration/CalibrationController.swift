import Foundation

/// Decides which calibration is in force, and widens it during auto-calibration.
///
/// Pulled out of `HIDTouchDriver` so that the precedence rule — the thing most
/// likely to send touches to the wrong place — can be tested without a device.
/// Reading the HID descriptor stays in the driver, because that genuinely needs
/// IOKit; everything decided *about* the resulting numbers happens here.
final class CalibrationController {

    /// Where the calibration in force came from. The driver uses this to say so
    /// on the console.
    enum Source {
        case descriptor
        case saved
        case manual
    }

    struct Outcome {
        let calibration: CalibrationData
        let source: Source
    }

    private let config: TouchConfig
    private let persist: (CalibrationData) -> Void
    private var observed = ObservedRange()

    /// The calibration currently in force.
    private(set) var calibration: CalibrationData = .identity

    /// - Parameter persist: where a widened range is written. Injected so tests
    ///   do not write to the real `~/.m14ttouch.json`.
    init(
        config: TouchConfig,
        persist: @escaping (CalibrationData) -> Void = { CalibrationStore.shared.save($0) }
    ) {
        self.config = config
        self.persist = persist
    }

    /// Settle on a calibration for a freshly connected device.
    ///
    /// Precedence is **manual flags > saved file > HID descriptor**. A saved
    /// calibration is ignored while auto-calibrating, so `--auto-calibrate`
    /// always learns fresh bounds rather than refining yesterday's; it is also
    /// ignored when manual bounds are given, since those would overwrite it
    /// anyway.
    ///
    /// - Parameter saved: the persisted calibration, passed in rather than read
    ///   here so the precedence rule can be tested without touching the disk.
    @discardableResult
    func resolve(descriptorRange: CalibrationData, saved: CalibrationData?) -> Outcome {
        var resolved = descriptorRange
        var source = Source.descriptor

        if let saved, !config.hasManualCalibration, !config.autoCalibrate {
            resolved = saved
            // Seed the observed range so auto-calibration refines rather than
            // starting from nothing.
            observed.seed(with: saved)
            source = .saved
        }

        if let v = config.manualXMin { resolved.xMin = v }
        if let v = config.manualXMax { resolved.xMax = v }
        if let v = config.manualYMin { resolved.yMin = v }
        if let v = config.manualYMax { resolved.yMax = v }
        if config.hasManualCalibration { source = .manual }

        calibration = resolved
        return Outcome(calibration: resolved, source: source)
    }

    /// Feed a raw sample while auto-calibrating.
    ///
    /// - Returns: the widened calibration when this sample grew the range,
    ///   `nil` when it changed nothing or auto-calibration is off. Returning the
    ///   new value rather than mutating a shared mapper keeps the caller in
    ///   charge of when the change takes effect.
    @discardableResult
    func record(x: Double? = nil, y: Double? = nil) -> CalibrationData? {
        guard config.autoCalibrate else { return nil }
        guard observed.update(x: x, y: y), let snapshot = observed.snapshot() else { return nil }

        calibration = snapshot
        persist(snapshot)
        return snapshot
    }
}
