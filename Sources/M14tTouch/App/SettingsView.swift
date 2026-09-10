import AppKit
import SwiftUI

/// The settings window.
///
/// A sidebar and a grouped form, which is what macOS settings look like and
/// what `NavigationSplitView` plus `Form(.grouped)` give without any help. There
/// is no custom chrome here on purpose: every control below is a stock one, so
/// it inherits the system's spacing, sizing, focus ring and both appearances
/// rather than approximating them.
struct SettingsView: View {

    @ObservedObject var model: SettingsModel
    @State private var section: Section = .general

    enum Section: String, CaseIterable, Identifiable {
        case general, touch, pen, calibration, diagnostics
        var id: Self { self }

        var title: String {
            switch self {
            case .general:     return "General"
            case .touch:       return "Touch"
            case .pen:         return "Pen"
            case .calibration: return "Calibration"
            case .diagnostics: return "Diagnostics"
            }
        }

        var symbol: String {
            switch self {
            case .general:     return "gearshape"
            case .touch:       return "hand.point.up.left"
            case .pen:         return "pencil.tip"
            case .calibration: return "scope"
            case .diagnostics: return "waveform.path.ecg"
            }
        }
    }

    var body: some View {
        // Laid out directly rather than with NavigationSplitView, which insists
        // on a collapse button in the detail's toolbar. `toolbar(removing:)`
        // does not reach it in a hand-made window, and the button both hid the
        // sections and overlapped the window title. A sidebar that cannot be
        // collapsed needs no control to collapse it.
        HStack(spacing: 0) {
            List(Section.allCases, selection: $section) { section in
                Label(section.title, systemImage: section.symbol).tag(section)
            }
            .listStyle(.sidebar)
            .frame(width: 190)
            .background(SidebarMaterial())

            Divider()

            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 680, minHeight: 460)
    }

    @ViewBuilder
    private var detail: some View {
        switch section {
        case .general:     GeneralSettings(model: model)
        case .touch:       TouchSettings(model: model)
        case .pen:         PenSettings(model: model)
        case .calibration: CalibrationSettings(model: model)
        case .diagnostics: DiagnosticsSettings(model: model)
        }
    }
}

/// The system's own sidebar material.
///
/// The one piece of AppKit here, and deliberately not a hand-drawn background:
/// SwiftUI only supplies this material inside `NavigationSplitView`, which is
/// exactly what had to go, and a flat colour approximating it would read as
/// almost-right, which is worse than plainly wrong. This is the system view the
/// system itself uses.
private struct SidebarMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .sidebar
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

// MARK: - General

private struct GeneralSettings: View {
    @ObservedObject var model: SettingsModel

    /// Green for working, orange for something the user can fix, grey for a
    /// panel that simply is not there. The colour lives in the view because it
    /// is a presentation choice; the model states the fact.
    private var connectionTint: Color {
        if model.status.failure != nil { return .orange }
        return model.status.isConnected ? .green : .secondary
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("Display") {
                    Label(
                        model.displayStatusText,
                        systemImage: model.status.failure == nil && model.status.isConnected
                            ? "circle.fill"
                            : (model.status.failure == nil
                                ? "circle"
                                : "exclamationmark.triangle.fill")
                    )
                    .foregroundStyle(connectionTint)
                    .labelStyle(.titleAndIcon)
                    .imageScale(.small)
                }

                Picker("Touch display", selection: displaySelection) {
                    ForEach(model.selectableDisplays, id: \.index) { display in
                        Text(describe(display)).tag(display.index)
                    }
                }
                .disabled(model.selectableDisplays.count < 2)
            } footer: {
                Text(model.selectableDisplays.count < 2
                     ? "Only displays shaped like the touch surface are listed."
                     : "Which screen your touches land on. Only external displays shaped like the touch surface are listed.")
            }

            if model.canOpenAtLogin {
                Section {
                    Toggle("Open at login", isOn: $model.opensAtLogin)
                    if model.loginNeedsApproval {
                        Button("Approve in Login Items…") { LoginItem.openLoginItemsSettings() }
                    }
                } footer: {
                    Text(model.loginNeedsApproval
                         ? "macOS is holding this until you approve it."
                         : "Touch works only while this app is running.")
                }
            }

