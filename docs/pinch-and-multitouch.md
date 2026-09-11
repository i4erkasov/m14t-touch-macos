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

**Settled: it does.** A two-finger probe was finally run — one finger, then two,
then two spread apart — with every HID value traced. The panel reports genuine
multi-touch.

Each contact arrives as its own small report:

    X = 9499 · ContactID = 2 · Confidence = 1 · TipSwitch = 1 · Y = 3534

and the reports interleave. During the spread, the X values alternate between
two clusters moving in opposite directions:

    9415 9824 9423 9819 9429 9815 9434 9812 9438 9809 9442 9806 …

one rising, one falling — the two fingers, sampled alternately. `TipSwitch`
went down and up exactly five times for the five contacts made.

Two details matter for whoever implements this:

- **`ContactID` is the only identity available.** Observed values were `0` and
  `2` — not `0` and `1`, so nothing may assume they are consecutive or small.
- **`ContactCount` (0x54) is never sent**, nor `ContactCountMaximum`. How many
  fingers are down has to be inferred from which contact IDs are currently
  reporting `TipSwitch = 1`, not read.

There is also `Confidence` (0x47), which the panel sets to 0 or 1 — the
hardware's own opinion of whether a contact is a real fingertip. That is palm
rejection available for free, and better informed than ours.

The driver currently overwrites one pair of coordinates from every contact, so
two fingers behave like one jittering finger. The data was always there.

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
