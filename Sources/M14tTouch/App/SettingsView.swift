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

    var body: some View {
        Form {
            Section {
                LabeledContent("Display") {
                    Label(
                        model.status.isConnected ? model.displayName : "Not connected",
                        systemImage: model.status.isConnected ? "circle.fill" : "circle"
                    )
                    .foregroundStyle(model.status.isConnected ? .green : .secondary)
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
                LabeledContent("Connection", value: model.status.isConnected ? "Connected" : "Not connected")
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
                Button("Copy report") { model.copyDiagnostics() }
            } footer: {
                Text("Copies the above, for pasting into a bug report.")
            }
        }
        .formStyle(.grouped)
    }
}