            Section {
                ForEach(Permission.allCases, id: \.self) { permission in
                    LabeledContent(permission.title) {
                        if model.isGranted(permission) {
                            Label("Granted", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .labelStyle(.titleAndIcon)
                        } else {
                            Button("Grant…") { model.grant(permission) }
                        }
                    }
                    .help(permission.explanation)
                }
            } header: {
                Text("Permissions")
            } footer: {
                Text("Granted to this app specifically, not to the project.")
            }
        }
        .formStyle(.grouped)
    }

    private var displaySelection: Binding<Int> {
        Binding(
            get: { model.selectedDisplayIndex ?? -1 },
            set: { index in
                if let display = model.selectableDisplays.first(where: { $0.index == index }) {
                    model.selectDisplay(display)
                }
            }
        )
    }

    /// Names the monitor, with its size only to tell two of a kind apart.
    ///
    /// Listing them by resolution read as a resolution setting, which is not
    /// what this chooses.
    private func describe(_ display: DisplayInfo) -> String {
        let name = display.name ?? (display.isBuiltin ? "Built-in display" : "Display \(display.index)")
        return "\(name) — \(Int(display.bounds.width)) × \(Int(display.bounds.height))"
    }
}

// MARK: - Touch

private struct TouchSettings: View {
    @ObservedObject var model: SettingsModel

    private var gestures: Binding<GestureConfiguration> { $model.settings.gestures }

