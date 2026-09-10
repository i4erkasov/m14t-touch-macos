# M14t pen capabilities

What the Lenovo ThinkVision M14t and its stylus actually do on macOS 26, as
observed. Written per `M14t_Pen_TZ.md` §39, at the end of the research phase it
requires before any pen code is written.

**Every line here is from a measurement, not from a datasheet or a HID table.**
Where something is declared but never seen, it says so — §2 of the pen spec asks
for exactly that distinction, and it turned out to matter.

Hardware: `Pen and multitouch sensor`, VID `0x2D1F`, PID `0x524C`.
Pen transducer serial: `-2136806051` (stable across sessions, so pens are
distinguishable).

## Hardware / HID

| Capability | Status | Evidence |
|---|---|---|
| Hover X/Y | **SUPPORTED** | ~1400 samples per axis with no contact |
| Proximity (`InRange`) | **SUPPORTED** | 17 clean enter/exit transitions |
| Tip contact (`TipSwitch`) | **SUPPORTED** | 7 press/release pairs, independent of pressure |
| Tip pressure | **SUPPORTED** | 581 samples in one run; full range reached |
| Near button (`Invert`) | **SUPPORTED** | isolated run: 2 presses, nothing else fired |
| Far button (`BarrelSwitch`) | **SUPPORTED** | isolated run: 4 presses, nothing else fired |
| Eraser (`Eraser`) | **SUPPORTED** | driven by the near button while touching |
| Battery level | **SUPPORTED** | `BatteryStrength`, reported unprompted |
| Tilt (`XTilt` / `YTilt`) | **UNSUPPORTED** | see below — a checked absence, not an unobserved one |
| Azimuth / Altitude / Twist | **UNSUPPORTED** | never sent |
| `SecondaryBarrelSwitch` | **UNSUPPORTED** | declared; the pen has only two buttons |

## Collections

Pen and finger are separate collections inside one device. There is no separate
Pen *device* — both interfaces report `usage 0x04` — so they are told apart by
the collection an element sits in, not by which device sent it.

```
TouchScreen / Finger          Pen / Stylus
  TipSwitch                     TipSwitch, BarrelSwitch, Eraser, Invert
  ContactIdentifier  0 … 1      InRange, TipPressure, XTilt, YTilt
  X                  0 … 12372  X                        0 … 30931
  Y                  0 … 6960   Y                        0 … 17399
```

A `Mouse / Pointer` collection is also declared, with two buttons and X/Y over
0…32767. **It never sent anything**, in any test.

`ContactIdentifier 0 … 1` suggests the panel tracks at most two finger contacts.

## Ranges

| | Range | Notes |
|---|---|---|
| Pen X | 0 … 30931 | **Different from the finger's.** Separate calibration required |
| Pen Y | 0 … 17399 | Observed up to 19417 / 15264 in normal use |
| Pressure | 0 … 4095 declared | 4095 reached exactly, so the declared maximum is real |
| Pressure, usable | **≈1350 … 4095** | See below |

**The bottom third of the pressure range cannot be reached.** The lightest
touches that register at all peak at 1367 and 1382 — about 33%. A press lighter
than that does not set `TipSwitch`, so there is no contact to have a pressure
for. Normalising over the declared 0…4095 would therefore start every possible
stroke at a third of full strength, and the whole lower part of any pressure
curve would be dead. Normalise over the usable range instead.

Pressure is monotonic with force. Two ascending series were recorded:
1382 → 1620 → 2389 → 3715 and 1367 → 2337 → 3058 → 4095.

Pressure reads non-zero for a few samples while not touching, at contact
transitions. Contact must be taken from `TipSwitch`, never from a pressure
threshold — which is what pen spec §38 asks for, and now there is a reason.

## Tilt is absent, and the absence was checked

Worth spelling out, because the first two attempts to establish it were not
evidence and one of them was written down as though it were.

The first run tilted only in hover, and many digitizers report orientation only
during contact — so nothing arriving meant nothing. The second pressed the tip
but proved nothing either: the probe reported only tilt, so "no tilt" could not
be told apart from "the pen was never in range".

The third run reported what else was happening alongside:

```
contacts (tip presses): 4
coordinate samples:     6155
pressure samples:       2589   peak 2409
tilt:                   nothing
```

