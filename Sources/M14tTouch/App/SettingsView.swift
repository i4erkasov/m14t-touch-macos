import SwiftUI

/// The settings window (spec §14).
struct SettingsView: View {

    @ObservedObject var model: SettingsModel

    var body: some View {
        TabView {
            GeneralTab(model: model).tabItem { Label("General", systemImage: "gearshape") }
            TouchTab(model: model).tabItem { Label("Touch", systemImage: "hand.point.up.left") }
            CalibrationTab(model: model).tabItem { Label("Calibration", systemImage: "scope") }
        }
        .frame(width: 460, height: 420)
    }
}

// MARK: - General

private struct GeneralTab: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        Form {
            Section("Device") {
                LabeledContent("Status") {
                    Label(
                        model.status.isConnected
                            ? (model.status.deviceName ?? "Connected")
                            : "No touch device",
                        systemImage: model.status.isConnected ? "checkmark.circle" : "xmark.circle"
                    )
                    .foregroundStyle(model.status.isConnected ? .green : .secondary)
                }
            }

            Section("Permissions") {
                ForEach(Permission.allCases, id: \.self) { permission in
                    LabeledContent {
                        if model.isGranted(permission) {
                            Label("Granted", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        } else {
                            Button("Grant…") { model.grant(permission) }
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(permission.title)
                            Text(permission.explanation)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section("Target display") {
                // Listed rather than typed as an index: the number means nothing
                // to anyone, and it changes when monitors are replugged.
                Picker("Display", selection: Binding(
                    get: { model.selectedDisplayIndex ?? -1 },
                    set: { index in
                        if let display = model.displays.first(where: { $0.index == index }) {
                            model.selectDisplay(display)
                        }
                    }
                )) {
                    ForEach(model.displays, id: \.index) { display in
                        Text(describe(display)).tag(display.index)
                    }
                }
                .labelsHidden()
            }

            Section("Touch") {
                Toggle("Enable touch", isOn: $model.settings.enabled)
            }
        }
        .formStyle(.grouped)
    }

    private func describe(_ display: DisplayInfo) -> String {
        let size = "\(Int(display.bounds.width)) × \(Int(display.bounds.height))"
        return display.isBuiltin ? "\(size) — built-in" : size
    }
}

// MARK: - Touch

private struct TouchTab: View {
    @ObservedObject var model: SettingsModel

    private var gestures: Binding<GestureConfiguration> { $model.settings.gestures }

    var body: some View {
        Form {
            Section("Mode") {
                Picker("Mode", selection: $model.settings.mode) {
                    Text("Touchscreen").tag(TouchMode.touchscreen)
                    Text("Mouse").tag(TouchMode.mouse)
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
            }

            // Only touchscreen mode has gestures to configure; mouse mode maps a
            // contact straight onto the button and has nothing to decide.
            if model.settings.mode == .touchscreen {
                Section("Gestures") {
                    Toggle("Tap to click", isOn: gestures.tapEnabled)
                    Toggle("One-finger scroll", isOn: gestures.oneFingerScrollEnabled)
                    Toggle("Long press to drag", isOn: gestures.longPressDragEnabled)
                }

                Section("Scrolling") {
                    Toggle("Natural scrolling", isOn: gestures.naturalScroll)
                    LabeledContent("Sensitivity") {
                        Slider(value: gestures.scrollSensitivity, in: 0.25...4)
                    }
                    Stepper(
                        "Starts after \(Int(model.settings.gestures.scrollThreshold)) px",
                        value: gestures.scrollThreshold, in: 1...60, step: 1
                    )
                }

                Section("Drag") {
                    Stepper(
                        "Hold for \(Int(model.settings.gestures.longPressDelay * 1000)) ms",
                        value: gestures.longPressDelay, in: 0.1...2, step: 0.05
                    )
                    .disabled(!model.settings.gestures.longPressDragEnabled)
                }

                Section("Cursor") {
                    Picker("While touching", selection: gestures.cursorHiding) {
                        Text("Keep visible").tag(CursorHiding.never)
                        Text("Hide while scrolling").tag(CursorHiding.scrolling)
                        Text("Hide while touching").tag(CursorHiding.touching)
                    }
                    Toggle("Put the pointer back afterwards", isOn: gestures.restoreCursor)
                    Text("Hiding only holds while the pointer is still, so a tap or a drag will show it again.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Calibration

private struct CalibrationTab: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        Form {
            Section("Current calibration") {
                if let calibration = model.calibration {
                    LabeledContent("X", value: "\(Int(calibration.xMin)) … \(Int(calibration.xMax))")
                    LabeledContent("Y", value: "\(Int(calibration.yMin)) … \(Int(calibration.yMax))")
                } else {
                    Text("None saved — the range the panel reports is used instead.")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Orientation") {
                Toggle("Invert horizontally", isOn: $model.settings.invertX)
                Toggle("Invert vertically", isOn: $model.settings.invertY)
            }

            Section {
                Button("Reset calibration", role: .destructive) { model.resetCalibration() }
                    .disabled(model.calibration == nil)
                // No Calibrate button here on purpose: guided calibration is
                // v0.4, and a button that silently started learning bounds
                // without telling you where to touch would be worse than none.
                Text("Calibrating from the app arrives in a later version. For now: m14ttouch --auto-calibrate, then touch all four corners.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
