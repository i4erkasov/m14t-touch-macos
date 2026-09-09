import IOKit.hid
import CoreGraphics
import Foundation

/// Bridges the M14t's USB HID touch interface to the gesture pipeline.
///
/// Responsibilities are deliberately narrow: open the HID device, turn the raw
/// touch stream into `TouchFrame`s (mapped through `CoordinateMapper`), and hand
/// them to a `TouchEngine`. What a finger *means* is decided by the engine's
/// recognizer, and how macOS is told is decided by its emitter — neither is this
/// file's business (spec §32).
///
/// ## Frame cadence
/// One frame is produced per HID value, not per report. The device reports X, Y
/// and TipSwitch as separate values, so a frame can carry a new X against the
/// previous Y. That is exactly what the pre-refactor driver did, and it is
/// preserved so this refactor cannot be the cause of a behaviour change;
/// report-level batching is a v0.2 decision (docs/v0.1-refactor-plan.md).
final class HIDTouchDriver {

    private var config: TouchConfig
    private let engine: TouchEngine

    // IOKit
    private var manager: IOHIDManager?

    // Coordinate state
    private var mapper: CoordinateMapper
    private let calibrationController: CalibrationController

    // Latest raw sample and contact state as reported by the device. This is
    // hardware state, not gesture state — whether a held finger is a drag or a
    // scroll is the recognizer's call.
    private var currentRawX: Double = 0
    private var currentRawY: Double = 0
    private var isTipSwitchDown = false

    /// - Parameter engine: the gesture pipeline to feed. Injected rather than
    ///   built here so the driver has no opinion on which mode is active — that
    ///   is chosen once, in `main.swift`, from `--mode`.
    init(config: TouchConfig, engine: TouchEngine) {
        self.config = config
        self.engine = engine
        self.calibrationController = CalibrationController(config: config)

        // Provisional calibration; refined once the device is connected.
        let initial = CalibrationData.identity

        let (bounds, _) = DisplayResolver.bounds(forIndex: config.displayIndex)
        self.mapper = CoordinateMapper(
            calibration: initial,
            displayBounds: bounds,
            invertX: config.invertX,
            invertY: config.invertY
        )
    }

    // MARK: - Lifecycle

    /// Open the HID manager and begin listening. Blocks via the caller's run loop.
    func start() {
        let (bounds, resolvedIndex) = DisplayResolver.bounds(forIndex: config.displayIndex)
        mapper.displayBounds = bounds
        if resolvedIndex != config.displayIndex {
            log("⚠️  Display index \(config.displayIndex) out of range — using [\(resolvedIndex)]")
        }
        log("🖥️  Target display [\(resolvedIndex)]: \(Int(bounds.width))×\(Int(bounds.height)) @ (\(Int(bounds.minX)),\(Int(bounds.minY)))")

        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        self.manager = manager

        IOHIDManagerSetDeviceMatching(manager, [
            kIOHIDDeviceUsagePageKey: HID.Page.digitizer.rawValue,
            kIOHIDDeviceUsageKey:     HID.Digitizer.touchScreen.rawValue
        ] as CFDictionary)

        let context = Unmanaged.passUnretained(self).toOpaque()

        IOHIDManagerRegisterDeviceMatchingCallback(manager, { ctx, _, _, device in
            HIDTouchDriver.from(ctx).deviceConnected(device)
        }, context)

        IOHIDManagerRegisterDeviceRemovalCallback(manager, { ctx, _, _, _ in
            HIDTouchDriver.from(ctx).deviceRemoved()
        }, context)

        IOHIDManagerRegisterInputValueCallback(manager, { ctx, _, _, value in
            HIDTouchDriver.from(ctx).handle(value)
        }, context)

        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)

