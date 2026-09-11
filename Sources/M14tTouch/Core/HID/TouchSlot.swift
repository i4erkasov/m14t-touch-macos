import Foundation

/// One of the panel's contact slots, as the descriptor lays them out.
///
/// The M14t declares **five** `Finger` collections, each with its own
/// `TipSwitch`, `Confidence`, `ContactIdentifier`, `X` and `Y`. A value belongs
/// to the collection it was found in, and that — not anything in the value
/// stream — is how contacts are told apart.
///
/// It has to be the collection, because IOKit delivers only values that
/// *changed*: `ContactIdentifier` is reported once when a finger lands and
/// never again, while its coordinates go on arriving interleaved with another
/// finger's. Read as a flat stream, the two are indistinguishable; read per
/// collection, they were never mixed up in the first place.
struct TouchSlot: Equatable {

    var rawX: Double = 0
    var rawY: Double = 0

    /// HID `TipSwitch` — whether this slot currently has a finger on it.
    var isTouching = false

    /// HID `Confidence` — the panel's own judgement that this is a fingertip
    /// rather than a palm. Assumed true until the panel says otherwise, so a
    /// device that never reports it is not treated as touching with nothing.
    var isConfident = true

    /// HID `ContactIdentifier`. Carried for diagnostics: the observed values on
    /// this panel were 0 and 2, so nothing may assume they are consecutive, and
    /// nothing uses them for identity.
    var contactID: Int = 0
}