The pen was demonstrably working. **That** is what makes the absence a finding.

## Behaviour

**Buttons work in hover.** Both were pressed and released repeatedly with the
pen off the surface. A right-click on hover is therefore possible without
touching the screen (§26).

**The near button is an eraser, not a button.** Held on its own it sets
`Invert`. Touch the screen while holding it and the device reports `Eraser`
instead of `TipSwitch`:

```
Invert    → 1     pen held in "eraser orientation"
Invert    → 0
Eraser    → 1     the eraser is touching
Eraser    → 0     lifted
Invert    → 0     button released
```

`TipSwitch` never fires during an eraser contact. **The device resolves the
conflict pen spec §27 asks us to resolve** — a left click and an erase cannot
arrive together, by construction.

The far button (`BarrelSwitch`) is an ordinary button and is the one free for
mapping.

## macOS event path

**Tablet events are public API.** Verified by building one:

```
CGEventType.tabletPointer   = 23    CGEventField.tabletEventPointPressure = 19
CGEventType.tabletProximity = 24    CGEventField.tabletEventTiltX / TiltY  = 20 / 21
                                    CGEventField.tabletEventPointButtons   = 18
built a tabletPointer event; pressure read back as 0.4999
```

So pressure does not obviously need a private API, unlike cursor hiding. **Not
yet tested: whether applications honour synthesised tablet events.** That is the
one open question left, and pen spec §18 is right to insist on a prototype
before anything is built on it.

## macOS already handles the pen, and handles it wrongly

Hovering the pen near the M14t moves the system pointer **on the MacBook
screen**. macOS consumes the `Pen / Stylus` collection natively as a pointing
device and applies it relative to wherever the pointer already is, ignoring
which display the pen is over. This is the behaviour pen spec §3 records and §11
calls wrong.

It cannot be fixed by adding absolute positioning alongside it: two sources
would fight, ours jumping and the system's sliding.

**Seizing the device works.** `IOHIDManagerOpen` with
`kIOHIDOptionsTypeSeizeDevice` was granted, delivered 5175 input values to us,
and the pointer stopped moving. So exclusive access is the way to absolute
positioning.

Two consequences to design around:

- seizing takes the **whole** device, finger included. That is acceptable —
  the driver handles finger anyway, and macOS ignores the touchscreen — but it
  means **the pen stops working entirely when the driver is not running**, where
  today it works badly. That is a visible change and belongs in the README.
- the seizure ends with the process, as observed when the probe exited.

## Pressure reaches applications; the eraser does not

Pen spec §18 asks whether applications honour synthesised tablet events. Settled
by experiment rather than argument: a probe application was built that posts
events to itself and prints the `NSEvent` it receives.

**Pressure survives.** A mouse event with `mouseEventSubtype` set to
`kCGEventMouseSubtypeTabletPoint` (1) and `mouseEventPressure` /
`tabletEventPointPressure` set arrives at an ordinary Cocoa application as a
tablet-subtype `NSEvent` with `pressure` intact:

| posted | received |
|---|---|
| `leftMouseDown`, pressure 0.75 | `subtype=tabletPoint  pressure=0.749` |
| `leftMouseDragged`, pressure 0.42 | `subtype=tabletPoint  pressure=0.420` |
| `leftMouseDown`, no subtype | `subtype=mouse  pressure=1.000` |

So pressure is a feature this driver can actually deliver, not merely read.

**But delivering it broke a real application.** Shipped on by default, on the
reasoning that an application which does not understand tablets would ignore the
marking and see the click it always saw. That reasoning is wrong for at least one
real consumer: in a browser-based paint program the pen stopped working
mid-stroke and stayed broken after the button was released. The mechanism is not
yet identified — a stuck button and a confused tablet-state machine in the page
are both consistent with what was seen. The event-level result above still
stands; what does not stand is the assumption that marking events is free.

It is therefore **off by default** and asked for explicitly. Anything that can
stop the pen working must not be the default.


**Proximity does not survive, so the eraser cannot be declared.** An application
learns which end of the pen is in use from `NSEvent.pointingDeviceType`, which is
carried by a `tabletProximity` event. Such an event can be built — `CGEvent.type`
accepts `.tabletProximity`, and `tabletProximityEventPointerType` accepts the
eraser value — but it never arrives. Checked twice, at two levels: neither the
view's `tabletProximity(with:)` nor an `NSEvent` monitor on `.any` at the
application level saw one, while the tablet-subtype strokes posted in the same
run arrived normally. Setting the proximity *subtype* on a `mouseMoved` event
instead is not delivered either.

