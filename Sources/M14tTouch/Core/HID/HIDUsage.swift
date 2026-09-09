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
        case scanTime = 0x56
    }
}
