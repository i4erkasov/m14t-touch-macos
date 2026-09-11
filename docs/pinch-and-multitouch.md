# Pinch and multi-touch — what was established

Spec §29 asks to *investigate* whether pinch-to-zoom can be generated on macOS.
This is that investigation — and, since it was written, the implementation.
**Both halves are built and working**: contacts are tracked separately and
spreading two fingers zooms. The corrections below are kept in place rather
than edited away, because two of the conclusions recorded here confidently
turned out to be wrong, and that is worth more to the next reader than a tidy
document.

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

The driver used to overwrite one pair of coordinates from every contact, so two
fingers behaved like one jittering finger. It now keys them by the `Finger`
collection a value was found in — which is forced, not stylistic: IOKit
delivers only values that *changed*, so `ContactID` is sent once when a finger
lands and never again while both fingers' coordinates keep arriving
interleaved. Read flat they are indistinguishable; read per collection they
were never mixed up.

There are **five** such collections, counted from the descriptor, so the panel
holds five fingers.

### Emitting a zoom — no public way to send a real one

A system pinch is an `NSEvent` of type `.magnify`. There is no public way to
synthesise one: `CGEvent` has no such event type, and `NSEvent` has no public
initialiser for gesture events. Tools that do it use private APIs.

Public alternatives, with what they cost:

| Approach | Verdict |
|---|---|
| ⌘ + scroll wheel | **does not zoom.** Measured — see below |
| **⌘= / ⌘−** | works, and is what ships. Stepped, not a pinch |
| private `.magnify` | would be exact, and is out of bounds |

### The correction: ⌘ + scroll does not zoom

This document recommended ⌘ + scroll, on the strength of it being what a mouse
wheel with Command held sends. It does not work, and that was established on
the hardware twice over:

- a scroll event carrying `.maskCommand` was read by the browser as a plain
  scroll, and ran the page to the top;
- holding Command down as a genuine keyboard event, around the same scrolls,
  produced the same plain scroll;
- `⌘=` pressed five times zoomed immediately.

So zoom ships as a keystroke. Two consequences, both real: it goes to the
**frontmost window** rather than to whatever is under the fingers, and it is
stepped by nature — each press is a whole zoom level, which is why the gesture
quantises coarsely and caps a burst.

## Why not the private path

The spec amendment that permitted one private API says plainly: *do not use
private APIs for HID, gestures or event injection where public ones will do.*
Cursor hiding earned its exception because no public path exists at all and the
cost of failure is cosmetic. Pinch is different on both counts — a public path
exists and covers browsers and viewers, where zoom is wanted most, and a private
one would sit **on the input path**, so a future macOS breaking it would break a
feature rather than a decoration.

It also fitted the architecture already built, which is how it turned out: a
new state in the recognizer, a new `InputAction` case, and a new emitter —
a keyboard one, as it happens, rather than the scroll emitter this document
expected.

## Order of work, when it is scheduled

1. Probe whether the panel reports two contacts, and how many it allows.
2. Only then: report-level parsing, so a frame carries every contact.
3. Two-finger gestures on top of that — scroll and right-click first (spec §11),
   since they need the same contact tracking and are simpler to judge.
4. Pinch via ⌘ + scroll last, as the one whose usefulness depends on the app.
