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
/// One frame per report, so X and Y in a frame always belong together.
///
/// IOKit delivers values one at a time with no end-of-report marker, but this
/// panel opens every report with `ScanTime`, so its arrival means the previous
/// report is complete. Coordinates therefore accumulate and are published when
/// the next report starts — about 10 ms later, one tick at the panel's ~100 Hz.
///
/// Contact changes do not wait. A release arrives at the end of a report and the
/// next `ScanTime` only comes with the *next touch*, which on real traces was
/// 1.6 seconds later; batching the release would delay it by that long.
///
/// A device that reports no `ScanTime` falls back to a frame per value, which is
/// what v0.1 did throughout.
///
/// ## Threading
/// Everything after `start()` happens on one serial queue: IOKit is told to
/// deliver callbacks there, so the driver's state, the recognizer's state and
/// event emission are all confined to it without a lock in sight (spec §25).
///
/// The main thread is left free. That mattered little for a CLI, where it only
/// ran an idle run loop, and matters a great deal once SwiftUI shares it —
/// frames arrive around a hundred times a second and must not compete with
/// drawing (spec §24).
///
/// `start()` and `stop()` are the only members meant to be called from
/// elsewhere, and both hop onto the queue to touch anything.
final class HIDTouchDriver {

    private var config: TouchConfig
    private let engine: TouchEngine

    // IOKit
    private var manager: IOHIDManager?

    /// The queue every callback and all mutable state lives on.
    ///
    /// `userInteractive` because this is the latency path: a frame late is a
    /// cursor that lags the finger.
    private let queue = DispatchQueue(label: "com.m14ttouch.touch", qos: .userInteractive)

    // Coordinate state
    private var mapper: CoordinateMapper
    private let calibrationController: CalibrationController

    // Latest raw sample and contact state as reported by the device. This is
    // hardware state, not gesture state — whether a held finger is a drag or a
    // scroll is the recognizer's call.
    private var currentRawX: Double = 0
    private var currentRawY: Double = 0
    private var isTipSwitchDown = false

    /// The device calibration was taken from, once one has actually sent input.
    private var calibratedDevice: IOHIDDevice?

    /// Whether this panel marks report boundaries with `ScanTime`. Until one
    /// arrives the driver cannot batch, so it publishes per value instead.
    private var reportsScanTime = false

    /// - Parameter engine: the gesture pipeline to feed. Injected rather than
    ///   built here so the driver has no opinion on which mode is active — that
    ///   is chosen once, in `main.swift`, from `--mode`.
    init(config: TouchConfig, engine: TouchEngine) {
        self.config = config
        self.engine = engine
        self.calibrationController = CalibrationController(config: config)

        // Provisional calibration; refined once the device is connected.
        let initial = CalibrationData.identity

        self.mapper = CoordinateMapper(
            calibration: initial,
            displayBounds: DisplayResolver.resolve(config.display)?.display.bounds ?? .zero,
            invertX: config.invertX,
            invertY: config.invertY
        )
    }

    // MARK: - Lifecycle

    /// Open the HID manager and begin listening.
    ///
    /// Returns immediately; delivery happens on the driver's own queue, and the
    /// caller's run loop is only needed to keep the process alive.
    func start() {
        guard let resolution = DisplayResolver.resolve(config.display) else {
            log("❌ No displays found — nothing to map touches onto.")
            return
        }
        let display = resolution.display
        mapper.displayBounds = display.bounds

        switch resolution.match {
        case .identity:    break
        case .index:       break
        case .automatic:   log("🖥️  No display chosen — using the first external one")
        case .unavailable: log("⚠️  The chosen display is not connected — using [\(display.index)] instead")
        }
        log("🖥️  Target display [\(display.index)]: \(Int(display.bounds.width))×\(Int(display.bounds.height)) @ (\(Int(display.bounds.minX)),\(Int(display.bounds.minY)))")

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

        let result = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        guard result == kIOReturnSuccess else {
            log("❌ Could not open HID manager (code \(result))")
            log("   Grant 'Input Monitoring' in System Settings → Privacy & Security, then retry.")
            self.manager = nil
            return
        }

        // Delivery on a queue rather than a run loop: the modern IOKit path, and
        // the one that lets the pipeline own a thread instead of borrowing the
        // main one. Must be set before activating.
        IOHIDManagerSetDispatchQueue(manager, queue)
        IOHIDManagerSetCancelHandler(manager) { [weak self] in
            // The manager must stay alive until this runs, so the reference is
            // dropped here rather than at the call to cancel.
            self?.manager = nil
            self?.log("🔌 HID manager closed")
        }
        IOHIDManagerActivate(manager)
        log("✅ Listening for touch device…")
    }

