import Foundation

/// USB HID usage-page and usage identifiers we care about.
///
/// Grouped into namespaces matching the HID spec so the input handler reads as
/// `HID.Digitizer.tipSwitch` rather than a wall of bare hex literals.
enum HID {

    enum Page: UInt32 {
        case genericDesktop = 0x01
        case digitizer      = 0x0D
    }

    enum GenericDesktop: UInt32 {
        case x = 0x30
        case y = 0x31
    }

    enum Digitizer: UInt32 {
        case tipSwitch = 0x42   // finger touching the surface (1) or lifted (0)
        case touchScreen = 0x04 // device-level usage identifying a touch screen

        /// A counter the panel advances while a contact exists — on this device
        /// by 100 every ~10 ms, so a ~100 Hz tick.
        ///
        /// Used as a report boundary and as a heartbeat, never as a clock: the
        /// descriptor caps it at 65535, which at 100 µs per unit wraps every 6.5
        /// seconds. Durations are measured from a monotonic system timestamp.
        case confidence = 0x47
        case contactIdentifier = 0x51
        case contactCount = 0x54
        case contactCountMaximum = 0x55
        case scanTime = 0x56

        // Collection usages, used to tell the pen's elements from the finger's.
        case pen = 0x02
        case stylus = 0x20
        case finger = 0x22

        // Pen state. Every one of these was observed on the device; tilt and a
        // second barrel switch are declared by the descriptor and never sent,
        // so they are deliberately absent (`M14t_PEN_CAPABILITIES.md`).
        case tipPressure = 0x30
        case inRange = 0x32
        case invert = 0x3C
        case barrelSwitch = 0x44
        case eraser = 0x45
        case batteryStrength = 0x3B
    }
}