    var body: some View {
        Form {
            Section {
                Toggle("Enable touch", isOn: $model.settings.enabled)
                Picker("Behaviour", selection: $model.settings.mode) {
                    Text("Touchscreen").tag(TouchMode.touchscreen)
                    Text("Mouse").tag(TouchMode.mouse)
                }
            } footer: {
                Text(model.settings.mode == .touchscreen
                     ? "Tap to click, swipe to scroll, press and hold to drag."
                     : "A finger presses and drags the pointer, as a mouse would.")
            }

            if model.settings.mode == .touchscreen {
                Section("Gestures") {
                    Toggle("Tap to click", isOn: gestures.tapEnabled)
                    Toggle("One-finger scroll", isOn: gestures.oneFingerScrollEnabled)
                    Toggle("Long press to drag", isOn: gestures.longPressDragEnabled)
                }

                Section {
                    Toggle("Natural scrolling", isOn: gestures.naturalScroll)
                    LabeledContent("Sensitivity") {
                        Slider(value: gestures.scrollSensitivity, in: 0.25...4)
                    }
                    Stepper(
                        "Starts after \(Int(model.settings.gestures.scrollThreshold)) px",
                        value: gestures.scrollThreshold, in: 1...60, step: 1
                    )
                } header: {
                    Text("Scrolling")
                } footer: {
                    Text("Natural scrolling moves the content with your finger.")
                }

                Section {
                    Stepper(
                        "Hold for \(Int(model.settings.gestures.longPressDelay * 1000)) ms",
                        value: gestures.longPressDelay, in: 0.1...2, step: 0.05
                    )
                    .disabled(!model.settings.gestures.longPressDragEnabled)
                } header: {
                    Text("Drag")
                }

                Section {
                    Picker("Hide pointer", selection: gestures.cursorHiding) {
                        Text("Never").tag(CursorHiding.never)
                        Text("While scrolling").tag(CursorHiding.scrolling)
                        Text("While touching").tag(CursorHiding.touching)
                    }
                    Toggle("Restore afterwards", isOn: gestures.restoreCursor)
                } header: {
                    Text("Pointer")
                } footer: {
                    Text("Hiding only holds while the pointer is still, so a tap or a drag shows it again.")
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Pen

private struct PenSettings: View {
    @ObservedObject var model: SettingsModel

    private var pen: Binding<PenConfiguration> { $model.settings.pen }

    /// The stored colour as the colour well wants it.
    ///
    /// A bridge rather than a stored `Color`, because a preferences file cannot
    /// hold one — see `RGBAColor`.
    private var ringColor: Binding<Color> {
        Binding(
            get: { model.settings.pen.pointerColor.color },
            set: { model.settings.pen.pointerColor = RGBAColor($0, fallback: model.settings.pen.pointerColor) }
        )
    }

    var body: some View {
        Form {
            Section {
                Toggle("Handle the stylus", isOn: $model.settings.penEnabled)
                Toggle("Move the pointer while hovering", isOn: pen.pointerFollowsHover)
                    .disabled(!model.settings.penEnabled)
            } header: {
                Text("Stylus")
            } footer: {
                Text("Handling the stylus takes the panel from macOS. The pen does nothing while this app is not running.")
            }

            if model.settings.penEnabled {
                Section {
                    Picker("Hover action", selection: pen.nearButtonHover) {
                        ForEach(PenButtonMapping.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    Picker("Touch action", selection: pen.nearButtonTouch) {
                        ForEach(PenTouchAction.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                } header: {
                    Text("Near button")
                } footer: {
                    Text(model.settings.pen.nearButtonTouch == .eraser
                         ? "The hover action happens on release, so reaching to erase does not click first. Eraser strokes reach only apps that understand a tablet eraser."
                         : "The hover action happens on release, so reaching to draw does not click first.")
                }

                Section {
                    Picker("Action", selection: pen.farButton) {
                        ForEach(PenButtonMapping.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                } header: {
                    Text("Far button")
                } footer: {
                    Text("Both buttons work while hovering, without touching the screen.")
                }

                Section {
                    Picker("Pointer", selection: pen.pointer) {
                        ForEach(PenPointerStyle.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    Toggle("Return the pointer when the pen leaves", isOn: pen.restoresPointerOnExit)
                    if model.settings.pen.pointer == .dot {
                        ColorPicker("Ring colour", selection: ringColor, supportsOpacity: false)
                        LabeledContent("Size") {
                            Slider(value: pen.pointerSize, in: 6...32, step: 1) {
                                Text("Size")
                            } minimumValueLabel: {
                                Text("6")
                            } maximumValueLabel: {
                                Text("32")
                            }
                            .labelsHidden()
                        }
                    }
                } header: {
                    Text("Pointer")
                } footer: {
                    Text(model.settings.pen.pointer == .dot
                         ? "The dot is drawn over everything and the system arrow is hidden while the pen is near. Its middle stays dark so it can be seen on a pale window; the ring carries the colour. Hiding the arrow needs the same facility as Touch → Cursor; where that is unavailable, both are visible."
                         : "The pointer macOS would show anyway.")
                }

                Section {
                    Toggle("Send pressure to applications", isOn: pen.sendsPressure)
                } header: {
                    Text("Pressure")
                } footer: {
                    Text("Marks strokes as coming from a tablet, which is what carries pressure — an ordinary click can only be full or none. Off by default: some applications handle these events badly, and one browser-based drawing app stopped responding to the pen entirely. Turn it off again if the pen misbehaves. An eraser stroke cannot be marked as one either way.")
                }

                Section {
                    Toggle("Ignore touches while the pen is near", isOn: pen.palmRejection)
                } header: {
                    Text("Palm rejection")
                } footer: {
                    Text("Only touches that begin while the pen is near are ignored.")
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Calibration

private struct CalibrationSettings: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        Form {
            Section {
                if let calibration = model.calibration {
                    LabeledContent("Horizontal", value: "\(Int(calibration.xMin)) – \(Int(calibration.xMax))")
                    LabeledContent("Vertical", value: "\(Int(calibration.yMin)) – \(Int(calibration.yMax))")
                } else {
                    LabeledContent("Calibration", value: "None saved")
                }
            } header: {
                Text("Current")
            } footer: {
                Text("Stored per display, so a panel is recognised again after replugging.")
            }

            Section("Orientation") {
                Toggle("Flip horizontally", isOn: $model.settings.invertX)
                Toggle("Flip vertically", isOn: $model.settings.invertY)
            }

            Section {
                if let start = model.startCalibration {
                    Button("Calibrate…", action: start)
                }
                Button("Reset", role: .destructive) { model.resetCalibration() }
                    .disabled(model.calibration == nil)
            } footer: {
                Text("Calibrating shows four targets on the panel to touch.")
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Diagnostics

private struct DiagnosticsSettings: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        Form {
            Section("Device") {
                LabeledContent("Display", value: model.displayName)
                LabeledContent("Touch interface", value: model.status.deviceName ?? "—")
                LabeledContent("Identifiers", value: model.status.identifiers ?? "—")
                LabeledContent("Connection", value: model.connectionSummary)
            }

            Section("Displays") {
                ForEach(model.displays, id: \.index) { display in
                    LabeledContent(
                        "\(Int(display.bounds.width)) × \(Int(display.bounds.height))",
                        value: "at \(Int(display.bounds.minX)), \(Int(display.bounds.minY))"
                    )
                }
            }

            Section {
                LabeledContent("Pressure", value: "Reported, 0–4095")
                LabeledContent("Tilt", value: "Not reported")
                LabeledContent("Buttons", value: "Two, both work while hovering")
                LabeledContent("Eraser", value: "The near button, in hardware")
            } header: {
                Text("Stylus")
            } footer: {
                // What the panel does was measured, not read off a datasheet;
                // a live view of the HID stream is a later piece of work and is
                // not implied here.
                Text("Established by testing this panel. See M14t_PEN_CAPABILITIES.md.")
            }

            Section {
                LabeledContent("Reporting", value: live.activity)
                LabeledContent("Source", value: live.sourceName)
                LabeledContent("Contact", value: live.contactDescription)
                LabeledContent("Panel coordinates", value: live.rawDescription)
                LabeledContent("On screen", value: live.screenDescription)
                LabeledContent("Pressure", value: live.pressureDescription)
                LabeledContent("Pen buttons", value: live.buttonDescription)
            } header: {
                Text("Live input")
            } footer: {
                Text("What the panel is reporting as you touch it. Panel coordinates are before calibration — the numbers to quote when a touch lands in the wrong place. \(live.contactCountNote)")
            }

            Section {
                Toggle("Log pen actions to the system log", isOn: $model.logsInput)
            } header: {
                Text("Logging")
            } footer: {
                Text("Records every action the pen produces — hovering, contacts, buttons — so a problem can be read back afterwards:\n\nlog show --last 5m --predicate 'subsystem == \"com.m14ttouch.app\"' --info\n\nSwitch it off when done; it is verbose.")
                    .textSelection(.enabled)
            }

            Section {
                Button("Copy report") { model.copyDiagnostics() }
            } footer: {
                Text("Copies the above, for pasting into a bug report.")
            }
        }
        .formStyle(.grouped)
        // Only while someone is looking: the driver counts nothing and
        // publishes nothing until this pane is on screen.
        .onAppear { model.setLiveMonitoring?(true) }
        .onDisappear { model.setLiveMonitoring?(false) }
    }

    private var live: LiveInput { model.live }
}

/// How the live snapshot reads in the pane.
///
/// On the value rather than in the view because every one of these is a
/// judgement about absence — "not reported" and "nothing" are different
/// answers, and the difference is the whole point of a diagnostics pane.
extension LiveInput {

    var activity: String {
        valuesPerSecond > 0 ? "\(valuesPerSecond) values/s" : "nothing arriving"
    }

    var sourceName: String {
        switch source {
        case .pen:    return penInRange ? "Pen, in range" : "Pen"
        case .finger: return "Finger"
        case .other:  return "Other"
        case nil:     return "—"
        }
    }

    var contactDescription: String {
        let touch = isTouching ? "touching" : "not touching"
        guard let contactCount else { return touch }
        let maximum = contactCountMaximum.map { " of \($0)" } ?? ""
        return "\(touch), \(contactCount)\(maximum)"
    }

    var rawDescription: String {
        guard let rawX, let rawY else { return "—" }
        return "\(Int(rawX)), \(Int(rawY))"
    }

    var screenDescription: String {
        guard let screen else { return "—" }
        return "\(Int(screen.x)), \(Int(screen.y))"
    }

    var pressureDescription: String {
        guard let rawPressure, let pressure else { return "—" }
        return String(format: "%d raw, %.2f scaled", Int(rawPressure), pressure)
    }

    var buttonDescription: String {
        var held: [String] = []
        if penButtons.contains(.barrel) { held.append("far") }
        if penButtons.contains(.eraserMode) { held.append("near") }
        return held.isEmpty ? "none held" : held.joined(separator: ", ")
    }

    /// Says what the absence of a contact count means, rather than leaving a
    /// dash to be interpreted.
    var contactCountNote: String {
        contactCount == nil
            ? "This panel has not reported a contact count; if it never does with two fingers down, it does not report multi-touch."
            : ""
    }
}
