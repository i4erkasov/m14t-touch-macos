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

    /// Called on the **main queue** whenever the connected device changes, so a
    /// menu can show it without reaching into the driver's queue.
    var onStatusChange: ((DriverStatus) -> Void)?

    /// Whether Input Monitoring was missing when the manager was opened.
    ///
    /// Denied permission does not always refuse the open: the device is found
    /// and then simply never sends anything, which looks like working hardware
    /// that does nothing. Remembered here so a connection can say so.
    private var inputMonitoringMissing = false

    private var status = DriverStatus() {
        didSet {
            guard status != oldValue else { return }
            let published = status
            DispatchQueue.main.async { [weak self] in self?.onStatusChange?(published) }
        }
    }

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

    // MARK: Pen
    //
    // The pen is a separate pipeline throughout (pen spec §4): its own mapper,
    // because it counts in a different coordinate space from the finger; its own
    // recognizer, because a pen states what it is doing rather than needing to be
    // interpreted; and its own backend.
    private var penMapper: CoordinateMapper
    private var pen = PenRecognizer()
    private let penBackend = PenMouseBackend()
    private let penPressure = PressureScale.m14t

    private var penRawX: Double = 0
    private var penRawY: Double = 0
    private var penInRange = false
    private var penTipDown = false
    private var penEraserDown = false
    private var penButtons: PenButtons = []
    private var penPressureRaw: Double = 0
    private var penBattery: Double?

    /// A finger contact that began while the pen was near, and is therefore
    /// being ignored for as long as it lasts (pen spec §15).
    ///
    /// Held until the finger lifts rather than cleared when the pen leaves: a
    /// touch that was ignored must not spring to life halfway through, which
    /// would be worse than ignoring it completely.
    private var suppressingFingerContact = false

    /// Which collection an element belongs to, worked out once per element.
    ///
    /// Walking the parent chain on every value would mean doing it a hundred
    /// times a second for the same handful of elements; the cookie is stable for
    /// the life of the device.
    private var sourceByCookie: [IOHIDElementCookie: InputSource] = [:]

    /// While set, frames go here **instead of** the gesture engine.
    ///
    /// A diversion rather than a fork. Calibration needs to see touches without
    /// them turning into clicks — a finger on a target would otherwise press the
    /// overlay showing it — and letting the engine see them as well would leave
    /// it holding a gesture whose end it never gets.
    ///
    /// Delivered on the **main queue**, because the only thing that wants frames
    /// this way is an interface.
    private var frameObserver: ((TouchFrame) -> Void)?

    /// - Parameter engine: the gesture pipeline to feed. Injected rather than
    ///   built here so the driver has no opinion on which mode is active — that
    ///   is chosen once, in `main.swift`, from `--mode`.
    init(config: TouchConfig, engine: TouchEngine) {
        self.config = config
        self.engine = engine
        self.calibrationController = CalibrationController(config: config)
        self.penBackend.apply(config.pen)

        // Provisional calibration; refined once the device is connected.
        let initial = CalibrationData.identity

        let bounds = DisplayResolver.resolve(config.display)?.display.bounds ?? .zero
        self.mapper = CoordinateMapper(
            calibration: initial,
            displayBounds: bounds,
            invertX: config.invertX,
            invertY: config.invertY
        )
        // The pen's own space, which is not the finger's: 0…30931 × 0…17399
        // against 0…12372 × 0…6960 (`M14t_PEN_CAPABILITIES.md`). Using one
        // calibration for both would put the pen at a third of the screen.
        self.penMapper = CoordinateMapper(
            calibration: CalibrationData(xMin: 0, xMax: 30931, yMin: 0, yMax: 17399),
            displayBounds: bounds,
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
            status = DriverStatus(failure: "No displays found")
            return
        }
        let display = resolution.display
        mapper.displayBounds = display.bounds
        penMapper.displayBounds = display.bounds
        // Calibration belongs to a panel, so it is looked up and saved against
        // the display we are actually aiming at.
        calibrationController.displayIdentity = display.identity

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

        // Seizing stops macOS handling the device itself. It has to be
        // exclusive or nothing: the system moves the pointer relative to where
        // it already is, so an absolute position from us would fight it rather
        // than replace it. It takes the finger collection too, which is fine —
        // we handle that anyway, and macOS ignores the touchscreen.
        inputMonitoringMissing =
            IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) != kIOHIDAccessTypeGranted
        if inputMonitoringMissing {
            log("⚠️  Input Monitoring is not granted — the panel may be found but stay silent.")
        }

        let options = config.penEnabled ? kIOHIDOptionsTypeSeizeDevice : kIOHIDOptionsTypeNone
        let result = IOHIDManagerOpen(manager, IOOptionBits(options))
        guard result == kIOReturnSuccess else {
            // Three different problems arrive here as three different codes, and
            // the answer to each is different too, so they are told apart rather
            // than reported as one "could not open".
            let reason: String
            switch result {
            case kIOReturnNotPermitted, kIOReturnNotPrivileged:
                reason = "Input Monitoring not granted"
            case kIOReturnExclusiveAccess:
                reason = "Another app is holding the panel"
            default:
                reason = String(format: "HID error 0x%08X", UInt32(bitPattern: result))
            }
            log("❌ Could not open HID manager: \(reason) (code \(result))")
            if config.penEnabled {
                log("   Taking the device exclusively was refused; try --no-pen.")
            }
            log("   Grant 'Input Monitoring' in System Settings → Privacy & Security, then retry.")
            status = DriverStatus(failure: reason)
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
        log(config.penEnabled
            ? "✅ Listening — device held exclusively, so the pen is ours"
            : "✅ Listening for touch device…")
    }

    /// Turn translation on or off, from any thread.
    ///
    /// Asynchronous on purpose: a menu click must not wait on the touch queue,
    /// which may be mid-frame.
    func setEnabled(_ enabled: Bool) {
        queue.async { [weak self] in self?.engine.setEnabled(enabled) }
    }

    /// Switch gesture model without restarting, from any thread.
    func setMode(_ mode: TouchMode) {
        queue.async { [weak self] in
            guard let self else { return }
            self.config.mode = mode
            self.engine.setRecognizer(mode.makeRecognizer(config: self.config))
            self.log("🎛️  Mode: \(mode.rawValue)")
        }
    }

    /// Divert frames away from the gesture engine, from any thread.
    ///
    /// Setting an observer abandons whatever gesture is in progress, so a finger
    /// that was down when calibration started does not leave a button held with
    /// nothing left to release it.
    ///
    /// - Parameter observer: called on the main queue for every frame, or `nil`
    ///   to hand frames back to the engine.
    func setFrameObserver(_ observer: ((TouchFrame) -> Void)?) {
        queue.async { [weak self] in
            guard let self else { return }
            if observer != nil, self.frameObserver == nil {
                self.logActions(self.engine.reset())
            }
            self.frameObserver = observer
        }
    }

    /// Take everything the user has chosen, from any thread.
    ///
    /// One entry point so the settings window does not have to know which knob
    /// lives on which side of the queue. Thresholds and toggles reach the
    /// recognizer by rebuilding it — they are read at construction, and a
    /// recognizer mid-gesture with new rules would be neither the old behaviour
    /// nor the new one.
    func apply(_ settings: AppSettings) {
        queue.async { [weak self] in
            guard let self else { return }
            self.config.mode = settings.mode
            self.config.gestures = settings.gestures
            self.config.pen = settings.pen
            self.penBackend.apply(settings.pen)
            self.config.invertX = settings.invertX
            self.config.invertY = settings.invertY
            self.config.display = settings.display

            self.mapper.invertX = settings.invertX
            self.mapper.invertY = settings.invertY
            if let resolved = DisplayResolver.resolve(settings.display) {
                self.mapper.displayBounds = resolved.display.bounds
            }

            self.engine.setRecognizer(settings.mode.makeRecognizer(config: self.config))
            self.engine.setEnabled(settings.enabled)
        }
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
            for action in pen.reset() { penBackend.handle(action) }

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
        status = DriverStatus(
            isConnected: true,
            deviceName: name,
            vendorID: vendor,
            productID: product,
            failure: inputMonitoringMissing ? "Input Monitoring not granted" : nil
        )
    }

    private func deviceRemoved() {
        log("🔌 Touch device disconnected")
        // Release any held button so the cursor doesn't get stuck pressed.
        isTipSwitchDown = false
        logActions(engine.reset())

        // The pen too: a stroke that never ends leaves a button pressed with no
        // pen left to lift it (pen spec §35).
        for action in pen.reset() { penBackend.handle(action) }
        penInRange = false
        penTipDown = false
        penEraserDown = false
        penButtons = []

        // Re-derive calibration from whichever device speaks up next.
        calibratedDevice = nil
        status = DriverStatus()
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
        let descriptorRange = readDescriptorRange(from: device)

        // The descriptor's proportions, not the saved calibration's: calibration
        // bounds are wherever a finger happened to reach, and are a percent or
        // two out. The descriptor states the surface.
        let width = descriptorRange.xMax - descriptorRange.xMin
        let height = descriptorRange.yMax - descriptorRange.yMin
        if width > 0, height > 0 { status.touchAspectRatio = width / height }

        let outcome = calibrationController.resolve(
            descriptorRange: descriptorRange,
            saved: CalibrationStore.shared.load(for: calibrationController.displayIdentity)
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

        // Pen and finger are two collections of one device, so which pipeline a
        // value belongs to is decided here and nowhere else (pen spec §4).
        switch source(of: element) {
        case .pen:
            handlePen(value, element: element)
            return
        case .other:
            return
        case .finger:
            break
        }

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
            let down = intVal != 0

            // Palm rejection, decided the moment the finger lands rather than
            // on every frame (pen spec §15). A hand resting on the panel to
            // write with is the case this exists for; the pen's proximity is
            // what tells it from a deliberate touch.
            //
            // The decision is made once and held for the life of the contact:
            // a touch that was ignored must not spring to life halfway through
            // because the pen moved away, which would be worse than ignoring it
            // outright.
            if down, !isTipSwitchDown {
                suppressingFingerContact = config.pen.palmRejection && penInRange
            } else if !down {
                suppressingFingerContact = false
            }

            // Contact changes are urgent — see the note on frame cadence.
            isTipSwitchDown = down
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

    // MARK: - Pen

    /// Which collection an element sits in, remembered per element.
    private func source(of element: IOHIDElement) -> InputSource {
        let cookie = IOHIDElementGetCookie(element)
        if let known = sourceByCookie[cookie] { return known }

        var collections: [(page: UInt32, usage: UInt32)] = []
        var node = IOHIDElementGetParent(element)
        while let current = node {
            collections.insert(
                (IOHIDElementGetUsagePage(current), IOHIDElementGetUsage(current)), at: 0
            )
            node = IOHIDElementGetParent(current)
        }

        let resolved = InputSource.from(collections: collections)
        sourceByCookie[cookie] = resolved
        return resolved
    }

    private func handlePen(_ value: IOHIDValue, element: IOHIDElement) {
        let page = IOHIDElementGetUsagePage(element)
        let usage = IOHIDElementGetUsage(element)
        let raw = Double(IOHIDValueGetIntegerValue(value))

        switch (page, usage) {
        case (HID.Page.genericDesktop.rawValue, HID.GenericDesktop.x.rawValue): penRawX = raw
        case (HID.Page.genericDesktop.rawValue, HID.GenericDesktop.y.rawValue): penRawY = raw
        case (HID.Page.digitizer.rawValue, HID.Digitizer.inRange.rawValue):     penInRange = raw != 0
        case (HID.Page.digitizer.rawValue, HID.Digitizer.tipSwitch.rawValue):   penTipDown = raw != 0
        case (HID.Page.digitizer.rawValue, HID.Digitizer.eraser.rawValue):      penEraserDown = raw != 0
        case (HID.Page.digitizer.rawValue, HID.Digitizer.tipPressure.rawValue): penPressureRaw = raw
        case (HID.Page.digitizer.rawValue, HID.Digitizer.batteryStrength.rawValue):
            penBattery = raw / 255
        case (HID.Page.digitizer.rawValue, HID.Digitizer.barrelSwitch.rawValue):
            penButtons = raw != 0 ? penButtons.union(.barrel) : penButtons.subtracting(.barrel)
        case (HID.Page.digitizer.rawValue, HID.Digitizer.invert.rawValue):
            penButtons = raw != 0 ? penButtons.union(.eraserMode) : penButtons.subtracting(.eraserMode)
        default:
            return                       // nothing else changes the pen's state
        }

        publishPenSample()
    }

    /// Publish the pen's current state.
    ///
    /// Per value rather than per report: unlike the finger's, the pen collection
    /// carries no ScanTime to mark a boundary with. The cost is a pointer move to
    /// an intermediate point when X and Y arrive separately, which is a fraction
    /// of a pixel and invisible; the alternative would be assuming an order the
    /// descriptor does not promise.
    private func publishPenSample() {
        // Contact comes from the switches, never from a pressure threshold: the
        // panel reports non-zero pressure at transitions while nothing is
        // touching (`M14t_PEN_CAPABILITIES.md`).
        let tool: PenTool? = penEraserDown ? .eraser : (penTipDown ? .tip : nil)
        let position = penMapper.map(rawX: penRawX, rawY: penRawY)

        let sample = PenSample(
            timestamp: ProcessInfo.processInfo.systemUptime,
            rawPosition: CGPoint(x: penRawX, y: penRawY),
            position: position,
            inProximity: penInRange,
            contact: tool,
            pressure: tool == nil ? nil : penPressure.normalize(penPressureRaw),
            buttons: penButtons,
            battery: penBattery
        )

        for action in pen.process(sample) {
            if config.debugMode {
                // Raw pressure alongside the normalised value: the two disagreeing
                // is how a wrong scale shows itself, and a normalised 0 could mean
                // either a light touch or a floor set too high.
                log("✒️  \(action)   [rawPressure \(Int(penPressureRaw))]")
            }
            penBackend.handle(action)
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
        // A contact that began under the pen stays ignored for its whole life.
        if suppressingFingerContact { return }

        let frame = TouchFrame(contact: contact)

        if let frameObserver {
            DispatchQueue.main.async { frameObserver(frame) }
            return
        }
        logActions(engine.process(frame))
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

    private func log(_ message: String) { Log.line(message) }
}
