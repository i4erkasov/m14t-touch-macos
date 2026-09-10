# Pinch and multi-touch — what was established

Spec §29 asks to *investigate* whether pinch-to-zoom can be generated on macOS.
This is that investigation, recorded before the work is scheduled so it is not
repeated. Nothing here is implemented; it is Phase 2 (spec §11, §29).

## The question splits in two, and the halves have different answers

### Seeing two fingers — possible, but not a small change

The driver reads `X`, `Y` and `TipSwitch` as a single contact. Real multi-touch
HID is repeating collections — contact 0, contact 1 — each with its own
coordinates and `ContactID`.

The obstacle is the delivery mechanism. `IOHIDManagerRegisterInputValueCallback`
hands over values one at a time, so which collection an `X` belongs to has to be
recovered from the element's parent, or the driver has to move to
`IOHIDManagerRegisterInputReportCallback` and parse raw reports against the
descriptor. Either is a real chunk of work, and the second is what the frame
model in `TouchFrame` was shaped for.

**Unknown, and cheap to settle:** whether this panel reports two contacts at all.
Its descriptor declares `ContactID` (0x51), `ContactCount` (0x54) and
`ContactCountMaximum` (0x55), but no values for them were ever observed, because
every probe so far used one finger. A minute with a two-finger probe answers it,
and until it is answered the rest is hypothetical.

### Emitting a zoom — no public way to send a real one

A system pinch is an `NSEvent` of type `.magnify`. There is no public way to
synthesise one: `CGEvent` has no such event type, and `NSEvent` has no public
initialiser for gesture events. Tools that do it use private APIs.

Public alternatives, with what they cost:

| Approach | Works in | Feel |
|---|---|---|
| **⌘ + scroll wheel** | browsers, Preview, most editors | smooth, close to real zoom |
| ⌘+ / ⌘− | anywhere with a View menu | stepped, not a pinch |
| private `.magnify` | everywhere | exactly like a phone |

## Recommendation: ⌘ + scroll, not the private path

The spec amendment that permitted one private API says plainly: *do not use
private APIs for HID, gestures or event injection where public ones will do.*
Cursor hiding earned its exception because no public path exists at all and the
cost of failure is cosmetic. Pinch is different on both counts — a public path
exists and covers browsers and viewers, where zoom is wanted most, and a private
one would sit **on the input path**, so a future macOS breaking it would break a
feature rather than a decoration.

It also fits the architecture already built: a new gesture in the recognizer, a
new `InputAction` case, and an emitter that adds a modifier to the scroll it
already knows how to post.

## Order of work, when it is scheduled

1. Probe whether the panel reports two contacts, and how many it allows.
2. Only then: report-level parsing, so a frame carries every contact.
3. Two-finger gestures on top of that — scroll and right-click first (spec §11),
   since they need the same contact tracking and are simpler to judge.
4. Pinch via ⌘ + scroll last, as the one whose usefulness depends on the app.