    /// Release any contact in progress and close the device.
    ///
    /// Quitting while a finger is down would otherwise leave the left button
    /// pressed: the release is normally emitted when the finger lifts or the
    /// device disappears, and process termination is neither.
    func stop() {
        // Synchronous so the release is posted before the caller exits the
        // process. Safe from the main thread, which is the only caller; calling
        // it from the queue itself would deadlock, and nothing does.
        queue.sync {
            isTipSwitchDown = false
            logActions(engine.reset())

            guard let manager else { return }
            // Cancel rather than close: the queue-based API requires it, and it
            // is what stops further callbacks arriving. The reference is
            // released in the cancel handler, not here — the object has to
            // outlive the cancellation.
            IOHIDManagerCancel(manager)
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
    }

    private func deviceRemoved() {
        log("🔌 Touch device disconnected")
        // Release any held button so the cursor doesn't get stuck pressed.
        isTipSwitchDown = false
        logActions(engine.reset())
        // Re-derive calibration from whichever device speaks up next.
        calibratedDevice = nil
    }

    // MARK: - Calibration

    /// Take calibration from the first device that actually sends input.
    ///
    /// The M14t presents *two* interfaces matching the driver's filter, and
    /// resolving on connect meant the second silently overwrote the first — with
    /// a descriptor range the panel never reports, putting touches in a fraction
    /// of the screen. Only one of the two ever delivers values, so waiting for
    /// input identifies the right one without having to guess from the
    /// descriptor.
    private func calibrateIfNeeded(from device: IOHIDDevice) {
        guard calibratedDevice == nil else { return }
        calibratedDevice = device
        applyCalibration(for: device)
    }

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
    ///
    /// IOKit access only — which of the several declared ranges to believe is
    /// `DescriptorRange`'s decision.
    private func readDescriptorRange(from device: IOHIDDevice) -> CalibrationData {
        guard let elements = IOHIDDeviceCopyMatchingElements(
            device, nil, IOOptionBits(kIOHIDOptionsTypeNone)
        ) as? [IOHIDElement] else { return .identity }

        let range = DescriptorRange.range(from: elements.map {
            DescriptorRange.Element(
                usagePage: IOHIDElementGetUsagePage($0),
                usage: IOHIDElementGetUsage($0),
                logicalMin: IOHIDElementGetLogicalMin($0),
                logicalMax: IOHIDElementGetLogicalMax($0)
            )
        })
        log("📐 Descriptor range: \(describe(range))")
        return range
    }

    // MARK: - Input Handling

    private func handle(_ value: IOHIDValue) {
        let element = IOHIDValueGetElement(value)
        calibrateIfNeeded(from: IOHIDElementGetDevice(element))

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
            emitFrameIfUnbatched()

        case (HID.Page.genericDesktop.rawValue, HID.GenericDesktop.y.rawValue):
            currentRawY = Double(intVal)
            recordForAutoCalibration(y: Double(intVal))
            emitFrameIfUnbatched()

        case (HID.Page.digitizer.rawValue, HID.Digitizer.tipSwitch.rawValue):
            // Contact changes are urgent — see the note on frame cadence.
            isTipSwitchDown = intVal != 0
            emitFrame()

        case (HID.Page.digitizer.rawValue, HID.Digitizer.scanTime.rawValue):
            // Opens a report, so the previous one is now complete. Published
            // even when nothing moved: a held finger sends nothing else, and
            // gesture recognition needs the tick to notice time passing.
            reportsScanTime = true
            emitFrame()

        default:
            break
        }
    }

    /// Publish a coordinate change only on panels that do not mark report
    /// boundaries. Where they do, the value waits for the boundary so X and Y
    /// are published as a matched pair.
    private func emitFrameIfUnbatched() {
        guard !reportsScanTime else { return }
        emitFrame()
    }

    /// Publish the current sample as a frame.
    ///
    /// The mapping always uses the calibration in force at that moment —
    /// `recordForAutoCalibration` runs first, so a sample that widens the range
    /// is mapped with the widened one.
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
