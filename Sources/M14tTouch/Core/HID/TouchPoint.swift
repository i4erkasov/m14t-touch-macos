import CoreGraphics
import Foundation

/// A single contact on the touch surface at one instant.
///
/// This is the boundary type between HID acquisition and gesture recognition:
/// everything upstream of it deals in `IOHIDValue`s, everything downstream deals
/// only in this. Because it carries the *already mapped* screen `position`, a
/// `GestureRecognizer` never needs `CoordinateMapper`, calibration, or IOKit —
/// which is what makes gesture logic testable with no hardware attached.
struct TouchPoint: Equatable, Sendable {

    /// Contact identifier, for tracking a finger across frames.
    ///
    /// The driver reports a single contact today and always uses `primary`.
    /// The field exists so multi-touch (spec §11) does not have to change the
    /// shape of this type later.
    let id: Int

    /// Position on the target display, in the global screen coordinate space.
    let position: CGPoint

    /// The raw panel coordinate this was mapped from.
    ///
    /// Kept for diagnostics only (spec §14 shows raw X/Y in the UI). Gesture
    /// logic must use `position` — raw values are meaningless without the
    /// calibration that produced them.
    let rawPosition: CGPoint

    /// Whether the finger is in contact with the surface (HID `TipSwitch`).
    let isTouching: Bool

    /// Contact pressure, if the device reports it. Always `nil` today — the
    /// driver does not yet parse a pressure usage (spec §12).
    let pressure: Double?

    /// Monotonic timestamp, in seconds from an arbitrary origin.
    ///
    /// Deliberately not wall-clock time: gesture recognition measures *durations*
    /// (tap duration, long-press delay — spec §7.1, §8), and a wall clock can
    /// jump backwards on time sync, which would make a long press fire early or
    /// never. Only differences between timestamps are meaningful.
    let timestamp: TimeInterval

    /// Identifier used for the single contact the driver reports today.
    static let primary = 0
}

/// All contacts observed at one instant.
///
/// Frames — rather than loose touch points — are what the gesture layer consumes,
/// so that multi-finger gestures (spec §11: two-finger scroll, two-finger tap)
/// can be added by populating `contacts` without reshaping the pipeline.
/// v0.1 always produces exactly one contact.
struct TouchFrame: Equatable, Sendable {

    let contacts: [TouchPoint]

    /// When the frame was assembled. Same basis as `TouchPoint.timestamp`.
    let timestamp: TimeInterval

    /// The contact a single-touch recognizer acts on, or `nil` for an empty frame.
    var primaryContact: TouchPoint? { contacts.first }

    init(contacts: [TouchPoint], timestamp: TimeInterval) {
        self.contacts = contacts
        self.timestamp = timestamp
    }

    /// Wrap a lone contact, adopting its timestamp.
    ///
    /// The common case while the driver is single-touch, and the convenient one
    /// for tests that build a sequence of frames by hand.
    init(contact: TouchPoint) {
        self.contacts = [contact]
        self.timestamp = contact.timestamp
    }
}