        let result = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        if result == kIOReturnSuccess {
            log("✅ Listening for touch device…")
        } else {
            log("❌ Could not open HID manager (code \(result))")
            log("   Grant 'Input Monitoring' in System Settings → Privacy & Security, then retry.")
        }
    }

    /// Recover `self` from the opaque pointer passed to C callbacks.
    private static func from(_ ctx: UnsafeMutableRawPointer?) -> HIDTouchDriver {
        Unmanaged<HIDTouchDriver>.fromOpaque(ctx!).takeUnretainedValue()
    }

    // MARK: - Device Callbacks

    private func deviceConnected(_ device: IOHIDDevice) {
        let name    = IOHIDDeviceGetProperty(device, kIOHIDProductKey   as CFString) as? String ?? "Unknown"
        let vendor  = IOHIDDeviceGetProperty(device, kIOHIDVendorIDKey  as CFString) as? Int ?? 0
        let product = IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? Int ?? 0
        log("🔌 Connected: \"\(name)\"  VID 0x\(hex(vendor))  PID 0x\(hex(product))")

        applyCalibration(for: device)
    }

    private func deviceRemoved() {
        log("🔌 Touch device disconnected")
        // Release any held button so the cursor doesn't get stuck pressed.
        isTipSwitchDown = false
        logActions(engine.reset())
    }

    // MARK: - Calibration

    /// Hand the descriptor range and any saved file to the controller, then put
    /// its verdict into the mapper.
    private func applyCalibration(for device: IOHIDDevice) {
        let outcome = calibrationController.resolve(
            descriptorRange: readDescriptorRange(from: device),
            saved: CalibrationStore.shared.load()
        )

        switch outcome.source {
        case .saved:      log("💾 Loaded calibration: \(describe(outcome.calibration))")
        case .manual:     log("📐 Manual calibration: \(describe(outcome.calibration))")
        case .descriptor: break
        }

        mapper.calibration = outcome.calibration

        if config.autoCalibrate {
            log("🎯 Auto-calibrate ON — learning fresh bounds; touch all four corners of the screen")
        }
    }

    /// Read the logical X/Y range the device advertises in its HID descriptor.
    private func readDescriptorRange(from device: IOHIDDevice) -> CalibrationData {
        var range = CalibrationData.identity
        guard let elements = IOHIDDeviceCopyMatchingElements(
            device, nil, IOOptionBits(kIOHIDOptionsTypeNone)
        ) as? [IOHIDElement] else { return range }

        for element in elements where IOHIDElementGetUsagePage(element) == HID.Page.genericDesktop.rawValue {
            switch IOHIDElementGetUsage(element) {
            case HID.GenericDesktop.x.rawValue:
                range.xMin = Double(IOHIDElementGetLogicalMin(element))
                range.xMax = Double(IOHIDElementGetLogicalMax(element))
            case HID.GenericDesktop.y.rawValue:
                range.yMin = Double(IOHIDElementGetLogicalMin(element))
                range.yMax = Double(IOHIDElementGetLogicalMax(element))
            default:
                break
            }
        }
        log("📐 Descriptor range: \(describe(range))")
        return range
    }

    // MARK: - Input Handling

    private func handle(_ value: IOHIDValue) {
        let element = IOHIDValueGetElement(value)
        let page    = IOHIDElementGetUsagePage(element)
        let usage   = IOHIDElementGetUsage(element)
        let intVal  = IOHIDValueGetIntegerValue(value)

        if config.debugMode {
            log("HID  page=0x\(hex(Int(page)))  usage=0x\(hex(Int(usage)))  val=\(intVal)")
        }

        switch (page, usage) {

        case (HID.Page.genericDesktop.rawValue, HID.GenericDesktop.x.rawValue):
            currentRawX = Double(intVal)
            recordForAutoCalibration(x: Double(intVal))
            emitFrame()

        case (HID.Page.genericDesktop.rawValue, HID.GenericDesktop.y.rawValue):
            currentRawY = Double(intVal)
            recordForAutoCalibration(y: Double(intVal))
            emitFrame()

        case (HID.Page.digitizer.rawValue, HID.Digitizer.tipSwitch.rawValue):
            isTipSwitchDown = intVal != 0
            emitFrame()

        default:
            break
        }
    }

    /// Publish the current sample as a frame.
    ///
    /// Called after every X, Y and TipSwitch value, so the mapping always uses
    /// the calibration in force at that moment — `recordForAutoCalibration` runs
    /// first, and a sample that widens the range is mapped with the widened one,
    /// as before.
    private func emitFrame() {
        let contact = TouchPoint(
            id: TouchPoint.primary,
            position: mapper.map(rawX: currentRawX, rawY: currentRawY),
            rawPosition: CGPoint(x: currentRawX, y: currentRawY),
            isTouching: isTipSwitchDown,
            pressure: nil,
            timestamp: ProcessInfo.processInfo.systemUptime
        )
        logActions(engine.process(TouchFrame(contact: contact)))
    }

    // MARK: - Auto-calibration

    private func recordForAutoCalibration(x: Double? = nil, y: Double? = nil) {
        guard let widened = calibrationController.record(x: x, y: y) else { return }
        mapper.calibration = widened
        log("🎯 Auto-cal: \(describe(widened))")
    }

    // MARK: - Helpers

    /// Echo emitted actions, preserving the console output of the original
    /// driver, which printed each press, drag and release as it posted it.
    private func logActions(_ actions: [InputAction]) {
        for action in actions {
            switch action {
            case .dragBegin(let p): log("☝️  DOWN  → (\(Int(p.x)),\(Int(p.y)))")
            case .dragMove(let p):  log("☝️  DRAG  → (\(Int(p.x)),\(Int(p.y)))")
            case .dragEnd(let p):   log("☝️  UP    → (\(Int(p.x)),\(Int(p.y)))")
            default:                log("☝️  \(action)")
            }
        }
    }

    private func describe(_ c: CalibrationData) -> String {
        "X \(Int(c.xMin))–\(Int(c.xMax))  Y \(Int(c.yMin))–\(Int(c.yMax))"
    }

    private func hex(_ value: Int) -> String { String(format: "%04X", value) }

    private func log(_ message: String) { print(message) }
}
