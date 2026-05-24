import IOKit.hid
import CoreGraphics
import Foundation

/// Bridges the M14t's USB HID touch interface to the macOS cursor.
///
/// Responsibilities are deliberately narrow: open the HID device, translate the
/// raw touch stream into screen coordinates (via `CoordinateMapper`), and emit
/// mouse events (via `MouseEmitter`). Calibration math and event posting live in
/// their own types, so this file is purely about *orchestration* and the touch
/// state machine.
///
/// ## Touch model
/// A single contact maps directly to the left mouse button:
/// - finger down  → `leftMouseDown`
/// - finger moves → `leftMouseDragged` (only past the jitter threshold)
/// - finger up    → `leftMouseUp`
///
/// A down-then-up with no movement is therefore a normal click; a down-move-up
/// is a drag. No multi-finger gestures — this is intentionally the simple,
/// rock-solid case.
final class HIDTouchDriver {

    private var config: TouchConfig
    private let emitter = MouseEmitter()

    // IOKit
    private var manager: IOHIDManager?

    // Coordinate state
    private var calibration: CalibrationData
    private var mapper: CoordinateMapper

    // Auto-calibration: the tightest range observed so far
    private var observed = ObservedRange()

    // Current touch sample and contact state
    private var currentRawX: Double = 0
    private var currentRawY: Double = 0
    private var isTouching = false
    private var lastScreenPoint: CGPoint = .zero

    init(config: TouchConfig) {
        self.config = config

        // Provisional calibration; refined once the device is connected.
        let initial = CalibrationData.identity
        self.calibration = initial

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

        resolveCalibration(for: device)
    }

    private func deviceRemoved() {
        log("🔌 Touch device disconnected")
        // Release any held button so the cursor doesn't get stuck pressed.
        if isTouching {
            emitter.post(.leftMouseUp, at: lastScreenPoint)
            isTouching = false
        }
    }

    // MARK: - Calibration Resolution
    //
    // Precedence: manual flags > saved file > HID descriptor.

    private func resolveCalibration(for device: IOHIDDevice) {
        var resolved = readDescriptorRange(from: device)

        if let saved = CalibrationStore.load(), !config.hasManualCalibration, !config.autoCalibrate {
            resolved = saved
            observed.seed(with: saved)
            log("💾 Loaded calibration: \(describe(resolved))")
        }

        // Manual overrides take ultimate priority.
        if let v = config.manualXMin { resolved.xMin = v }
        if let v = config.manualXMax { resolved.xMax = v }
        if let v = config.manualYMin { resolved.yMin = v }
        if let v = config.manualYMax { resolved.yMax = v }
        if config.hasManualCalibration {
            log("📐 Manual calibration: \(describe(resolved))")
        }

        calibration = resolved
        mapper.calibration = resolved

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
            emitDragIfMoved()

        case (HID.Page.genericDesktop.rawValue, HID.GenericDesktop.y.rawValue):
            currentRawY = Double(intVal)
            recordForAutoCalibration(y: Double(intVal))
            emitDragIfMoved()

        case (HID.Page.digitizer.rawValue, HID.Digitizer.tipSwitch.rawValue):
            updateContact(touching: intVal != 0)

        default:
            break
        }
    }

    /// Finger made or broke contact with the surface.
    private func updateContact(touching: Bool) {
        if touching, !isTouching {
            isTouching = true
            lastScreenPoint = mapper.map(rawX: currentRawX, rawY: currentRawY)
            emitter.post(.leftMouseDown, at: lastScreenPoint)
            log("☝️  DOWN  → (\(Int(lastScreenPoint.x)),\(Int(lastScreenPoint.y)))")
        } else if !touching, isTouching {
            isTouching = false
            emitter.post(.leftMouseUp, at: lastScreenPoint)
            log("☝️  UP    → (\(Int(lastScreenPoint.x)),\(Int(lastScreenPoint.y)))")
        }
    }

    /// While a finger is down, translate position changes into drag events.
    private func emitDragIfMoved() {
        guard isTouching else { return }
        let point = mapper.map(rawX: currentRawX, rawY: currentRawY)
        let moved = abs(point.x - lastScreenPoint.x) > config.dragThreshold
                 || abs(point.y - lastScreenPoint.y) > config.dragThreshold
        guard moved else { return }

        emitter.post(.leftMouseDragged, at: point)
        lastScreenPoint = point
        log("☝️  DRAG  → (\(Int(point.x)),\(Int(point.y)))")
    }

    // MARK: - Auto-calibration

    private func recordForAutoCalibration(x: Double? = nil, y: Double? = nil) {
        guard config.autoCalibrate else { return }
        if observed.update(x: x, y: y), let snapshot = observed.snapshot() {
            calibration = snapshot
            mapper.calibration = snapshot
            CalibrationStore.save(snapshot)
            log("🎯 Auto-cal: \(describe(snapshot))")
        }
    }

    // MARK: - Helpers

    private func describe(_ c: CalibrationData) -> String {
        "X \(Int(c.xMin))–\(Int(c.xMax))  Y \(Int(c.yMin))–\(Int(c.yMax))"
    }

    private func hex(_ value: Int) -> String { String(format: "%04X", value) }

    private func log(_ message: String) { print(message) }
}

// MARK: - Observed Range

/// Tracks the tightest min/max coordinates seen during auto-calibration.
struct ObservedRange {
    private var minX = Double.infinity
    private var maxX = -Double.infinity
    private var minY = Double.infinity
    private var maxY = -Double.infinity

    /// Seed from a previously-saved calibration so auto-cal refines rather than
    /// starting from nothing.
    mutating func seed(with c: CalibrationData) {
        minX = c.xMin; maxX = c.xMax
        minY = c.yMin; maxY = c.yMax
    }

    /// Feed a new sample. Returns `true` if the range expanded.
    mutating func update(x: Double?, y: Double?) -> Bool {
        var changed = false
        if let x, x >= 0 {
            if x < minX { minX = x; changed = true }
            if x > maxX { maxX = x; changed = true }
        }
        if let y, y >= 0 {
            if y < minY { minY = y; changed = true }
            if y > maxY { maxY = y; changed = true }
        }
        return changed
    }

    /// A valid calibration, or `nil` if the range hasn't formed yet.
    func snapshot() -> CalibrationData? {
        guard minX < maxX, minY < maxY else { return nil }
        return CalibrationData(xMin: minX, xMax: maxX, yMin: minY, yMax: maxY)
    }
}