The consequence is exactly the one pen spec §27 worried about: the near button
held during contact is a real eraser to the hardware and cannot be presented as
one to applications. It stays what `PenTouchAction` already offers — nothing, or
an ordinary stroke.

## What the pipeline costs, measured

Written down because a guess sent this in the wrong direction once. Drawing
lagged after the pointer-return feature landed, and the explanation given at the
time — that warping the pointer blocked the touch queue — is **wrong**. Every
call on the per-sample path was then timed on this machine:

| Call | Per call | At 200 samples/s |
|---|---|---|
| `CGEvent` create + `post` (one pen move) | 19.0 µs | 0.4% of one queue |
| `CGDisplayHideCursor` (re-asserted per sample) | 15.9 µs | 0.3% |
| `CGEvent(source:)?.location` (parking) | 0.3 µs | negligible |
| `CGWarpMouseCursorPosition` | 39.2 µs | once per visit |
| `CGAssociateMouseAndMouseCursorPosition` | 40.4 µs | once per visit |
| `CGDisplayShowCursor` (release, per outstanding hide) | 2.3 µs | 6000 of them = 14 ms |

So a pen sample costs ~35 µs of a queue that has 5000 µs to spend, and
returning the pointer costs 80 µs *once*. Nothing here is a throughput problem,
and the release loop — which looked alarming, since hover accumulates one hide
per sample — is 14 ms after half a minute of hovering.

The one thing on this path that *is* expensive is building the dot's window,
and it is expensive once:

| Step | First time | Every time after |
|---|---|---|
| Construct the overlay window | 27.7 ms | — |
| Show it | 3.2 ms | 0.11 ms |
| Hide it | 1.1 ms | 0.19 ms |
| Move it | — | 0.07 ms |
| Resolve the private cursor symbols | 0.06 ms | — |

31 ms on the main thread is about six pen samples, and it was being paid by the
first stroke after every launch — which is exactly what a stutter that clears up
on its own looks like. The window is now built when the setting is applied, and
its first appearance is spent at alpha zero.

What the delayed return actually fixed was **visible**, not temporal: the pen
loses proximity on every lift between strokes, so the pointer was teleporting
across the desk and back after each stroke. Before optimising this path, measure
it; the numbers above are the baseline.

## Answers to the questions pen spec §42 requires

1. Pen and finger collections — `Pen / Stylus` and `TouchScreen / Finger`, one device.
2. X/Y usages — `0x01:0x30` and `0x01:0x31` in both, with different logical ranges.
3. Reliable proximity — yes, `InRange`.
4. X/Y ranges — pen 0…30931 / 0…17399, finger 0…12372 / 0…6960.
5. TipSwitch — yes, independent of pressure.
6. TipPressure — yes, 0…4095 declared and reached; usable from ≈1350.
7. Button usages visible — two: `Invert` and `BarrelSwitch`.
8. Which physical button is which — near the tip is `Invert`, far is `BarrelSwitch`.
9. Buttons in hover — yes, both.
10. Tilt — no.
11. Eraser — yes, via the near button, reported as `Eraser`.
12. Do pen and finger calibrations match — **no**, different coordinate spaces.
13. Can a tablet event be built with public API — yes, verified.
14–17, 19 — open; they need the injection prototype pen spec §18 asks for.
18. Production backend — decide after 14.
20. Pen vs finger cursor policy — a single owner, since the driver will hold the
    device exclusively and nothing else can move the pointer from it.

## Recommended next step

Pen v0.2 in the spec's plan, plus the injection prototype from §18 — they answer
different halves and neither blocks the other.

What can be built on measurement alone: the pen/finger classifier by collection,
`PenSample`, the `outOfRange → hovering → touching` state machine, absolute
mapping under seizure, hover, tip, both buttons and the eraser.

What must wait for the prototype: whether pressure reaches applications, and
therefore whether a pressure curve is a real setting or a dead one.

What should not be built at all: tilt, and anything that assumes a second barrel
switch.
